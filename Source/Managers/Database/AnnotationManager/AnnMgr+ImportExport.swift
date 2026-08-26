//
//  AnnMgr+ImportExport.swift
//  Maktabah
//
//  Created by Ghoys on 17/08/2026.
//

import Foundation

extension AnnotationManager {
    /// Imports a list of annotations into the database.
    /// - Parameters:
    ///   - annotations: Decoded annotations to import.
    ///   - overwrite: If true, existing annotations matching by ckRecordId or (bkId, contentId, range) will be overwritten. If false, existing annotations will be skipped.
    /// - Returns: Total number of annotations imported/updated.
    @discardableResult
    func importAnnotations(_ annotations: [Annotation], overwrite: Bool = true) throws -> Int {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }
        guard !annotations.isEmpty else { return 0 }

        var importedCount = 0
        var updatedOrInsertedAnnotations: [Annotation] = []
        let currentTimestamp = now

        try transaction {
            for ann in annotations {
                let existingId = try findExistingAnnotationId(db: _db, ann: ann)
                if let existingId {
                    guard overwrite else { continue }
                    let updated = try overwriteExistingAnnotation(
                        db: _db,
                        ann: ann,
                        existingId: existingId,
                        currentTimestamp: currentTimestamp
                    )
                    updatedOrInsertedAnnotations.append(updated)
                    importedCount += 1
                } else if let saved = try insertNewImportedAnnotation(
                    db: _db,
                    ann: ann,
                    currentTimestamp: currentTimestamp
                ) {
                    updatedOrInsertedAnnotations.append(saved)
                    importedCount += 1
                }
            }
        }

        if importedCount > 0 {
            try? deleteUnusedTags()
            clearAllCaches()
            buildAnnotationTree()
            CloudKitSyncManager.shared.upload(annotations: updatedOrInsertedAnnotations, debounce: true)
        }

        return importedCount
    }

    private func findExistingAnnotationId(db: SQLiteDatabase, ann: Annotation) throws -> Int64? {
        if let ckId = ann.ckRecordId, !ckId.isEmpty {
            let sql = "SELECT \(colAnnId) FROM \(annotationsTable) WHERE \(colAnnCkRecordId) = ? LIMIT 1;"
            if let row = try db.fetch(query: sql, parameters: [ckId], mapping: { $0.int64(at: 0) }).first {
                return row
            }
        }

        let sql = "SELECT \(colAnnId) FROM \(annotationsTable) WHERE \(colAnnBkId) = ? AND \(colAnnContentId) = ? AND \(colAnnStart) = ? AND \(colAnnLength) = ? LIMIT 1;"
        return try db.fetch(
            query: sql,
            parameters: [ann.bkId, ann.contentId, ann.range.location, ann.range.length],
            mapping: { $0.int64(at: 0) }
        ).first
    }

    private func overwriteExistingAnnotation(
        db: SQLiteDatabase,
        ann: Annotation,
        existingId: Int64,
        currentTimestamp: Int64
    ) throws -> Annotation {
        let updateSql = """
        UPDATE \(annotationsTable) SET
            \(colAnnColor) = ?,
            \(colAnnType) = ?,
            \(colAnnNote) = ?,
            \(colAnnLastModified) = ?,
            \(colAnnStartDiac) = ?,
            \(colAnnLengthDiac) = ?,
            \(colAnnContext) = ?,
            \(colAnnPart) = ?,
            \(colAnnPage) = ?,
            \(colAnnCreatedAt) = ?
        WHERE \(colAnnId) = ?;
        """

        let lastMod = ann.lastModified ?? currentTimestamp
        let params: [Any] = [
            ann.colorHex,
            ann.type.rawValue,
            ann.note ?? NSNull(),
            lastMod,
            ann.rangeDiacritics.location,
            ann.rangeDiacritics.length,
            ann.context,
            ann.part,
            ann.page,
            ann.createdAt,
            existingId,
        ]

        try db.execute(query: updateSql, parameters: params)
        let normalizedTags = sanitizeTagNames(ann.tags)
        try replaceTags(normalizedTags, for: existingId)

        var updatedAnn = ann
        updatedAnn.id = existingId
        updatedAnn.tags = normalizedTags
        updatedAnn.lastModified = lastMod

        if let ckId = ann.ckRecordId, !ckId.isEmpty {
            try addPendingSync(ckRecordId: ckId, operation: "upload")
        }
        return updatedAnn
    }

    private func insertNewImportedAnnotation(
        db: SQLiteDatabase,
        ann: Annotation,
        currentTimestamp: Int64
    ) throws -> Annotation? {
        var annToInsert = ann
        if annToInsert.ckRecordId == nil || annToInsert.ckRecordId?.isEmpty == true {
            annToInsert.ckRecordId = UUID().uuidString
        }
        let lastMod = annToInsert.lastModified ?? currentTimestamp
        annToInsert.lastModified = lastMod

        let newId = try insertAnnotationRow(annToInsert, into: db)
        guard newId > 0 else { return nil }

        let normalizedTags = sanitizeTagNames(annToInsert.tags)
        try replaceTags(normalizedTags, for: newId)

        var savedAnn = annToInsert
        savedAnn.id = newId
        savedAnn.tags = normalizedTags

        if let ckId = annToInsert.ckRecordId {
            try addPendingSync(ckRecordId: ckId, operation: "upload")
        }
        return savedAnn
    }
}
