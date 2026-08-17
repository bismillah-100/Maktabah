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
                var existingId: Int64?

                // 1. Check existence by ckRecordId if present
                if let ckId = ann.ckRecordId, !ckId.isEmpty {
                    let sql = "SELECT \(colAnnId) FROM \(annotationsTable) WHERE \(colAnnCkRecordId) = ? LIMIT 1;"
                    if let row = try _db.fetch(query: sql, parameters: [ckId], mapping: { $0.int64(at: 0) }).first {
                        existingId = row
                    }
                }

                // 2. Check existence by bkId + contentId + range
                if existingId == nil {
                    let sql = "SELECT \(colAnnId) FROM \(annotationsTable) WHERE \(colAnnBkId) = ? AND \(colAnnContentId) = ? AND \(colAnnStart) = ? AND \(colAnnLength) = ? LIMIT 1;"
                    if let row = try _db.fetch(query: sql, parameters: [ann.bkId, ann.contentId, ann.range.location, ann.range.length], mapping: { $0.int64(at: 0) }).first {
                        existingId = row
                    }
                }

                if let existingId {
                    // Duplicate found
                    if !overwrite {
                        continue
                    }

                    // Overwrite existing record
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

                    try _db.execute(query: updateSql, parameters: params)
                    let normalizedTags = sanitizeTagNames(ann.tags)
                    try self.replaceTags(normalizedTags, for: existingId)

                    var updatedAnn = ann
                    updatedAnn.id = existingId
                    updatedAnn.tags = normalizedTags
                    updatedAnn.lastModified = lastMod
                    updatedOrInsertedAnnotations.append(updatedAnn)

                    if let ckId = ann.ckRecordId, !ckId.isEmpty {
                        try self.addPendingSync(ckRecordId: ckId, operation: "upload")
                    }
                    importedCount += 1
                } else {
                    // Insert new record
                    var annToInsert = ann
                    if annToInsert.ckRecordId == nil || annToInsert.ckRecordId?.isEmpty == true {
                        annToInsert.ckRecordId = UUID().uuidString
                    }
                    let lastMod = annToInsert.lastModified ?? currentTimestamp
                    annToInsert.lastModified = lastMod

                    let insertSql = """
                    INSERT INTO \(annotationsTable) (
                        \(colAnnBkId), \(colAnnContentId), \(colAnnStart), \(colAnnLength),
                        \(colAnnStartDiac), \(colAnnLengthDiac), \(colAnnColor), \(colAnnType),
                        \(colAnnNote), \(colAnnCreatedAt), \(colAnnContext), \(colAnnPart),
                        \(colAnnPage), \(colAnnCkRecordId), \(colAnnLastModified)
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """

                    let params: [Any] = [
                        annToInsert.bkId,
                        annToInsert.contentId,
                        annToInsert.range.location,
                        annToInsert.range.length,
                        annToInsert.rangeDiacritics.location,
                        annToInsert.rangeDiacritics.length,
                        annToInsert.colorHex,
                        annToInsert.type.rawValue,
                        annToInsert.note ?? NSNull(),
                        annToInsert.createdAt,
                        annToInsert.context,
                        annToInsert.part,
                        annToInsert.page,
                        annToInsert.ckRecordId ?? NSNull(),
                        lastMod,
                    ]

                    try _db.execute(query: insertSql, parameters: params)
                    let newId = _db.lastInsertRowId()
                    if newId > 0 {
                        let normalizedTags = sanitizeTagNames(annToInsert.tags)
                        try self.replaceTags(normalizedTags, for: newId)

                        var savedAnn = annToInsert
                        savedAnn.id = newId
                        savedAnn.tags = normalizedTags
                        updatedOrInsertedAnnotations.append(savedAnn)

                        if let ckId = annToInsert.ckRecordId {
                            try self.addPendingSync(ckRecordId: ckId, operation: "upload")
                        }
                        importedCount += 1
                    }
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
}
