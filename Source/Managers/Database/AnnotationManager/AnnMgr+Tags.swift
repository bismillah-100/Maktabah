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
        try transaction {
            for annotationID in uniqueIDs {
                guard var annotation = loadAnnotationById(annotationID) else { continue }
                let mergedTags = sanitizeTagNames(annotation.tags + [normalizedTag])
                guard mergedTags != annotation.tags else { continue }
                try replaceTags(mergedTags, for: annotationID)
                annotation.tags = mergedTags
                annotation.lastModified = now
                updatedAnnotations.append(annotation)
                try exec("UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) = ?;", parameters: [now, annotationID])
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
                try exec("UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) = ?;", parameters: [now, annotationID])
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

        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
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
            let placeholders = Array(repeating: "?", count: normalizedTags.count).joined(separator: ",")

            let findSql = "SELECT \(colTagId), \(colTagName), \(colTagNormalizedName) FROM \(tagsTable) WHERE \(colTagNormalizedName) IN (\(placeholders))"
            let fetchedExisting = try _db.fetch(query: findSql, parameters: normalizedTags) { row -> (Int64, String, String) in
                return (row.int64(at: 0), row.string(at: 1) ?? "", row.string(at: 2) ?? "")
            }
            for (id, name, normalized) in fetchedExisting {
                existingTags[normalized] = (id, name)
            }
        }

        for tag in tags {
            let normalized = normalizedTagName(tag)

            var existingTagId: Int64 = -1
            var existingTagName = ""

            if let existing = existingTags[normalized] {
                existingTagId = existing.id
                existingTagName = existing.name
            }

            let currentTagId: Int64

            if existingTagId != -1 {
                currentTagId = existingTagId
                if existingTagName != tag {
                    let updateSql = "UPDATE \(tagsTable) SET \(colTagName) = ? WHERE \(colTagId) = ?;"
                    try _db.execute(query: updateSql, parameters: [tag, currentTagId])
                    existingTags[normalized] = (currentTagId, tag)
                }
            } else {
                let insertSql = "INSERT INTO \(tagsTable) (\(colTagName), \(colTagNormalizedName)) VALUES (?, ?);"
                try _db.execute(query: insertSql, parameters: [tag, normalized])
                currentTagId = _db.lastInsertRowId()
                existingTags[normalized] = (currentTagId, tag)
            }

            if currentTagId != -1 {
                let insertRelSql = "INSERT OR IGNORE INTO \(annotationTagsTable) (\(colAnnotationTagAnnotationId), \(colAnnotationTagTagId)) VALUES (?, ?);"
                try _db.execute(query: insertRelSql, parameters: [annotationId, currentTagId])
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
