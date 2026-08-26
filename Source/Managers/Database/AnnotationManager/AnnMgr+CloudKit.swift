//
//  AnnMgr+CloudKit.swift
//  Maktabah
//

import Foundation

extension AnnotationManager {
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
                deletedAnnotations = try processCloudKitDeletions(db: _db, recordIdsToDelete: recordIdsToDelete)

                let ckIdsToSave = annotationsToSave.compactMap(\.ckRecordId)
                let existingAnnotations = try fetchExistingAnnotationMetadata(db: _db, ckIds: ckIdsToSave)

                for ann in annotationsToSave {
                    guard let ckId = ann.ckRecordId else { continue }
                    let existing = existingAnnotations[ckId]
                    let result = try processCloudKitSave(db: _db, ann: ann, existing: existing)
                    if let added = result.added {
                        addedAnnotations.append(added)
                    }
                    if let updated = result.updated {
                        updatedAnnotations.append(updated)
                    }
                }

                try self.deleteUnusedTags()
            }

            let totalChanges = addedAnnotations.count + updatedAnnotations.count + deletedAnnotations.count

            if totalChanges > 0, totalChanges < 100 {
                applyIncrementalCloudKitCacheAndTree(
                    added: addedAnnotations,
                    updated: updatedAnnotations,
                    deleted: deletedAnnotations
                )
            } else if totalChanges >= 100 {
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

    private func processCloudKitDeletions(
        db: SQLiteDatabase,
        recordIdsToDelete: [String]
    ) throws -> [Annotation] {
        guard !recordIdsToDelete.isEmpty else { return [] }
        var deletedAnnotations: [Annotation] = []

        for chunk in recordIdsToDelete.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let findSql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IN (\(placeholders))"

            let rows = try db.fetch(query: findSql, parameters: chunk, mapping: { ($0.int64(at: 0), self.makeAnnotation(from: $0)) })

            if !rows.isEmpty {
                let localIds = rows.map(\.0)
                let anns = rows.map(\.1)
                deletedAnnotations.append(contentsOf: anns)

                let idPlaceholders = String(repeating: "?,", count: localIds.count).dropLast()
                try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagAnnotationId) IN (\(idPlaceholders));", parameters: localIds)
                try exec("DELETE FROM \(annotationsTable) WHERE \(colAnnId) IN (\(idPlaceholders));", parameters: localIds)
            }
        }
        return deletedAnnotations
    }

    private func fetchExistingAnnotationMetadata(
        db: SQLiteDatabase,
        ckIds: [String]
    ) throws -> [String: (id: Int64, lastModified: Int64)] {
        var existingAnnotations: [String: (id: Int64, lastModified: Int64)] = [:]
        guard !ckIds.isEmpty else { return existingAnnotations }

        for chunk in ckIds.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let findSql = "SELECT \(colAnnCkRecordId), \(colAnnId), \(colAnnLastModified) FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IN (\(placeholders))"
            let rows = try db.fetch(query: findSql, parameters: chunk, mapping: { ($0.string(at: 0) ?? "", $0.int64(at: 1), $0.int64(at: 2)) })
            for row in rows {
                existingAnnotations[row.0] = (id: row.1, lastModified: row.2)
            }
        }
        return existingAnnotations
    }

    private func processCloudKitSave(
        db: SQLiteDatabase,
        ann: Annotation,
        existing: (id: Int64, lastModified: Int64)?
    ) throws -> (added: Annotation?, updated: Annotation?) {
        guard ann.ckRecordId != nil else { return (nil, nil) }

        if let existing {
            let remoteLastMod = ann.lastModified ?? 0
            if remoteLastMod >= existing.lastModified {
                let updated = try updateCloudKitAnnotation(db: db, ann: ann, existingId: existing.id)
                return (nil, updated)
            }
            return (nil, nil)
        } else {
            let added = try insertCloudKitAnnotation(db: db, ann: ann)
            return (added, nil)
        }
    }

    private func updateCloudKitAnnotation(
        db: SQLiteDatabase,
        ann: Annotation,
        existingId: Int64
    ) throws -> Annotation {
        var annCopy = ann
        annCopy.id = existingId
        let updateSql = "UPDATE \(annotationsTable) SET \(colAnnBkId) = ?, \(colAnnContentId) = ?, \(colAnnStart) = ?, \(colAnnLength) = ?, \(colAnnStartDiac) = ?, \(colAnnLengthDiac) = ?, \(colAnnColor) = ?, \(colAnnType) = ?, \(colAnnNote) = ?, \(colAnnLastModified) = ?, \(colAnnPart) = ?, \(colAnnPage) = ? WHERE \(colAnnId) = ?;"

        let params: [Any] = [
            annCopy.bkId,
            annCopy.contentId,
            annCopy.range.location,
            annCopy.range.length,
            annCopy.rangeDiacritics.location,
            annCopy.rangeDiacritics.length,
            annCopy.colorHex,
            annCopy.type.rawValue,
            annCopy.note ?? NSNull(),
            annCopy.lastModified ?? 0,
            annCopy.part,
            annCopy.page,
            existingId,
        ]

        try db.execute(query: updateSql, parameters: params)
        try replaceTags(sanitizeTagNames(annCopy.tags), for: existingId)
        return annCopy
    }

    private func insertCloudKitAnnotation(
        db: SQLiteDatabase,
        ann: Annotation
    ) throws -> Annotation? {
        var annCopy = ann
        let rowId = try insertAnnotationRow(annCopy, into: db, orReplace: true)
        guard rowId != -1 else { return nil }
        annCopy.id = rowId
        try replaceTags(sanitizeTagNames(annCopy.tags), for: rowId)
        return annCopy
    }

    private func applyIncrementalCloudKitCacheAndTree(
        added: [Annotation],
        updated: [Annotation],
        deleted: [Annotation]
    ) {
        let allChanged = added + updated + deleted
        let affectedContentKeys = Set(allChanged.map { ContentKey(bkId: $0.bkId, contentId: $0.contentId) })
        let affectedBookIds = Set(allChanged.map(\.bkId))

        _cacheQueue.sync {
            _cachedAllTagNames = nil

            for ann in deleted {
                guard let id = ann.id else { continue }
                _cacheById.removeValue(forKey: id)
                _cacheTagsByAnnotationId.removeValue(forKey: id)
            }

            for ann in added + updated {
                guard let id = ann.id else { continue }
                _cacheById[id] = ann
                _cacheTagsByAnnotationId[id] = ann.tags
            }

            for key in affectedContentKeys {
                _cacheByContent.removeValue(forKey: key)
            }
            for bkId in affectedBookIds {
                _cacheByBook.removeValue(forKey: bkId)
            }
        }

        // Incremental Tree Update (UI)
        for ann in deleted {
            if let id = ann.id { removeAnnotationFromTree(id: id, deletedAnnotation: ann, uploadToCloudKit: false) }
        }
        for ann in added {
            addAnnotationToTree(ann, uploadToCloudKit: false)
        }
        for ann in updated {
            updateAnnotationInTree(ann, uploadToCloudKit: false)
        }
    }
}
