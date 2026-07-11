//
//  AnnotationManager+CloudKit.swift
//  Maktabah
//

import Foundation

extension AnnotationManager {
    // MARK: - Sync Pending Helpers

    func addPendingSync(ckRecordId: String, operation: String) {
        guard let _db else { return }
        let sql = "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES (?, ?, ?);"
        try? _db.execute(query: sql, parameters: [ckRecordId, operation, now])
    }

    func removePendingSync(ckRecordIds: [String]) {
        guard let _db else { return }
        let placeholders = ckRecordIds.map { _ in "?" }.joined(separator: ",")
        let sql = "DELETE FROM sync_pending WHERE ck_record_id IN (\(placeholders));"
        try? _db.execute(query: sql, parameters: ckRecordIds)
    }

    func fetchPendingSync(operation: String) -> [String] {
        guard let _db else { return [] }
        let sql = "SELECT ck_record_id FROM sync_pending WHERE operation = ? ORDER BY queued_at ASC;"
        return (try? _db.fetch(query: sql, parameters: [operation]) { $0.string(at: 0) ?? "" }) ?? []
    }

    // MARK: - Nuke Database

    func nukeDatabase() {
        do {
            try transaction {
                try exec("DELETE FROM \(annotationTagsTable);")
                try exec("DELETE FROM \(annotationsTable);")
                try exec("DELETE FROM \(tagsTable);")
            }
            clearAllCaches()
            invalidateTree()
            #if DEBUG
            print("AnnotationManager: Local database purged.")
            #endif
        } catch {
            print("AnnotationManager: Failed to purge database - \(error)")
        }
    }

    // MARK: - Apply CloudKit Changes

    func applyCloudKitChanges(annotationsToSave: [Annotation], recordIdsToDelete: [String]) {
        guard let _db else { return }

        var addedAnnotations: [Annotation] = []
        var updatedAnnotations: [Annotation] = []
        var deletedAnnotations: [Annotation] = []

        do {
            try transaction {
                // Process Deletions
                for ckId in recordIdsToDelete {
                    let findSql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnCkRecordId) = ? LIMIT 1"
                    if let row = try _db.fetch(query: findSql, parameters: [ckId], mapping: { ($0.int64(at: 0), self.makeAnnotation(from: $0)) }).first {
                        let localId = row.0
                        let ann = row.1
                        deletedAnnotations.append(ann)
                        try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagAnnotationId) = ?;", parameters: [localId])
                        try exec("DELETE FROM \(annotationsTable) WHERE \(colAnnId) = ?;", parameters: [localId])
                    }
                }

                // Process Saves/Updates
                for var ann in annotationsToSave {
                    guard let ckId = ann.ckRecordId else { continue }

                    var existingLocalId: Int64 = -1
                    var localLastMod: Int64 = 0

                    let findSql = "SELECT \(colAnnId), \(colAnnLastModified) FROM \(annotationsTable) WHERE \(colAnnCkRecordId) = ? LIMIT 1"
                    if let row = try _db.fetch(query: findSql, parameters: [ckId], mapping: { ($0.int64(at: 0), $0.int64(at: 1)) }).first {
                        existingLocalId = row.0
                        localLastMod = row.1
                    }

                    if existingLocalId != -1 {
                        // Update existing
                        ann.id = existingLocalId
                        let remoteLastMod = ann.lastModified ?? 0

                        if remoteLastMod >= localLastMod {
                            let updateSql = "UPDATE \(annotationsTable) SET \(colAnnBkId) = ?, \(colAnnContentId) = ?, \(colAnnStart) = ?, \(colAnnLength) = ?, \(colAnnStartDiac) = ?, \(colAnnLengthDiac) = ?, \(colAnnColor) = ?, \(colAnnType) = ?, \(colAnnNote) = ?, \(colAnnLastModified) = ?, \(colAnnPart) = ?, \(colAnnPage) = ? WHERE \(colAnnId) = ?;"

                            let params: [Any] = [
                                ann.bkId,
                                ann.contentId,
                                ann.range.location,
                                ann.range.length,
                                ann.rangeDiacritics.location,
                                ann.rangeDiacritics.length,
                                ann.colorHex,
                                ann.type.rawValue,
                                ann.note ?? NSNull(),
                                ann.lastModified ?? 0,
                                ann.part,
                                ann.page,
                                existingLocalId
                            ]

                            try _db.execute(query: updateSql, parameters: params)
                            try self.replaceTags(self.sanitizeTagNames(ann.tags), for: existingLocalId)
                            updatedAnnotations.append(ann)
                        }
                    } else {
                        // Insert new
                        let insertSql = """
                        INSERT OR REPLACE INTO \(annotationsTable) (
                            \(colAnnBkId), \(colAnnContentId), \(colAnnStart), \(colAnnLength),
                            \(colAnnStartDiac), \(colAnnLengthDiac), \(colAnnColor), \(colAnnType),
                            \(colAnnNote), \(colAnnCreatedAt), \(colAnnContext), \(colAnnPart),
                            \(colAnnPage), \(colAnnCkRecordId), \(colAnnLastModified)
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                        """

                        let params: [Any] = [
                            ann.bkId,
                            ann.contentId,
                            ann.range.location,
                            ann.range.length,
                            ann.rangeDiacritics.location,
                            ann.rangeDiacritics.length,
                            ann.colorHex,
                            ann.type.rawValue,
                            ann.note ?? NSNull(),
                            ann.createdAt,
                            ann.context,
                            ann.part,
                            ann.page,
                            ckId,
                            ann.lastModified ?? 0
                        ]

                        try _db.execute(query: insertSql, parameters: params)
                        let rowId = _db.lastInsertRowId()

                        if rowId != -1 {
                            ann.id = rowId
                            try self.replaceTags(self.sanitizeTagNames(ann.tags), for: rowId)
                            addedAnnotations.append(ann)
                        }
                    }
                }

                try self.deleteUnusedTags()
            }

