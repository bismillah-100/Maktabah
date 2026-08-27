//
//  AnnMgr+Tags.swift
//  Maktabah
//

import Foundation

extension AnnotationManager {
    // MARK: - Rename Tag

    /// Ganti nama tag.
    /// - Jika `newName` (setelah normalisasi) sama dengan tag lain yang sudah ada → **merge**:
    ///   semua anotasi dari tag lama dipindah ke tag yang sudah ada, tag lama dihapus.
    /// - Jika tidak → **simple rename**: hanya nama di DB & cache yang diperbarui.
    /// - Throws `NSError(domain:"EmptyTagName")` jika `newName` kosong setelah trim.
    private enum TagSQL {
        static func findTagId(table: String, colId: String, colNormalizedName: String) -> String {
            "SELECT \(colId) FROM \(table) WHERE \(colNormalizedName) = ? LIMIT 1"
        }

        static func findAffectedIds(table: String, colAnnotationId: String, colTagId: String) -> String {
            "SELECT \(colAnnotationId) FROM \(table) WHERE \(colTagId) = ?"
        }
    }

    private func fetchTagId(normalizedName: String, db: SQLiteDatabase) throws -> Int64 {
        let query = TagSQL.findTagId(table: tagsTable, colId: colTagId, colNormalizedName: colTagNormalizedName)
        if let fetchedId = try db.fetch(query: query, parameters: [normalizedName], mapping: { $0.int64(at: 0) }).first {
            return fetchedId
        }
        return -1
    }

    private func getTagRenameContext(
        oldNormalized: String,
        newNormalized: String,
        trimmedNew: String,
        db: SQLiteDatabase,
        now: Int64
    ) throws -> (context: TagRenameContext, existingNewTagId: Int64)? {
        let oldTagId = try fetchTagId(normalizedName: oldNormalized, db: db)
        guard oldTagId != -1 else { return nil }

        let affectedQuery = TagSQL.findAffectedIds(
            table: annotationTagsTable,
            colAnnotationId: colAnnotationTagAnnotationId,
            colTagId: colAnnotationTagTagId
        )
        let affectedIds = try db.fetch(query: affectedQuery, parameters: [oldTagId], mapping: { $0.int64(at: 0) })

        let existingNewTagId = try fetchTagId(normalizedName: newNormalized, db: db)

        let context = TagRenameContext(
            oldTagId: oldTagId,
            oldNormalized: oldNormalized,
            newNormalized: newNormalized,
            trimmedNew: trimmedNew,
            affectedIds: affectedIds,
            now: now
        )

        return (context, existingNewTagId)
    }

    func renameTag(from oldName: String, to newName: String) throws {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }

        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldNormalized = normalizedTagName(oldName)
        let newNormalized = normalizedTagName(trimmedNew)

        guard !newNormalized.isEmpty else {
            throw NSError(domain: "EmptyTagName", code: 3, userInfo: [NSLocalizedDescriptionKey: "Tag name cannot be empty."])
        }
        if oldNormalized == newNormalized, oldName == trimmedNew {
            return
        }

        guard let result = try getTagRenameContext(
            oldNormalized: oldNormalized,
            newNormalized: newNormalized,
            trimmedNew: trimmedNew,
            db: _db,
            now: now
        ) else { return }

        let updatedAnnotations: [Annotation] = if result.existingNewTagId != -1 {
            try performTagMerge(context: result.context, existingNewTagId: result.existingNewTagId)
        } else {
            try performSimpleTagRename(context: result.context)
        }

