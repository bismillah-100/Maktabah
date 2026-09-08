//
//  AnnotationRepository.swift
//  Maktabah
//

import Foundation
import SQLite3

final class AnnotationRepository: SyncPendingManaging {
    // MARK: - Table & Column Names

    let annotationsTable = "annotations"
    let colAnnId = "id"
    let colAnnBkId = "bkId"
    let colAnnContentId = "contentId"
    let colAnnStart = "startIndex"
    let colAnnStartDiac = "startIndexDiac"
    let colAnnLength = "length"
    let colAnnLengthDiac = "lengthDiac"
    let colAnnColor = "color"
    let colAnnType = "type"
    let colAnnNote = "note"
    let colAnnCreatedAt = "createdAt"
    let colAnnContext = "context"
    let colAnnPage = "page"
    let colAnnPart = "part"
    let colAnnCkRecordId = "ckRecordId"
    let colAnnLastModified = "lastModified"

    let tagsTable = "tags"
    let colTagId = "id"
    let colTagName = "name"
    let colTagNormalizedName = "normalizedName"

    let annotationTagsTable = "annotation_tags"
    let colAnnotationTagAnnotationId = "annotationId"
    let colAnnotationTagTagId = "tagId"

    // MARK: - Singleton & Database

    static let shared = AnnotationRepository()

    var _db: SQLiteDatabase?
    var db: SQLiteDatabase? {
        _db
    }

    var syncPendingStore: SyncPendingStore?
    var dbURL: URL?

    var now: Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private init() {}

    // MARK: - Setup & Connection

    func setupAnnotationsDatabase(at folderURL: URL?) throws -> Bool {
        guard let folderURL else { throw NSError(domain: "maktabah", code: 404) }

        let fm = FileManager.default
        if !fm.fileExists(atPath: folderURL.path) {
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        let url = folderURL.appendingPathComponent("Annotations.sqlite")
        dbURL = url

        let isNewDatabase = !fm.fileExists(atPath: url.path)

        #if DEBUG
        print("AnnotationRepository: setupAnnotationsDatabase at \(url.path), isNewDatabase: \(isNewDatabase)")
        #endif

        connect()
        try createAnnotationsTableAndSchemaIfNeeded()
        try createTagsTablesIfNeeded()
        try createSyncPendingTableIfNeeded()

        return isNewDatabase
    }

    func connect() {
        if let dbURL {
            do {
                let db = try SQLiteDatabase(path: dbURL.path)
                db.enableWALMode()
                _db = db
                syncPendingStore = SyncPendingStore(database: db)
            } catch {
                ReusableFunc.showAlert(title: "Error", message: "Failed to open annotations database: \(error.localizedDescription)")
            }
        }
    }

    func disconnect() {
        _db?.checkpoint()
        _db = nil
        syncPendingStore = nil
    }

    func checkpoint() {
        _db?.checkpoint()
    }

    // MARK: - Schema

    private func createAnnotationsTableAndSchemaIfNeeded() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS \(annotationsTable) (
            \(colAnnId) INTEGER PRIMARY KEY AUTOINCREMENT,
            \(colAnnBkId) INTEGER,
            \(colAnnContentId) INTEGER,
            \(colAnnStart) INTEGER,
            \(colAnnLength) INTEGER,
            \(colAnnStartDiac) INTEGER,
            \(colAnnLengthDiac) INTEGER,
            \(colAnnColor) TEXT,
            \(colAnnType) INTEGER,
            \(colAnnNote) TEXT,
            \(colAnnCreatedAt) INTEGER,
            \(colAnnContext) TEXT,
            \(colAnnPart) INTEGER,
            \(colAnnPage) INTEGER
        );
        """)

        let columns = try listTableColumns(tableName: annotationsTable)
        if !columns.contains(colAnnCkRecordId) {
            try exec("ALTER TABLE \(annotationsTable) ADD COLUMN \(colAnnCkRecordId) TEXT;")
        }
        if !columns.contains(colAnnLastModified) {
            try exec("ALTER TABLE \(annotationsTable) ADD COLUMN \(colAnnLastModified) INTEGER;")
        }

        try exec("CREATE INDEX IF NOT EXISTS idx_ann_bk_content ON \(annotationsTable) (\(colAnnBkId), \(colAnnContentId));")
        try exec("CREATE INDEX IF NOT EXISTS idx_ann_ck_record_id ON \(annotationsTable) (\(colAnnCkRecordId));")
    }

    private func createTagsTablesIfNeeded() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS \(tagsTable) (
            \(colTagId) INTEGER PRIMARY KEY AUTOINCREMENT,
            \(colTagName) TEXT,
            \(colTagNormalizedName) TEXT UNIQUE
        );
        """)