            let totalChanges = addedAnnotations.count + updatedAnnotations.count + deletedAnnotations.count

            if totalChanges > 0, totalChanges < 100 {
                // Incremental Cache Update
                let affectedContentKeys = Set(
                    (addedAnnotations + updatedAnnotations + deletedAnnotations).map {
                        ContentKey(bkId: $0.bkId, contentId: $0.contentId)
                    }
                )
                let affectedBookIds = Set(
                    (addedAnnotations + updatedAnnotations + deletedAnnotations).map(\.bkId)
                )
                _cacheQueue.sync {
                    _cachedAllTagNames = nil

                    for ann in deletedAnnotations {
                        guard let id = ann.id else { continue }
                        _cacheById.removeValue(forKey: id)
                        _cacheTagsByAnnotationId.removeValue(forKey: id)
                    }

                    for ann in addedAnnotations {
                        guard let id = ann.id else { continue }
                        _cacheById[id] = ann
                        _cacheTagsByAnnotationId[id] = ann.tags
                    }

                    for ann in updatedAnnotations {
                        guard let id = ann.id else { continue }
                        _cacheById[id] = ann
                        _cacheTagsByAnnotationId[id] = ann.tags
                    }

                    // Per-page and per-book caches must not be rebuilt from a partial CloudKit delta,
                    // or reader views can observe only the changed annotations for a page.
                    for key in affectedContentKeys {
                        _cacheByContent.removeValue(forKey: key)
                    }
                    for bkId in affectedBookIds {
                        _cacheByBook.removeValue(forKey: bkId)
                    }
                }

                // Incremental Tree Update (UI)
                for ann in deletedAnnotations {
                    if let id = ann.id { removeAnnotationFromTree(id: id, deletedAnnotation: ann, uploadToCloudKit: false) }
                }
                for ann in addedAnnotations {
                    addAnnotationToTree(ann, uploadToCloudKit: false)
                }
                for ann in updatedAnnotations {
                    updateAnnotationInTree(ann, uploadToCloudKit: false)
                }
            } else if totalChanges >= 100 {
                // Bulk Update: Reload Everything
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.clearAllCaches()
                    self.invalidateTree()
                    self.buildAnnotationTree()
                }
            }
        } catch {
            print("AnnotationManager: Failed to apply CloudKit changes - \(error)")
        }
    }
}