        applyBatchTagUpdates(updatedAnnotations)
    }

    private struct TagRenameContext {
        let oldTagId: Int64
        let oldNormalized: String
        let newNormalized: String
        let trimmedNew: String
        let affectedIds: [Int64]
        let now: Int64
    }

    private func performTagMerge(
        context: TagRenameContext,
        existingNewTagId: Int64
    ) throws -> [Annotation] {
        var updatedAnnotations: [Annotation] = []
        try transaction {
            for annId in context.affectedIds {
                guard var ann = loadAnnotationById(annId) else { continue }
                var tags = ann.tags.filter { normalizedTagName($0) != context.oldNormalized }
                if !tags.contains(where: { normalizedTagName($0) == context.newNormalized }) {
                    tags.append(context.trimmedNew)
                }
                ann.tags = sanitizeTagNames(tags)
                ann.lastModified = context.now
                updatedAnnotations.append(ann)
            }

            let insertRelSql = "INSERT OR IGNORE INTO \(annotationTagsTable) (\(colAnnotationTagAnnotationId), \(colAnnotationTagTagId)) SELECT \(colAnnotationTagAnnotationId), ? FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?;"
            try exec(insertRelSql, parameters: [existingNewTagId, context.oldTagId])

            let updateAnnSql = "UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) IN (SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?);"
            try exec(updateAnnSql, parameters: [context.now, context.oldTagId])

            try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?;", parameters: [context.oldTagId])
            try exec("DELETE FROM \(tagsTable) WHERE \(colTagId) = ?;", parameters: [context.oldTagId])
        }
        return updatedAnnotations
    }

    private func performSimpleTagRename(
        context: TagRenameContext
    ) throws -> [Annotation] {
        var updatedAnnotations: [Annotation] = []
        try transaction {
            for annId in context.affectedIds {
                guard var ann = loadAnnotationById(annId) else { continue }
                ann.tags = ann.tags.map {
                    normalizedTagName($0) == context.oldNormalized ? context.trimmedNew : $0
                }
                ann.tags = sanitizeTagNames(ann.tags)
                ann.lastModified = context.now
                updatedAnnotations.append(ann)
            }

            let updateAnnSql = "UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) IN (SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?);"
            try exec(updateAnnSql, parameters: [context.now, context.oldTagId])

            let updateTagSql = "UPDATE \(tagsTable) SET \(colTagName) = ?, \(colTagNormalizedName) = ? WHERE \(colTagId) = ?;"
            try exec(updateTagSql, parameters: [context.trimmedNew, context.newNormalized, context.oldTagId])
        }
        return updatedAnnotations
    }

    private func mutateTags(
        forAnnotationIDs annotationIDs: [Int64],
        mutation: (inout [String]) -> Bool
    ) throws {
        let uniqueIDs = Array(Set(annotationIDs)).sorted()
        guard !uniqueIDs.isEmpty else { return }

        var updatedAnnotations: [Annotation] = []
        var updatedIDs: [Int64] = []
        try transaction {
            for annotationID in uniqueIDs {
                guard var annotation = loadAnnotationById(annotationID) else { continue }
                var tags = annotation.tags
                guard mutation(&tags) else { continue }
                let sanitizedTags = sanitizeTagNames(tags)
                guard sanitizedTags != annotation.tags else { continue }
                try replaceTags(sanitizedTags, for: annotationID)
                annotation.tags = sanitizedTags
                annotation.lastModified = now
                updatedAnnotations.append(annotation)
                updatedIDs.append(annotationID)
            }

            try updateAnnotationsLastModified(for: updatedIDs, timestamp: now)
        }

        applyBatchTagUpdates(updatedAnnotations)
    }

    func addTag(_ tag: String, toAnnotationIDs annotationIDs: [Int64]) throws {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedTags = sanitizeTagNames([trimmedTag])
        guard let normalizedTag = sanitizedTags.first else { return }

        try mutateTags(forAnnotationIDs: annotationIDs) { tags in
            tags.append(normalizedTag)
            return true
        }
    }

    func removeTag(_ tag: String, fromAnnotationIDs annotationIDs: [Int64]) throws {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTarget = normalizedTagName(trimmedTag)
        guard !normalizedTarget.isEmpty else { return }

        try mutateTags(forAnnotationIDs: annotationIDs) { tags in
            tags.removeAll { self.normalizedTagName($0) == normalizedTarget }
            return true
        }
    }

    private func updateAnnotationsLastModified(for annotationIDs: [Int64], timestamp: Int64) throws {
        guard !annotationIDs.isEmpty else { return }
        for chunk in annotationIDs.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let updateSql = "UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) IN (\(placeholders));"

            var parameters: [Any] = [timestamp]
            parameters.append(contentsOf: chunk)

            try exec(updateSql, parameters: parameters)
        }
    }

    // MARK: - Delete Tag

    /// Hapus tag dari DB dan semua anotasi yang memilikinya.
    /// Anotasi tidak dihapus — hanya kehilangan tag ini.
    func deleteTag(named tagNameToDelete: String) throws {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }

        let normalized = normalizedTagName(tagNameToDelete)
        var deletedTagId: Int64 = -1
        let findTagSql = "SELECT \(colTagId) FROM \(tagsTable) WHERE \(colTagNormalizedName) = ? LIMIT 1"
        if let fetchedId = try _db.fetch(query: findTagSql, parameters: [normalized], mapping: { $0.int64(at: 0) }).first {
            deletedTagId = fetchedId
        }

        if deletedTagId == -1 {
            return
        }

        let findAffectedSql = "SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?"
        let affectedIds = try _db.fetch(query: findAffectedSql, parameters: [deletedTagId], mapping: { $0.int64(at: 0) })

        try transaction {
            try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?;", parameters: [deletedTagId])
            try exec("DELETE FROM \(tagsTable) WHERE \(colTagId) = ?;", parameters: [deletedTagId])

            try updateAnnotationsLastModified(for: affectedIds, timestamp: now)
        }

        let updatedAnnotations = purgeCachedTagAnnotations(affectedIds: affectedIds, normalized: normalized, now: now)

        deleteTagFromTree(
            tagName: tagNameToDelete,
            normalizedName: normalized,
            updatedAnnotations: updatedAnnotations
        )
    }

    private func purgeCachedTagAnnotations(affectedIds: [Int64], normalized: String, now: Int64) -> [Annotation] {
        var updatedAnnotations: [Annotation] = []
        _cacheQueue.sync {
            _cachedAllTagNames = nil
            for annId in affectedIds {
                guard var ann = _cacheById[annId] else { continue }
                ann.tags = ann.tags.filter { normalizedTagName($0) != normalized }
                ann.lastModified = now
                _cacheById[annId] = ann
                _cacheTagsByAnnotationId[annId] = ann.tags

                let key = ContentKey(bkId: ann.bkId, contentId: ann.contentId)
                var cachedArr = _cacheByContent[key] ?? []
                if let idx = cachedArr.firstIndex(where: { $0.id == annId }) {
                    cachedArr[idx] = ann
                    _cacheByContent[key] = cachedArr
                }
                if var bookArr = _cacheByBook[ann.bkId],
                   let idx = bookArr.firstIndex(where: { $0.id == annId })
                {
                    bookArr[idx] = ann
                    _cacheByBook[ann.bkId] = bookArr
                }
                updatedAnnotations.append(ann)
            }
        }
        return updatedAnnotations
    }

    // MARK: - All Tag Names

    func allTagNames() -> [String] {
        if let cached = _cacheQueue.sync(execute: { _cachedAllTagNames }) {
            return cached
        }
        guard let _db else { return [] }
        var names: [String] = []
        let sql = "SELECT \(colTagName) FROM \(tagsTable) ORDER BY \(colTagName) COLLATE NOCASE"
        do {
            names = try _db.fetch(query: sql) { $0.string(at: 0) ?? "" }
            _cacheQueue.sync { _cachedAllTagNames = names }
        } catch {
            print("Failed to fetch all tag names: \(error)")
        }
        return names
    }

    // MARK: - Private Tag Helpers

    func fetchTagsForAnnotations(_ annotations: [Annotation]) -> [Int64: [String]] {
        let ids = annotations.compactMap(\.id)
        guard !ids.isEmpty, let _db = db else { return [:] }

        var result: [Int64: [String]] = [:]

        let placeholders = String(repeating: "?,", count: ids.count).dropLast()
        let sql = """
        SELECT at.\(colAnnotationTagAnnotationId), t.\(colTagName)
        FROM \(tagsTable) t
        JOIN \(annotationTagsTable) at ON t.\(colTagId) = at.\(colAnnotationTagTagId)
        WHERE at.\(colAnnotationTagAnnotationId) IN (\(placeholders))
        ORDER BY t.\(colTagName) COLLATE NOCASE
        """

        do {
            let rows = try _db.fetch(query: sql, parameters: ids) { row -> (Int64, String) in
                (row.int64(at: 0), row.string(at: 1) ?? "")
            }
            for row in rows {
                result[row.0, default: []].append(row.1)
            }
        } catch {
            print("Failed to fetch bulk tags: \(error)")
        }

        return result
    }

    func loadTags(for annotationId: Int64) -> [String] {
        if let cached = _cacheQueue.sync(execute: { _cacheTagsByAnnotationId[annotationId] }) {
            return cached
        }

        guard let _db = db else { return [] }
        var tags: [String] = []
        let sql = """
        SELECT t.\(colTagName)
        FROM \(tagsTable) t
        JOIN \(annotationTagsTable) at ON t.\(colTagId) = at.\(colAnnotationTagTagId)
        WHERE at.\(colAnnotationTagAnnotationId) = ?
        ORDER BY t.\(colTagName) COLLATE NOCASE
        """

        do {
            tags = try _db.fetch(query: sql, parameters: [annotationId]) { $0.string(at: 0) ?? "" }
            _cacheQueue.sync {
                _cacheTagsByAnnotationId[annotationId] = tags
            }
        } catch {
            print("Failed to load tags for annotation: \(error)")
        }
        return tags
    }

    private func fetchExistingTagsMap(
        db: SQLiteDatabase,
        tags: [String]
    ) throws -> [String: (id: Int64, name: String)] {
        var existingTags: [String: (id: Int64, name: String)] = [:]
        guard !tags.isEmpty else { return existingTags }

        struct TagRow {
            let id: Int64
            let name: String
            let normalizedName: String
        }

        let normalizedTags = tags.map { normalizedTagName($0) }
        for chunk in normalizedTags.chunked(into: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")

            let findSql = "SELECT \(colTagId), \(colTagName), \(colTagNormalizedName) FROM \(tagsTable) WHERE \(colTagNormalizedName) IN (\(placeholders))"
            let fetchedExisting = try db.fetch(query: findSql, parameters: chunk) { row -> TagRow in
                TagRow(id: row.int64(at: 0), name: row.string(at: 1) ?? "", normalizedName: row.string(at: 2) ?? "")
            }
            for tag in fetchedExisting {
                existingTags[tag.normalizedName] = (tag.id, tag.name)
            }
        }
        return existingTags
    }

    private func insertNewTagsAndFetch(
        db: SQLiteDatabase,
        tagsToInsert: [(name: String, normalized: String)],
        existingTags: inout [String: (id: Int64, name: String)],
        currentTagIds: inout [Int64]
    ) throws {
        guard !tagsToInsert.isEmpty else { return }

        struct TagRow {
            let id: Int64
            let name: String
            let normalizedName: String
        }

        for chunk in tagsToInsert.chunked(into: 400) {
            let placeholders = String(repeating: "(?, ?),", count: chunk.count).dropLast()
            let insertSql = "INSERT INTO \(tagsTable) (\(colTagName), \(colTagNormalizedName)) VALUES \(placeholders);"

            var insertParams: [Any] = []
            for tagTuple in chunk {
                insertParams.append(tagTuple.name)
                insertParams.append(tagTuple.normalized)
            }
            try db.execute(query: insertSql, parameters: insertParams)
        }

        let normalizedNewTags = tagsToInsert.map(\.normalized)
        for chunk in normalizedNewTags.chunked(into: 500) {
            let selectPlaceholders = String(repeating: "?,", count: chunk.count).dropLast()
            let fetchNewSql = "SELECT \(colTagId), \(colTagNormalizedName), \(colTagName) FROM \(tagsTable) WHERE \(colTagNormalizedName) IN (\(selectPlaceholders))"

            let fetchedNewTags = try db.fetch(query: fetchNewSql, parameters: chunk) { row -> TagRow in
                TagRow(id: row.int64(at: 0), name: row.string(at: 2) ?? "", normalizedName: row.string(at: 1) ?? "")
            }

            for tag in fetchedNewTags {
                existingTags[tag.normalizedName] = (tag.id, tag.name)
                currentTagIds.append(tag.id)
            }
        }
    }

    private func linkAnnotationTags(
        db: SQLiteDatabase,
        annotationId: Int64,
        tagIds: [Int64]
    ) throws {
        guard !tagIds.isEmpty else { return }

        for chunk in tagIds.chunked(into: 400) {
            let relPlaceholders = String(repeating: "(?, ?),", count: chunk.count).dropLast()
            let insertRelSql = "INSERT OR IGNORE INTO \(annotationTagsTable) (\(colAnnotationTagAnnotationId), \(colAnnotationTagTagId)) VALUES \(relPlaceholders);"

            var relParams: [Any] = []
            for tagId in chunk {
                relParams.append(annotationId)
                relParams.append(tagId)
            }
            try db.execute(query: insertRelSql, parameters: relParams)
        }
    }

    func replaceTags(_ tags: [String], for annotationId: Int64) throws {
        guard let _db = db else { return }

        try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagAnnotationId) = ?;", parameters: [annotationId])

        var existingTags = try fetchExistingTagsMap(db: _db, tags: tags)
        var currentTagIds: [Int64] = []
        var tagsToInsert: [(name: String, normalized: String)] = []
        var seenNormalized: Set<String> = []

        // Process Updates and prepare unique Inserts
        for tag in tags {
            let normalized = normalizedTagName(tag)

            if let existing = existingTags[normalized] {
                let existingTagId = existing.id
                let existingTagName = existing.name

                if existingTagName != tag {
                    let updateSql = "UPDATE \(tagsTable) SET \(colTagName) = ? WHERE \(colTagId) = ?;"
                    try _db.execute(query: updateSql, parameters: [tag, existingTagId])
                    existingTags[normalized] = (existingTagId, tag)
                }
                if seenNormalized.insert(normalized).inserted {
                    currentTagIds.append(existingTagId)
                }
            } else if seenNormalized.insert(normalized).inserted {
                tagsToInsert.append((name: tag, normalized: normalized))
            }
        }

        try insertNewTagsAndFetch(
            db: _db,
            tagsToInsert: tagsToInsert,
            existingTags: &existingTags,
            currentTagIds: &currentTagIds
        )

        try linkAnnotationTags(db: _db, annotationId: annotationId, tagIds: currentTagIds)

        _cacheQueue.sync { _cachedAllTagNames = nil }
        try deleteUnusedTags()
    }

    func deleteUnusedTags() throws {
        try exec("""
        DELETE FROM \(tagsTable)
        WHERE \(colTagId) NOT IN (
            SELECT DISTINCT \(colAnnotationTagTagId)
            FROM \(annotationTagsTable)
        )
        """)
    }

    func sanitizeTagNames(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = normalizedTagName(trimmed)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            result.append(trimmed)
        }

        return result
    }

    func normalizedTagName(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
