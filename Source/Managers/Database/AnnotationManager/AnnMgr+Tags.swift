//
//  AnnotationManager+Tags.swift
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
    func renameTag(from oldName: String, to newName: String) throws {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }

        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldNormalized = normalizedTagName(oldName)
        let newNormalized = normalizedTagName(trimmedNew)

        guard !newNormalized.isEmpty else {
            throw NSError(
                domain: "EmptyTagName", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Tag name cannot be empty."]
            )
        }
        if oldNormalized == newNormalized, oldName == trimmedNew { return }

        var oldTagId: Int64 = -1
        let findOldSql = "SELECT \(colTagId) FROM \(tagsTable) WHERE \(colTagNormalizedName) = ? LIMIT 1"
        if let fetchedId = try _db.fetch(query: findOldSql, parameters: [oldNormalized], mapping: { $0.int64(at: 0) }).first {
            oldTagId = fetchedId
        }

        if oldTagId == -1 { return }

        var affectedIds: [Int64] = []
        let findAffectedSql = "SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?"
        affectedIds = try _db.fetch(query: findAffectedSql, parameters: [oldTagId], mapping: { $0.int64(at: 0) })

        var updatedAnnotations: [Annotation] = []

        var existingNewTagId: Int64 = -1
        let findNewSql = "SELECT \(colTagId) FROM \(tagsTable) WHERE \(colTagNormalizedName) = ? LIMIT 1"
        if let fetchedId = try _db.fetch(query: findNewSql, parameters: [newNormalized], mapping: { $0.int64(at: 0) }).first {
            existingNewTagId = fetchedId
        }

        if existingNewTagId != -1 {
            // MERGE
            try transaction {
                for annId in affectedIds {
                    guard var ann = loadAnnotationById(annId) else { continue }
                    var tags = ann.tags.filter { normalizedTagName($0) != oldNormalized }
                    if !tags.contains(where: { normalizedTagName($0) == newNormalized }) {
                        tags.append(trimmedNew)
                    }
                    ann.tags = sanitizeTagNames(tags)
                    ann.lastModified = now
                    updatedAnnotations.append(ann)
                }

                let insertRelSql = "INSERT OR IGNORE INTO \(annotationTagsTable) (\(colAnnotationTagAnnotationId), \(colAnnotationTagTagId)) SELECT \(colAnnotationTagAnnotationId), ? FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?;"
                try exec(insertRelSql, parameters: [existingNewTagId, oldTagId])

                let updateAnnSql = "UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) IN (SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?);"
                try exec(updateAnnSql, parameters: [now, oldTagId])

                try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?;", parameters: [oldTagId])
                try exec("DELETE FROM \(tagsTable) WHERE \(colTagId) = ?;", parameters: [oldTagId])
            }
        } else {
            // SIMPLE RENAME
            try transaction {
                for annId in affectedIds {
                    guard var ann = loadAnnotationById(annId) else { continue }
                    ann.tags = ann.tags.map {
                        normalizedTagName($0) == oldNormalized ? trimmedNew : $0
                    }
                    ann.tags = sanitizeTagNames(ann.tags)
                    ann.lastModified = now
                    updatedAnnotations.append(ann)
                }

                let updateAnnSql = "UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) IN (SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?);"
                try exec(updateAnnSql, parameters: [now, oldTagId])

                let updateTagSql = "UPDATE \(tagsTable) SET \(colTagName) = ?, \(colTagNormalizedName) = ? WHERE \(colTagId) = ?;"
                try exec(updateTagSql, parameters: [trimmedNew, newNormalized, oldTagId])
            }
        }

        applyBatchTagUpdates(updatedAnnotations)
    }

    // MARK: - Add / Remove Tag (Batch)

    func addTag(_ tag: String, toAnnotationIDs annotationIDs: [Int64]) throws {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedTags = sanitizeTagNames([trimmedTag])
        guard let normalizedTag = sanitizedTags.first else { return }

        let uniqueIDs = Array(Set(annotationIDs)).sorted()
        guard !uniqueIDs.isEmpty else { return }

        var updatedAnnotations: [Annotation] = []
        var updatedIDs: [Int64] = []
        try transaction {
            for annotationID in uniqueIDs {
                guard var annotation = loadAnnotationById(annotationID) else { continue }
                let mergedTags = sanitizeTagNames(annotation.tags + [normalizedTag])
                guard mergedTags != annotation.tags else { continue }
                try replaceTags(mergedTags, for: annotationID)
                annotation.tags = mergedTags
                annotation.lastModified = now
                updatedAnnotations.append(annotation)
                updatedIDs.append(annotationID)
            }

            let chunkSize = 500
            for chunkStart in stride(from: 0, to: updatedIDs.count, by: chunkSize) {
                let chunkEnd = min(chunkStart + chunkSize, updatedIDs.count)
                let chunk = Array(updatedIDs[chunkStart..<chunkEnd])

                let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                let updateSql = "UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) IN (\(placeholders));"

                var parameters: [Any] = [now]
                parameters.append(contentsOf: chunk)

                try exec(updateSql, parameters: parameters)
            }
        }

        applyBatchTagUpdates(updatedAnnotations)
    }

    func removeTag(_ tag: String, fromAnnotationIDs annotationIDs: [Int64]) throws {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTarget = normalizedTagName(trimmedTag)
        guard !normalizedTarget.isEmpty else { return }

        let uniqueIDs = Array(Set(annotationIDs)).sorted()
        guard !uniqueIDs.isEmpty else { return }

        var updatedAnnotations: [Annotation] = []
        var updatedIDs: [Int64] = []
        try transaction {
            for annotationID in uniqueIDs {
                guard var annotation = loadAnnotationById(annotationID) else { continue }
                let filteredTags = annotation.tags.filter {
                    normalizedTagName($0) != normalizedTarget
                }
                let sanitizedTags = sanitizeTagNames(filteredTags)
                guard sanitizedTags != annotation.tags else { continue }
                try replaceTags(sanitizedTags, for: annotationID)
                annotation.tags = sanitizedTags
                annotation.lastModified = now
                updatedAnnotations.append(annotation)
                updatedIDs.append(annotationID)
            }

            let chunkSize = 500
            for chunkStart in stride(from: 0, to: updatedIDs.count, by: chunkSize) {
                let chunkEnd = min(chunkStart + chunkSize, updatedIDs.count)
                let chunk = Array(updatedIDs[chunkStart..<chunkEnd])

                let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                let updateSql = "UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) IN (\(placeholders));"

                var parameters: [Any] = [now]
                parameters.append(contentsOf: chunk)

                try exec(updateSql, parameters: parameters)
            }
        }

        applyBatchTagUpdates(updatedAnnotations)
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

        if deletedTagId == -1 { return }

        let findAffectedSql = "SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?"
        let affectedIds = try _db.fetch(query: findAffectedSql, parameters: [deletedTagId], mapping: { $0.int64(at: 0) })

        try transaction {
            try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?;", parameters: [deletedTagId])
            try exec("DELETE FROM \(tagsTable) WHERE \(colTagId) = ?;", parameters: [deletedTagId])

            let chunkSize = 500
            for chunkStart in stride(from: 0, to: affectedIds.count, by: chunkSize) {
                let chunkEnd = min(chunkStart + chunkSize, affectedIds.count)
                let chunk = Array(affectedIds[chunkStart..<chunkEnd])

                let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                let updateSql = "UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) IN (\(placeholders));"

                var parameters: [Any] = [now]
                parameters.append(contentsOf: chunk)

                try exec(updateSql, parameters: parameters)
            }
        }

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

        deleteTagFromTree(
            tagName: tagNameToDelete,
            normalizedName: normalized,
            updatedAnnotations: updatedAnnotations
        )
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
        let ids = annotations.compactMap { $0.id }
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

    func replaceTags(_ tags: [String], for annotationId: Int64) throws {
        guard let _db = db else { return }

        try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagAnnotationId) = ?;", parameters: [annotationId])

        var existingTags: [String: (id: Int64, name: String)] = [:]

        if !tags.isEmpty {
            let normalizedTags = tags.map { normalizedTagName($0) }
            for i in stride(from: 0, to: normalizedTags.count, by: 500) {
                let chunk = Array(normalizedTags[i ..< min(i + 500, normalizedTags.count)])
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")

                let findSql = "SELECT \(colTagId), \(colTagName), \(colTagNormalizedName) FROM \(tagsTable) WHERE \(colTagNormalizedName) IN (\(placeholders))"
                let fetchedExisting = try _db.fetch(query: findSql, parameters: chunk) { row -> (Int64, String, String) in
                    (row.int64(at: 0), row.string(at: 1) ?? "", row.string(at: 2) ?? "")
                }
                for (id, name, normalized) in fetchedExisting {
                    existingTags[normalized] = (id, name)
                }
            }
        }

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
            } else {
                if seenNormalized.insert(normalized).inserted {
                    tagsToInsert.append((name: tag, normalized: normalized))
                }
            }
        }

        if !tagsToInsert.isEmpty {
            for i in stride(from: 0, to: tagsToInsert.count, by: 400) {
                let chunk = Array(tagsToInsert[i ..< min(i + 400, tagsToInsert.count)])
                let placeholders = String(repeating: "(?, ?),", count: chunk.count).dropLast()
                let insertSql = "INSERT INTO \(tagsTable) (\(colTagName), \(colTagNormalizedName)) VALUES \(placeholders);"

                var insertParams: [Any] = []
                for tagTuple in chunk {
                    insertParams.append(tagTuple.name)
                    insertParams.append(tagTuple.normalized)
                }
                try _db.execute(query: insertSql, parameters: insertParams)
            }

            let normalizedNewTags = tagsToInsert.map { $0.normalized }
            for i in stride(from: 0, to: normalizedNewTags.count, by: 500) {
                let chunk = Array(normalizedNewTags[i ..< min(i + 500, normalizedNewTags.count)])
                let selectPlaceholders = String(repeating: "?,", count: chunk.count).dropLast()
                let fetchNewSql = "SELECT \(colTagId), \(colTagNormalizedName), \(colTagName) FROM \(tagsTable) WHERE \(colTagNormalizedName) IN (\(selectPlaceholders))"

                let fetchedNewTags = try _db.fetch(query: fetchNewSql, parameters: chunk) { row -> (Int64, String, String) in
                    let id = row.int64(at: 0)
                    let norm = row.string(at: 1) ?? ""
                    let name = row.string(at: 2) ?? ""
                    return (id, norm, name)
                }

                for (id, normalized, name) in fetchedNewTags {
                    existingTags[normalized] = (id, name)
                    currentTagIds.append(id)
                }
            }
        }

        if !currentTagIds.isEmpty {
            for i in stride(from: 0, to: currentTagIds.count, by: 400) {
                let chunk = Array(currentTagIds[i ..< min(i + 400, currentTagIds.count)])
                let relPlaceholders = String(repeating: "(?, ?),", count: chunk.count).dropLast()
                let insertRelSql = "INSERT OR IGNORE INTO \(annotationTagsTable) (\(colAnnotationTagAnnotationId), \(colAnnotationTagTagId)) VALUES \(relPlaceholders);"

                var relParams: [Any] = []
                for tagId in chunk {
                    relParams.append(annotationId)
                    relParams.append(tagId)
                }
                try _db.execute(query: insertRelSql, parameters: relParams)
            }
        }

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