        try exec("""
        CREATE TABLE IF NOT EXISTS \(annotationTagsTable) (
            \(colAnnotationTagAnnotationId) INTEGER,
            \(colAnnotationTagTagId) INTEGER
        );
        """)

        try exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_ann_tag_ids ON \(annotationTagsTable) (\(colAnnotationTagAnnotationId), \(colAnnotationTagTagId));")
    }

    private func createSyncPendingTableIfNeeded() throws {
        try syncPendingStore?.createTable()
    }

    // MARK: - SQLite Helpers

    func exec(_ sql: String, parameters: [Any] = []) throws {
        guard let _db else { return }
        try _db.execute(query: sql, parameters: parameters)
    }

    func transaction(_ block: () throws -> Void) throws {
        guard let _db else { return }
        try _db.transaction(block)
    }

    func listTableColumns(tableName: String) throws -> [String] {
        guard let _db else { return [] }
        return _db.tableColumns(tableName: tableName)
    }

    // MARK: - Row Mapping

    func makeAnnotation(from row: SQLiteRow, tags: [String] = []) -> Annotation {
        let page = row.int(at: 13)
        let part = row.int(at: 12)
        return Annotation(
            id: row.int64(at: 0),
            bkId: row.int(at: 1),
            contentId: row.int(at: 2),
            range: NSRange(location: row.int(at: 3), length: row.int(at: 4)),
            rangeDiacritics: NSRange(location: row.int(at: 5), length: row.int(at: 6)),
            colorHex: row.string(at: 7) ?? "#FFFF00",
            type: AnnotationMode.from(int: row.int(at: 8)),
            note: row.string(at: 9),
            createdAt: row.int64(at: 10),
            context: row.string(at: 11) ?? "",
            page: page,
            part: part,
            pageArb: String(page).convertToArabicDigits(),
            partArb: String(part).convertToArabicDigits(),
            tags: tags,
            ckRecordId: row.string(at: 14),
            lastModified: row.int64(at: 15)
        )
    }

    // MARK: - CRUD DB Operations

    func insertAnnotationRow(
        _ ann: Annotation,
        into db: SQLiteDatabase,
        orReplace: Bool = false
    ) throws -> Int64 {
        let insertVerb = orReplace ? "INSERT OR REPLACE INTO" : "INSERT INTO"
        let sql = """
        \(insertVerb) \(annotationsTable) (
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
            ann.ckRecordId ?? NSNull(),
            ann.lastModified ?? 0,
        ]

        try db.execute(query: sql, parameters: params)
        return db.lastInsertRowId()
    }

    @discardableResult
    func addAnnotation(_ annotation: Annotation) throws -> (id: Int64, saved: Annotation) {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }
        var rowId: Int64 = 0

        var annotationToSave = annotation
        if annotationToSave.ckRecordId == nil {
            annotationToSave.ckRecordId = UUID().uuidString
        }
        annotationToSave.lastModified = now

        let sanitizedTags = sanitizeTagNames(annotationToSave.tags)

        try transaction {
            rowId = try self.insertAnnotationRow(annotationToSave, into: _db)
            if rowId > 0 {
                try self.replaceTags(sanitizedTags, for: rowId)
                if let ckId = annotationToSave.ckRecordId {
                    try self.addPendingSync(ckRecordId: ckId, operation: "upload")
                }
            } else {
                throw NSError(domain: "InsertError", code: -1)
            }
        }

        var saved = annotationToSave
        saved.id = rowId
        saved.pageArb = String(saved.page).convertToArabicDigits()
        saved.partArb = String(saved.part).convertToArabicDigits()
        saved.tags = sanitizedTags

        return (rowId, saved)
    }

    func updateAnnotationRow(_ annotation: Annotation) throws -> Annotation {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }
        guard let id = annotation.id else { throw NSError(domain: "NoID", code: 2) }
        let normalizedTags = sanitizeTagNames(annotation.tags)

        var updatedAnnotation = annotation
        updatedAnnotation.lastModified = now

        try transaction {
            let sql = "UPDATE \(annotationsTable) SET \(colAnnColor) = ?, \(colAnnType) = ?, \(colAnnNote) = ?, \(colAnnLastModified) = ? WHERE \(colAnnId) = ?;"
            let params: [Any] = [
                updatedAnnotation.colorHex,
                updatedAnnotation.type.rawValue,
                updatedAnnotation.note ?? NSNull(),
                updatedAnnotation.lastModified ?? 0,
                id,
            ]
            try _db.execute(query: sql, parameters: params)
            try self.replaceTags(normalizedTags, for: id)
            try self.deleteUnusedTags()

            if let ckId = updatedAnnotation.ckRecordId {
                try self.addPendingSync(ckRecordId: ckId, operation: "upload")
            }
        }

        updatedAnnotation.tags = normalizedTags
        return updatedAnnotation
    }

    func deleteAnnotationRow(id: Int64) throws -> Annotation? {
        guard _db != nil else { throw NSError(domain: "DBNil", code: 1) }
        let deletedAnnotation = try loadAnnotationById(id)

        try transaction {
            try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagAnnotationId) = ?;", parameters: [id])
            try exec("DELETE FROM \(annotationsTable) WHERE \(colAnnId) = ?;", parameters: [id])
            try self.deleteUnusedTags()

            if let ckId = deletedAnnotation?.ckRecordId {
                try self.addPendingSync(ckRecordId: ckId, operation: "delete")
            }
        }

        return deletedAnnotation
    }

    func loadAnnotations(bkId: Int, contentId: Int) throws -> [Annotation] {
        guard let _db else { return [] }
        let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnBkId) = ? AND \(colAnnContentId) = ? ORDER BY \(colAnnStart) ASC;"
        let rows = try _db.fetch(query: sql, parameters: [bkId, contentId]) { self.makeAnnotation(from: $0) }
        return try populateTags(for: rows)
    }

    func loadAnnotations(bkId: Int) throws -> [Annotation] {
        guard let _db else { return [] }
        let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnBkId) = ? ORDER BY \(colAnnStart) ASC;"
        let rows = try _db.fetch(query: sql, parameters: [bkId]) { self.makeAnnotation(from: $0) }
        return try populateTags(for: rows)
    }

    func loadAllAnnotations() throws -> [Annotation] {
        guard let _db else { return [] }
        let sql = "SELECT * FROM \(annotationsTable) ORDER BY \(colAnnStart) ASC;"
        let rows = try _db.fetch(query: sql) { self.makeAnnotation(from: $0) }
        return try populateTags(for: rows)
    }

    func loadAnnotationById(_ id: Int64) throws -> Annotation? {
        guard let _db else { return nil }
        let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnId) = ? LIMIT 1;"
        guard var ann = try _db.fetch(query: sql, parameters: [id], mapping: { self.makeAnnotation(from: $0) }).first else {
            return nil
        }
        ann.tags = try fetchTags(for: id)
        return ann
    }

    func loadAnnotationsByIds(_ ids: [Int64]) throws -> [Annotation] {
        guard let _db, !ids.isEmpty else { return [] }
        var result: [Annotation] = []

        for chunk in ids.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnId) IN (\(placeholders));"
            let rows = try _db.fetch(query: sql, parameters: chunk) { self.makeAnnotation(from: $0) }
            result.append(contentsOf: rows)
        }

        return try populateTags(for: result)
    }

    func fetchAnnotations(byCkRecordIds ckRecordIds: [String]) -> [Annotation] {
        guard let _db, !ckRecordIds.isEmpty else { return [] }
        var result: [Annotation] = []

        for chunk in ckRecordIds.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IN (\(placeholders));"
            if let rows = try? _db.fetch(query: sql, parameters: chunk, mapping: { self.makeAnnotation(from: $0) }) {
                result.append(contentsOf: rows)
            }
        }

        return (try? populateTags(for: result)) ?? result
    }

    private func populateTags(for annotations: [Annotation]) throws -> [Annotation] {
        guard !annotations.isEmpty else { return [] }
        let ids = annotations.compactMap(\.id)
        let tagsMap = try fetchTagsForAnnotations(ids: ids)
        return annotations.map { ann in
            var copy = ann
            if let id = ann.id {
                copy.tags = tagsMap[id] ?? []
            }
            return copy
        }
    }

    func updateAnnotationsBookId(oldId: Int, newId: Int) throws -> [Annotation] {
        guard let _db else { return [] }
        var affectedAnnotations: [Annotation] = []

        try transaction {
            let fetchSql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnBkId) = ?;"
            affectedAnnotations = try _db.fetch(query: fetchSql, parameters: [oldId]) { self.makeAnnotation(from: $0) }

            guard !affectedAnnotations.isEmpty else { return }

            let updateSql = "UPDATE \(annotationsTable) SET \(colAnnBkId) = ?, \(colAnnLastModified) = ? WHERE \(colAnnBkId) = ?;"
            try _db.execute(query: updateSql, parameters: [newId, self.now, oldId])

            for i in 0 ..< affectedAnnotations.count {
                var ann = affectedAnnotations[i]
                if let ckId = ann.ckRecordId {
                    try self.addPendingSync(ckRecordId: ckId, operation: "upload")
                }
                let tags = try self.fetchTags(for: ann.id ?? -1)
                ann.tags = tags
                ann.lastModified = self.now
                affectedAnnotations[i] = ann
            }
        }

        return affectedAnnotations
    }

    func nukeDatabase() throws {
        try transaction {
            try exec("DELETE FROM \(annotationTagsTable);")
            try exec("DELETE FROM \(annotationsTable);")
            try exec("DELETE FROM \(tagsTable);")
        }
    }

    // MARK: - Tag Management Operations

    func fetchAllTagNames() throws -> [String] {
        guard let _db else { return [] }
        let sql = "SELECT \(colTagName) FROM \(tagsTable) ORDER BY \(colTagName) COLLATE NOCASE ASC;"
        return try _db.fetch(query: sql) { $0.string(at: 0) ?? "" }.filter { !$0.isEmpty }
    }

    func fetchTags(for annotationId: Int64) throws -> [String] {
        guard let _db else { return [] }
        let sql = """
        SELECT t.\(colTagName) FROM \(tagsTable) t
        INNER JOIN \(annotationTagsTable) at ON t.\(colTagId) = at.\(colAnnotationTagTagId)
        WHERE at.\(colAnnotationTagAnnotationId) = ?
        ORDER BY t.\(colTagName) COLLATE NOCASE ASC;
        """
        return try _db.fetch(query: sql, parameters: [annotationId]) { $0.string(at: 0) ?? "" }
    }

    func fetchTagsForAnnotations(ids: [Int64]) throws -> [Int64: [String]] {
        guard let _db, !ids.isEmpty else { return [:] }
        var result: [Int64: [String]] = [:]

        for chunk in ids.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let sql = """
            SELECT at.\(colAnnotationTagAnnotationId), t.\(colTagName)
            FROM \(tagsTable) t
            INNER JOIN \(annotationTagsTable) at ON t.\(colTagId) = at.\(colAnnotationTagTagId)
            WHERE at.\(colAnnotationTagAnnotationId) IN (\(placeholders))
            ORDER BY t.\(colTagName) COLLATE NOCASE ASC;
            """
            let rows = try _db.fetch(query: sql, parameters: chunk) { ($0.int64(at: 0), $0.string(at: 1) ?? "") }
            for (annId, tagName) in rows where !tagName.isEmpty {
                result[annId, default: []].append(tagName)
            }
        }

        return result
    }

    func replaceTags(_ tags: [String], for annotationId: Int64) throws {
        guard let _db else { return }
        try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagAnnotationId) = ?;", parameters: [annotationId])

        let sanitized = sanitizeTagNames(tags)
        guard !sanitized.isEmpty else { return }

        for tag in sanitized {
            let normalized = normalizedTagName(tag)
            let insertTagSql = "INSERT OR IGNORE INTO \(tagsTable) (\(colTagName), \(colTagNormalizedName)) VALUES (?, ?);"
            try exec(insertTagSql, parameters: [tag, normalized])

            let selectTagIdSql = "SELECT \(colTagId) FROM \(tagsTable) WHERE \(colTagNormalizedName) = ? LIMIT 1;"
            guard let tagId = try _db.fetch(query: selectTagIdSql, parameters: [normalized], mapping: { $0.int64(at: 0) }).first else {
                continue
            }

            let linkSql = "INSERT OR IGNORE INTO \(annotationTagsTable) (\(colAnnotationTagAnnotationId), \(colAnnotationTagTagId)) VALUES (?, ?);"
            try exec(linkSql, parameters: [annotationId, tagId])
        }
    }

    func deleteUnusedTags() throws {
        let sql = """
        DELETE FROM \(tagsTable)
        WHERE \(colTagId) NOT IN (SELECT DISTINCT \(colAnnotationTagTagId) FROM \(annotationTagsTable));
        """
        try exec(sql)
    }

    func sanitizeTagNames(_ tags: [String]) -> [String] {
        var seenNormalized = Set<String>()
        var result: [String] = []

        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = normalizedTagName(trimmed)
            if seenNormalized.insert(normalized).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    func normalizedTagName(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func saveAndQueueAnnotationChanges(
        _ annotation: Annotation,
        updatedTags: [String]? = nil,
        modifiedTimestamp: Int64
    ) throws -> Annotation {
        var copy = annotation
        if let updatedTags {
            copy.tags = updatedTags
        }
        copy.lastModified = modifiedTimestamp

        if let id = copy.id {
            if let updatedTags {
                try replaceTags(updatedTags, for: id)
            }
            try exec("UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) = ?;", parameters: [modifiedTimestamp, id])
            if let ckId = copy.ckRecordId {
                try addPendingSync(ckRecordId: ckId, operation: "upload")
            }
        }

        return copy
    }

    func renameTag(from oldName: String, to newName: String) throws -> [Annotation] {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }

        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldNormalized = normalizedTagName(oldName)
        let newNormalized = normalizedTagName(trimmedNew)

        guard !newNormalized.isEmpty else {
            throw NSError(domain: "EmptyTagName", code: 3, userInfo: [NSLocalizedDescriptionKey: "Tag name cannot be empty."])
        }
        if oldNormalized == newNormalized, oldName == trimmedNew {
            return []
        }

        let oldTagId = try _db.fetch(
            query: "SELECT \(colTagId) FROM \(tagsTable) WHERE \(colTagNormalizedName) = ? LIMIT 1",
            parameters: [oldNormalized],
            mapping: { $0.int64(at: 0) }
        ).first ?? -1

        guard oldTagId != -1 else { return [] }

        let affectedIds = try _db.fetch(
            query: "SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?",
            parameters: [oldTagId],
            mapping: { $0.int64(at: 0) }
        )

        let existingNewTagId = try _db.fetch(
            query: "SELECT \(colTagId) FROM \(tagsTable) WHERE \(colTagNormalizedName) = ? LIMIT 1",
            parameters: [newNormalized],
            mapping: { $0.int64(at: 0) }
        ).first ?? -1

        let annotations = try loadAnnotationsByIds(affectedIds)
        var updatedAnnotations: [Annotation] = []

        try transaction {
            if existingNewTagId != -1 {
                updatedAnnotations = try self.mergeTags(
                    annotations: annotations,
                    oldTagId: oldTagId,
                    oldNormalized: oldNormalized,
                    newNormalized: newNormalized,
                    trimmedNew: trimmedNew
                )
            } else {
                updatedAnnotations = try self.renameTagRow(
                    annotations: annotations,
                    oldTagId: oldTagId,
                    oldNormalized: oldNormalized,
                    newNormalized: newNormalized,
                    trimmedNew: trimmedNew
                )
            }

            try self.deleteUnusedTags()
        }

        return updatedAnnotations
    }

    private func mergeTags(
        annotations: [Annotation],
        oldTagId: Int64,
        oldNormalized: String,
        newNormalized: String,
        trimmedNew: String
    ) throws -> [Annotation] {
        var updated: [Annotation] = []
        let currentNow = now
        for ann in annotations {
            var tags = ann.tags.filter { self.normalizedTagName($0) != oldNormalized }
            if !tags.contains(where: { self.normalizedTagName($0) == newNormalized }) {
                tags.append(trimmedNew)
            }
            let updatedAnn = try saveAndQueueAnnotationChanges(ann, updatedTags: tags, modifiedTimestamp: currentNow)
            updated.append(updatedAnn)
        }
        try exec("DELETE FROM \(tagsTable) WHERE \(colTagId) = ?;", parameters: [oldTagId])
        return updated
    }

    private func renameTagRow(
        annotations: [Annotation],
        oldTagId: Int64,
        oldNormalized: String,
        newNormalized: String,
        trimmedNew: String
    ) throws -> [Annotation] {
        var updated: [Annotation] = []
        let currentNow = now
        let sql = "UPDATE \(tagsTable) SET \(colTagName) = ?, \(colTagNormalizedName) = ? WHERE \(colTagId) = ?;"
        try exec(sql, parameters: [trimmedNew, newNormalized, oldTagId])
        for ann in annotations {
            var tags = ann.tags.filter { self.normalizedTagName($0) != oldNormalized }
            tags.append(trimmedNew)
            let updatedAnn = try saveAndQueueAnnotationChanges(ann, updatedTags: tags, modifiedTimestamp: currentNow)
            updated.append(updatedAnn)
        }
        return updated
    }

    func deleteTag(named tagName: String) throws -> (deletedTagName: String, updatedAnnotations: [Annotation]) {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }

        let normalized = normalizedTagName(tagName)
        guard let tagId = try _db.fetch(
            query: "SELECT \(colTagId) FROM \(tagsTable) WHERE \(colTagNormalizedName) = ? LIMIT 1;",
            parameters: [normalized],
            mapping: { $0.int64(at: 0) }
        ).first else {
            return (tagName, [])
        }

        let affectedAnnotationIds = try _db.fetch(
            query: "SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?;",
            parameters: [tagId],
            mapping: { $0.int64(at: 0) }
        )

        var updatedAnnotations: [Annotation] = []
        let currentNow = now

        try transaction {
            try self.exec("DELETE FROM \(self.annotationTagsTable) WHERE \(self.colAnnotationTagTagId) = ?;", parameters: [tagId])
            try self.exec("DELETE FROM \(self.tagsTable) WHERE \(self.colTagId) = ?;", parameters: [tagId])

            let annotations = try self.loadAnnotationsByIds(affectedAnnotationIds)
            for ann in annotations {
                var tags = ann.tags
                tags.removeAll { self.normalizedTagName($0) == normalized }
                let updated = try self.saveAndQueueAnnotationChanges(ann, updatedTags: tags, modifiedTimestamp: currentNow)
                updatedAnnotations.append(updated)
            }

            try self.deleteUnusedTags()
        }

        return (tagName, updatedAnnotations)
    }

    private func mutateTags(
        forAnnotationIDs annotationIDs: [Int64],
        tag: String,
        mutation: (inout [String], String, String) -> Bool
    ) throws -> [Annotation] {
        guard !annotationIDs.isEmpty else { return [] }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var updated: [Annotation] = []
        let annotations = try loadAnnotationsByIds(annotationIDs)
        let normalized = normalizedTagName(trimmed)
        let currentNow = now

        try transaction {
            for ann in annotations {
                guard ann.id != nil else { continue }
                var tags = ann.tags
                if mutation(&tags, trimmed, normalized) {
                    let updatedAnn = try self.saveAndQueueAnnotationChanges(ann, updatedTags: tags, modifiedTimestamp: currentNow)
                    updated.append(updatedAnn)
                }
            }
        }

        return updated
    }

    func addTag(_ tag: String, toAnnotationIDs annotationIDs: [Int64]) throws -> [Annotation] {
        try mutateTags(forAnnotationIDs: annotationIDs, tag: tag) { tags, trimmed, normalized in
            if !tags.contains(where: { self.normalizedTagName($0) == normalized }) {
                tags.append(trimmed)
                return true
            }
            return false
        }
    }

    func removeTag(_ tag: String, fromAnnotationIDs annotationIDs: [Int64]) throws -> [Annotation] {
        let updated = try mutateTags(forAnnotationIDs: annotationIDs, tag: tag) { tags, _, normalized in
            if tags.contains(where: { self.normalizedTagName($0) == normalized }) {
                tags.removeAll { self.normalizedTagName($0) == normalized }
                return true
            }
            return false
        }
        if !updated.isEmpty {
            try transaction {
                try self.deleteUnusedTags()
            }
        }
        return updated
    }

    // MARK: - CloudKit Sync DB Operations

    func backfillCloudKitFieldsIfNeeded() throws -> [Annotation] {
        guard let _db else { return [] }

        let sql = "SELECT \(colAnnId), \(colAnnBkId), \(colAnnContentId), \(colAnnStart), \(colAnnCreatedAt) FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IS NULL"
        var backfilledAnnotations: [Annotation] = []

        try transaction {
            struct BackfillRow {
                let id: Int64
                let bkId: Int
                let contentId: Int
                let start: Int
                let createdAt: Int64
            }

            let results = try _db.fetch(query: sql) { row -> BackfillRow in
                BackfillRow(
                    id: row.int64(at: 0),
                    bkId: row.int(at: 1),
                    contentId: row.int(at: 2),
                    start: row.int(at: 3),
                    createdAt: row.int64(at: 4)
                )
            }

            for res in results {
                let deterministicID = "legacy_\(res.bkId)_\(res.contentId)_\(res.start)_\(res.createdAt)"
                try self.exec("UPDATE \(self.annotationsTable) SET \(self.colAnnCkRecordId) = ?, \(self.colAnnLastModified) = ? WHERE \(self.colAnnId) = ?;", parameters: [deterministicID, self.now, res.id])

                if var annotation = try self.loadAnnotationById(res.id) {
                    annotation.ckRecordId = deterministicID
                    annotation.lastModified = self.now
                    backfilledAnnotations.append(annotation)
                }
            }
        }

        return backfilledAnnotations
    }

    func applyCloudKitDeletions(recordIdsToDelete: [String]) throws -> [Annotation] {
        guard let _db, !recordIdsToDelete.isEmpty else { return [] }
        var deletedAnnotations: [Annotation] = []

        for chunk in recordIdsToDelete.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let findSql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IN (\(placeholders))"
            let rows = try _db.fetch(query: findSql, parameters: chunk, mapping: { ($0.int64(at: 0), self.makeAnnotation(from: $0)) })

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

    func applyCloudKitSaves(annotationsToSave: [Annotation]) throws -> (added: [Annotation], updated: [Annotation]) {
        guard let _db, !annotationsToSave.isEmpty else { return ([], []) }

        var addedAnnotations: [Annotation] = []
        var updatedAnnotations: [Annotation] = []

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

        return (addedAnnotations, updatedAnnotations)
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
            let checkSql = "SELECT \(colAnnId), \(colAnnLastModified) FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IS NULL AND \(colAnnBkId) = ? AND \(colAnnContentId) = ? AND \(colAnnStart) = ? AND \(colAnnLength) = ? LIMIT 1;"
            let existingByPos = try db.fetch(
                query: checkSql,
                parameters: [ann.bkId, ann.contentId, ann.range.location, ann.range.length],
                mapping: { ($0.int64(at: 0), $0.int64(at: 1)) }
            ).first

            if let existingByPos {
                let updated = try updateCloudKitAnnotation(db: db, ann: ann, existingId: existingByPos.0)
                return (nil, updated)
            } else {
                let added = try insertCloudKitAnnotation(db: db, ann: ann)
                return (added, nil)
            }
        }
    }

    private func updateCloudKitAnnotation(
        db: SQLiteDatabase,
        ann: Annotation,
        existingId: Int64
    ) throws -> Annotation {
        var annCopy = ann
        annCopy.id = existingId
        let updateSql = "UPDATE \(annotationsTable) SET \(colAnnBkId) = ?, \(colAnnContentId) = ?, \(colAnnStart) = ?, \(colAnnLength) = ?, \(colAnnStartDiac) = ?, \(colAnnLengthDiac) = ?, \(colAnnColor) = ?, \(colAnnType) = ?, \(colAnnNote) = ?, \(colAnnLastModified) = ?, \(colAnnPart) = ?, \(colAnnPage) = ?, \(colAnnCkRecordId) = ? WHERE \(colAnnId) = ?;"

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
            annCopy.ckRecordId ?? NSNull(),
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
        guard rowId > 0 else { return nil }
        annCopy.id = rowId
        try replaceTags(sanitizeTagNames(annCopy.tags), for: rowId)
        return annCopy
    }

    // MARK: - Import Operations

    func importAnnotations(_ annotations: [Annotation], overwrite: Bool = true) throws -> (count: Int, modified: [Annotation]) {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }
        guard !annotations.isEmpty else { return (0, []) }

        var importedCount = 0
        var updatedOrInsertedAnnotations: [Annotation] = []
        let currentTimestamp = now

        try transaction {
            for ann in annotations {
                let existingId = try self.findExistingAnnotationId(db: _db, ann: ann)
                if let existingId {
                    guard overwrite else { continue }
                    let updated = try self.overwriteExistingAnnotation(
                        db: _db,
                        ann: ann,
                        existingId: existingId,
                        currentTimestamp: currentTimestamp
                    )
                    updatedOrInsertedAnnotations.append(updated)
                    importedCount += 1
                } else if let saved = try self.insertNewImportedAnnotation(
                    db: _db,
                    ann: ann,
                    currentTimestamp: currentTimestamp
                ) {
                    updatedOrInsertedAnnotations.append(saved)
                    importedCount += 1
                }
            }
            try self.deleteUnusedTags()
        }

        return (importedCount, updatedOrInsertedAnnotations)
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
        var resolvedCkRecordId = ann.ckRecordId
        if resolvedCkRecordId == nil || resolvedCkRecordId?.isEmpty == true {
            let fetchSql = "SELECT \(colAnnCkRecordId) FROM \(annotationsTable) WHERE \(colAnnId) = ? LIMIT 1;"
            resolvedCkRecordId = try db.fetch(query: fetchSql, parameters: [existingId]) { $0.string(at: 0) }.first ?? nil
            if resolvedCkRecordId == nil || resolvedCkRecordId?.isEmpty == true {
                resolvedCkRecordId = UUID().uuidString
            }
        }

        let updateSql = """
        UPDATE \(annotationsTable) SET
            \(colAnnCkRecordId) = ?,
            \(colAnnColor) = ?,
            \(colAnnType) = ?,
            \(colAnnNote) = ?,
            \(colAnnLastModified) = ?,
            \(colAnnStartDiac) = ?,
            \(colAnnLengthDiac) = ?,
            \(colAnnContext) = ?,
            \(colAnnPart) = ?,
            \(colAnnPage) = ?
        WHERE \(colAnnId) = ?;
        """

        let params: [Any] = [
            resolvedCkRecordId ?? NSNull(),
            ann.colorHex,
            ann.type.rawValue,
            ann.note ?? NSNull(),
            currentTimestamp,
            ann.rangeDiacritics.location,
            ann.rangeDiacritics.length,
            ann.context,
            ann.part,
            ann.page,
            existingId,
        ]

        try db.execute(query: updateSql, parameters: params)
        try replaceTags(sanitizeTagNames(ann.tags), for: existingId)

        var saved = ann
        saved.id = existingId
        saved.ckRecordId = resolvedCkRecordId
        saved.lastModified = currentTimestamp
        saved.tags = sanitizeTagNames(ann.tags)
        return saved
    }

    private func insertNewImportedAnnotation(
        db: SQLiteDatabase,
        ann: Annotation,
        currentTimestamp: Int64
    ) throws -> Annotation? {
        var toInsert = ann
        if toInsert.ckRecordId == nil || toInsert.ckRecordId?.isEmpty == true {
            toInsert.ckRecordId = UUID().uuidString
        }
        toInsert.lastModified = currentTimestamp

        let rowId = try insertAnnotationRow(toInsert, into: db)
        guard rowId > 0 else { return nil }

        try replaceTags(sanitizeTagNames(toInsert.tags), for: rowId)

        var saved = toInsert
        saved.id = rowId
        saved.tags = sanitizeTagNames(toInsert.tags)
        return saved
    }
}
