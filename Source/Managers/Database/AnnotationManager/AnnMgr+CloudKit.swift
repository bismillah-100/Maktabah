//
//  AnnMgr+CloudKit.swift
//  Maktabah
//

import Foundation

extension AnnotationManager {
    // MARK: - Sync Pending Helpers

    func addPendingSync(ckRecordId: String, operation: String) throws {
        guard let _db else { return }
        if operation == "upload" {
            let checkSql = "SELECT COUNT(*) FROM sync_pending WHERE ck_record_id = ? AND operation = 'delete';"
            if let count = try _db.fetch(
                query: checkSql,
                parameters: [ckRecordId],
                mapping: { $0.int64(at: 0) }).first,
                count > 0 {
                return // Delete wins
            }
        } else if operation == "delete" {
            let delSql = "DELETE FROM sync_pending WHERE ck_record_id = ? AND operation = 'upload';"
            try _db.execute(query: delSql, parameters: [ckRecordId])
        }
        let now = Int64(Date().timeIntervalSince1970)
        let sql = "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES (?, ?, ?);"
        try _db.execute(query: sql, parameters: [ckRecordId, operation, now])
    }

    func removePendingSync(ckRecordIds: [String]) {
        guard let _db else { return }
        let placeholders = String(repeating: "?,", count: ckRecordIds.count).dropLast()
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

    @discardableResult
    func applyCloudKitChanges(annotationsToSave: [Annotation], recordIdsToDelete: [String]) -> Bool {
        guard let _db else { return false }

        var addedAnnotations: [Annotation] = []
        var updatedAnnotations: [Annotation] = []
        var deletedAnnotations: [Annotation] = []

        do {
            try transaction {
                // Process Deletions
                if !recordIdsToDelete.isEmpty {
                    let chunkSize = 500
                    for chunkStart in stride(from: 0, to: recordIdsToDelete.count, by: chunkSize) {
                        let chunkEnd = min(chunkStart + chunkSize, recordIdsToDelete.count)
                        let chunk = Array(recordIdsToDelete[chunkStart..<chunkEnd])

                        let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                        let findSql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IN (\(placeholders))"

                        let rows = try _db.fetch(query: findSql, parameters: chunk, mapping: { ($0.int64(at: 0), self.makeAnnotation(from: $0)) })

                        if !rows.isEmpty {
                            let localIds = rows.map { $0.0 }
                            let anns = rows.map { $0.1 }
                            deletedAnnotations.append(contentsOf: anns)

                            let idPlaceholders = String(repeating: "?,", count: localIds.count).dropLast()
                            try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagAnnotationId) IN (\(idPlaceholders));", parameters: localIds)
                            try exec("DELETE FROM \(annotationsTable) WHERE \(colAnnId) IN (\(idPlaceholders));", parameters: localIds)
                        }
                    }
                }

                // Pre-fetch all existing annotations by ckRecordId to avoid N+1 queries
                var existingAnnotations: [String: (id: Int64, lastModified: Int64)] = [:]
                let ckIdsToSave = annotationsToSave.compactMap { $0.ckRecordId }
                if !ckIdsToSave.isEmpty {
                    let chunkSize = 500
                    for i in stride(from: 0, to: ckIdsToSave.count, by: chunkSize) {
                        let chunk = Array(ckIdsToSave[i..<min(i + chunkSize, ckIdsToSave.count)])
                        let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                        let findSql = "SELECT \(colAnnCkRecordId), \(colAnnId), \(colAnnLastModified) FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IN (\(placeholders))"
                        let rows = try _db.fetch(query: findSql, parameters: chunk, mapping: { ($0.string(at: 0) ?? "", $0.int64(at: 1), $0.int64(at: 2)) })
                        for row in rows {
                            existingAnnotations[row.0] = (id: row.1, lastModified: row.2)
                        }
                    }
                }

                // Process Saves/Updates
                for var ann in annotationsToSave {
                    guard let ckId = ann.ckRecordId else { continue }

                    var existingLocalId: Int64 = -1
                    var localLastMod: Int64 = 0

                    if let existing = existingAnnotations[ckId] {
                        existingLocalId = existing.id
                        localLastMod = existing.lastModified
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
                                existingLocalId,
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
                            ann.lastModified ?? 0,
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
                    guard let self else { return }
                    clearAllCaches()
                    invalidateTree()
                    buildAnnotationTree()
                }
            }
        } catch {
            print("AnnotationManager: Failed to apply CloudKit changes - \(error)")
            return false
        }
        return true
    }
}
