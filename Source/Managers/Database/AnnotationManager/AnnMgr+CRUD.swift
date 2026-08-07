//
//  AnnotationManager+CRUD.swift
//  Maktabah
//

import Foundation

extension AnnotationManager {
    // MARK: - Add Annotation

    @discardableResult
    func addAnnotation(_ annotation: Annotation) throws -> Int64 {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }
        var rowId: Int64 = 0

        var annotationToSave = annotation
        if annotationToSave.ckRecordId == nil {
            annotationToSave.ckRecordId = UUID().uuidString
        }
        annotationToSave.lastModified = Int64(Date().timeIntervalSince1970)

        try transaction {
            let sql = """
            INSERT INTO \(annotationsTable) (
                \(colAnnBkId), \(colAnnContentId), \(colAnnStart), \(colAnnLength),
                \(colAnnStartDiac), \(colAnnLengthDiac), \(colAnnColor), \(colAnnType),
                \(colAnnNote), \(colAnnCreatedAt), \(colAnnContext), \(colAnnPart),
                \(colAnnPage), \(colAnnCkRecordId), \(colAnnLastModified)
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            let params: [Any] = [
                annotationToSave.bkId,
                annotationToSave.contentId,
                annotationToSave.range.location,
                annotationToSave.range.length,
                annotationToSave.rangeDiacritics.location,
                annotationToSave.rangeDiacritics.length,
                annotationToSave.colorHex,
                annotationToSave.type.rawValue,
                annotationToSave.note ?? NSNull(),
                annotationToSave.createdAt,
                annotationToSave.context,
                annotationToSave.part,
                annotationToSave.page,
                annotationToSave.ckRecordId ?? NSNull(),
                annotationToSave.lastModified ?? 0
            ]

            try _db.execute(query: sql, parameters: params)
            rowId = _db.lastInsertRowId()

            if rowId > 0 {
                try self.replaceTags(self.sanitizeTagNames(annotationToSave.tags), for: rowId)
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
        saved.tags = sanitizeTagNames(annotationToSave.tags)
        updateCacheAfterAdd(saved)

        addAnnotationToTree(saved)

        return rowId
    }

    // MARK: - Update Annotation

    func updateAnnotation(_ annotation: Annotation) throws {
        guard let _db else { throw NSError(domain: "DBNil", code: 1) }
        guard let id = annotation.id else { throw NSError(domain: "NoID", code: 2) }
        let normalizedTags = sanitizeTagNames(annotation.tags)

        var updatedAnnotation = annotation
        updatedAnnotation.lastModified = Int64(Date().timeIntervalSince1970)

        try transaction {
            let sql = "UPDATE \(annotationsTable) SET \(colAnnColor) = ?, \(colAnnType) = ?, \(colAnnNote) = ?, \(colAnnLastModified) = ? WHERE \(colAnnId) = ?;"

            let params: [Any] = [
                updatedAnnotation.colorHex,
                updatedAnnotation.type.rawValue,
                updatedAnnotation.note ?? NSNull(),
                updatedAnnotation.lastModified ?? 0,
                id
            ]

            try _db.execute(query: sql, parameters: params)
            try self.replaceTags(normalizedTags, for: id)

            if let ckId = updatedAnnotation.ckRecordId {
                try self.addPendingSync(ckRecordId: ckId, operation: "upload")
            }
        }

        updatedAnnotation.tags = normalizedTags
        updateCacheAfterUpdate(updatedAnnotation)

        updateAnnotationInTree(updatedAnnotation)
    }

    // MARK: - Delete Annotation

    func deleteAnnotation(id: Int64) throws {
        let annotationToDelete = loadAnnotationById(id)

        try transaction {
            try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagAnnotationId) = ?;", parameters: [id])
            try exec("DELETE FROM \(annotationsTable) WHERE \(colAnnId) = ?;", parameters: [id])
            try self.deleteUnusedTags()
            if let ckId = annotationToDelete?.ckRecordId {
                try self.addPendingSync(ckRecordId: ckId, operation: "delete")
            }
        }

        updateCacheAfterDelete(id: id, annotation: annotationToDelete)

        removeAnnotationFromTree(id: id, deletedAnnotation: annotationToDelete)
    }

    // MARK: - Load Annotations

    func loadAnnotations(bkId: Int, contentId: Int) -> [Annotation] {
        let key = ContentKey(bkId: bkId, contentId: contentId)

        if let cached = _cacheQueue.sync(execute: { _cacheByContent[key] }) {
            return cached
        }

        guard let _db else { return [] }
        var result: [Annotation] = []
        let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnBkId) = ? AND \(colAnnContentId) = ? ORDER BY \(colAnnStart)"

        do {
            var fetched = try _db.fetch(query: sql, parameters: [bkId, contentId]) { self.makeAnnotation(from: $0) }

            let tagsMap = fetchTagsForAnnotations(fetched)
            for i in 0..<fetched.count {
                if let id = fetched[i].id {
                    fetched[i].tags = tagsMap[id] ?? []
                }
            }
            result = fetched

            _cacheQueue.sync {
                _cacheByContent[key] = result
                for ann in result {
                    if let id = ann.id { _cacheById[id] = ann }
                }
            }
        } catch {
            print("Failed to load annotations: \(error)")
        }
        return result
    }

    func loadAnnotations(bkId: Int) -> [Annotation] {
        if let cached = _cacheQueue.sync(execute: { _cacheByBook[bkId] }) {
            return cached
        }

        guard let _db else { return [] }
        var result: [Annotation] = []
        let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnBkId) = ? ORDER BY \(colAnnStart)"

        do {
            var fetched = try _db.fetch(query: sql, parameters: [bkId]) { self.makeAnnotation(from: $0) }

            let tagsMap = fetchTagsForAnnotations(fetched)
            for i in 0..<fetched.count {
                if let id = fetched[i].id {
                    fetched[i].tags = tagsMap[id] ?? []
                }
            }
            result = fetched

            let grouped = Dictionary(grouping: result) { ann in
                ContentKey(bkId: bkId, contentId: ann.contentId)
            }
            _cacheQueue.sync {
                _cacheByBook[bkId] = result
                for (key, anns) in grouped {
                    _cacheByContent[key] = anns
                }
                for ann in result {
                    if let id = ann.id { _cacheById[id] = ann }
                }
            }
        } catch {
            print("Failed to load annotations for book: \(error)")
        }
        return result
    }

    func loadAnnotationById(_ id: Int64) -> Annotation? {
        if let cached = _cacheQueue.sync(execute: { _cacheById[id] }) {
            return cached
        }

        guard let _db else { return nil }
        let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnId) = ? LIMIT 1"
        do {
            if var ann = try _db.fetch(query: sql, parameters: [id], mapping: { self.makeAnnotation(from: $0) }).first {
                ann.tags = loadTags(for: id)

                _cacheQueue.sync {
                    _cacheById[id] = ann
                    let key = ContentKey(bkId: ann.bkId, contentId: ann.contentId)
                    var arr = _cacheByContent[key] ?? []
                    if !arr.contains(where: { $0.id == ann.id }) {
                        let idx = arr.insertionIndex(for: ann) { $0.range.location < $1.range.location }
                        arr.insert(ann, at: idx)
                        _cacheByContent[key] = arr
                    }
                }
                return ann
            }
        } catch {
            print("Failed to load annotation by ID: \(error)")
        }
        return nil
    }

    func fetchAnnotations(byCkRecordIds ckRecordIds: [String]) -> [Annotation] {
        guard let _db else { return [] }
        var annotations: [Annotation] = []
        let chunkSize = 500
        for i in stride(from: 0, to: ckRecordIds.count, by: chunkSize) {
            let chunk = Array(ckRecordIds[i..<min(i + chunkSize, ckRecordIds.count)])
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IN (\(placeholders))"

            if var fetched = try? _db.fetch(query: sql, parameters: chunk, mapping: { self.makeAnnotation(from: $0) }) {
                let tagsMap = fetchTagsForAnnotations(fetched)
                for j in 0..<fetched.count {
                    if let id = fetched[j].id {
                        fetched[j].tags = tagsMap[id] ?? []
                    }
                }
                annotations.append(contentsOf: fetched)
            }
        }
        return annotations
    }

    func loadAnnotations() -> [Annotation] {
        guard let _db else { return [] }
        var result: [Annotation] = []
        let sql = "SELECT * FROM \(annotationsTable) ORDER BY \(colAnnStart)"
        do {
            var fetched = try _db.fetch(query: sql) { self.makeAnnotation(from: $0) }

            let tagsMap = fetchTagsForAnnotations(fetched)
            for i in 0..<fetched.count {
                if let id = fetched[i].id {
                    fetched[i].tags = tagsMap[id] ?? []
                }
            }
            result = fetched
        } catch {
            print("Failed to load all annotations: \(error)")
        }
        return result
    }

    // MARK: - Update Book ID

    @discardableResult
    func updateAnnotationsBookId(oldId: Int, newId: Int) throws -> [Annotation] {
        guard let _db else { return [] }

        let fetchSql = """
        SELECT id FROM \(annotationsTable) WHERE \(colAnnBkId) = ?;
        """

        let affectedIds = (try? _db.fetch(
            query: fetchSql,
            parameters: [oldId]) {
                $0.int64(at: 0)
            }
        ) ?? []

        let updateSql = """
        UPDATE \(annotationsTable) SET \(colAnnBkId) = ?,
        \(colAnnLastModified) = ? WHERE \(colAnnBkId) = ?;
        """

        var annotationsToSync: [Annotation] = []
        try transaction {
            try exec(updateSql, parameters: [newId, now, oldId])
            
            for annId in affectedIds {
                if let ann = loadAnnotationById(annId) {
                    annotationsToSync.append(ann)
                    if let ckId = ann.ckRecordId {
                        try addPendingSync(ckRecordId: ckId, operation: "upload")
                    }
                }
            }
        }

        clearAllCaches()
        invalidateTree()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .annotationDidChange,
                object: self,
                userInfo: [AnnotationNotificationKeys.changeType: AnnotationChangeType.updated.rawValue]
            )
        }

        return annotationsToSync
    }

    // MARK: - Private Helper

    func makeAnnotation(from row: SQLiteRow) -> Annotation {
        let id = row.int64(at: 0)
        let bkId = row.int(at: 1)
        let contentId = row.int(at: 2)
        let start = row.int(at: 3)
        let length = row.int(at: 4)
        let startDiac = row.int(at: 5)
        let lengthDiac = row.int(at: 6)
        let color = row.string(at: 7) ?? ""
        let typeInt = row.int(at: 8)
        let note = row.string(at: 9)
        let createdAt = row.int64(at: 10)
        let context = row.string(at: 11) ?? ""
        let part = row.int(at: 12)
        let page = row.int(at: 13)
        let ckId = row.string(at: 14)
        let lastMod = !row.isNull(at: 15) ? row.int64(at: 15) : nil

        return Annotation(
            id: id,
            bkId: bkId,
            contentId: contentId,
            range: NSRange(location: start, length: length),
            rangeDiacritics: NSRange(location: startDiac, length: lengthDiac),
            colorHex: color,
            type: AnnotationMode.from(int: typeInt),
            note: note,
            createdAt: createdAt,
            context: context,
            page: page,
            part: part,
            pageArb: String(page).convertToArabicDigits(),
            partArb: String(part).convertToArabicDigits(),
            tags: [], // Tags will be loaded in bulk
            ckRecordId: ckId,
            lastModified: lastMod
        )
    }
}
