//
//  AnnotationManager.swift
//  maktab
//
//  Created by MacBook on 15/12/25.
//  Granular Tag UI Update
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation
import SQLite3

// MARK: - Notification Names

extension Notification.Name {
    static let annotationDidChange = Notification.Name("annotationDidChange")
    static let annotationTreeDidUpdate = Notification.Name("annotationTreeDidUpdate")
}

// MARK: - Notification UserInfo Keys

enum AnnotationChangeType: String {
    case added
    case updated
    case deleted
}

enum AnnotationNotificationKeys {
    static let changeType = "changeType"
    static let annotation = "annotation"
    static let annotationId = "annotationId"
    static let tagDiff = "tagDiff"
    static let oldParentIndex = "oldParentIndex"
    static let newParentIndex = "newParentIndex"
}

struct TagUpdateDiff {
    struct RemovedEntry {
        let annotationNode: AnnotationNode // node anotasi yang dihapus
        let tagNode: AnnotationNode // tag node induknya
        let tagNodeBecomesEmpty: Bool // apakah tag node ikut hilang dari root
        let oldIndex: Int // Index item yang dihapus dalam parentnya
    }

    struct AddedEntry {
        let annotationNode: AnnotationNode // node anotasi yang ditambahkan
        let tagNode: AnnotationNode // tag node induknya
        let tagNodeIsNew: Bool // apakah tag node baru dibuat
    }

    let removed: [RemovedEntry]
    let added: [AddedEntry]
    let updated: [AnnotationNode] // annotation node yang hanya di-update teks/warna
}

final class AnnotationManager {
    // MARK: - Table & columns names

    private let annotationsTable = "annotations"
    private let colAnnId = "id"
    private let colAnnBkId = "bkId"
    private let colAnnContentId = "contentId"
    private let colAnnStart = "startIndex"
    private let colAnnStartDiac = "startIndexDiac"
    private let colAnnLength = "length"
    private let colAnnLengthDiac = "lengthDiac"
    private let colAnnColor = "color"
    private let colAnnType = "type"
    private let colAnnNote = "note"
    private let colAnnCreatedAt = "createdAt"
    private let colAnnContext = "context"
    private let colAnnPage = "page"
    private let colAnnPart = "part"
    private let colAnnCkRecordId = "ckRecordId"
    private let colAnnLastModified = "lastModified"

    private let tagsTable = "tags"
    private let colTagId = "id"
    private let colTagName = "name"
    private let colTagNormalizedName = "normalizedName"

    private let annotationTagsTable = "annotation_tags"
    private let colAnnotationTagAnnotationId = "annotationId"
    private let colAnnotationTagTagId = "tagId"

    private(set) var db: SQLiteDatabase?

    static let shared = AnnotationManager()

    // MARK: - Caches

    private var cacheById: [Int64: Annotation] = [:]
    private var cacheByContent: [ContentKey: [Annotation]] = [:]
    private var cacheByBook: [Int: [Annotation]] = [:]
    private var cacheTagsByAnnotationId: [Int64: [String]] = [:]
    private var cachedAllTagNames: [String]?

    private var _rootNode: AnnotationNode?
    private let treeQueue = DispatchQueue(label: "com.maktab.annotationManager.treeQueue", qos: .userInitiated)

    var rootNode: AnnotationNode? {
        treeQueue.sync { _rootNode }
    }

    // State Sorting
    private(set) var sortOption: AnnotationSortOption = .init(field: .createdAt, isAscending: false)
    private(set) var groupingMode: AnnotationGroupingMode = .book

    /// Serial queue to protect caches
    private let cacheQueue = DispatchQueue(label: "com.maktab.annotationManager.cacheQueue", qos: .userInitiated)

    private init() {}

    private var now: Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    // MARK: - Private helper to post notification

    private func postChangeNotification(
        type: AnnotationChangeType,
        annotation: Annotation? = nil,
        annotationsToSync: [Annotation]? = nil,
        annotationId: Int64? = nil,
        diff: TagUpdateDiff? = nil,
        oldParentIndex: Int? = nil,
        newParentIndex: Int? = nil,
        uploadToCloudKit: Bool = true
    ) {
        var userInfo: [String: Any] = [AnnotationNotificationKeys.changeType: type.rawValue]

        if let ann = annotation {
            userInfo[AnnotationNotificationKeys.annotation] = ann
            if type != .deleted { pushRecentColor(ann) }
        }

        if uploadToCloudKit {
            if type == .added || type == .updated {
                let toUpload = annotationsToSync ?? (annotation != nil ? [annotation!] : [])
                if !toUpload.isEmpty {
                    CloudKitSyncManager.shared.upload(annotations: toUpload)
                }
            } else if type == .deleted, let ann = annotation, let ckId = ann.ckRecordId {
                CloudKitSyncManager.shared.delete(ckRecordIds: [ckId], target: .annotation)
            }
        }

        if let id = annotationId {
            userInfo[AnnotationNotificationKeys.annotationId] = id
        }
        if let diff = diff {
            userInfo[AnnotationNotificationKeys.tagDiff] = diff
        }
        if let oldIdx = oldParentIndex {
            userInfo[AnnotationNotificationKeys.oldParentIndex] = oldIdx
        }
        if let newIdx = newParentIndex {
            userInfo[AnnotationNotificationKeys.newParentIndex] = newIdx
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .annotationDidChange,
                object: self,
                userInfo: userInfo
            )
        }
    }

    private var dbURL: URL?

    func setupAnnotations(at folderURL: URL?) throws {
        guard let folderURL else { throw NSError(domain: "maktabah", code: 404) }

        let fm = FileManager.default

        if !fm.fileExists(atPath: folderURL.path) {
            try fm.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true
            )
        }

        let url = folderURL.appendingPathComponent("Annotations.sqlite")
        dbURL = url

        // Deteksi database baru - gunakan .path (property) bukan .path() (function)
        let isNewDatabase = !fm.fileExists(atPath: url.path)

        #if DEBUG
        print("AnnotationManager: setupAnnotations at \(url.path), isNewDatabase: \(isNewDatabase)")
        #endif

        connect()
        clearAllCaches()
        invalidateTree()
        try setupAnnotationsDatabase()

        if isNewDatabase {
            CloudKitSyncManager.shared.resetChangeToken()
        }
    }

    // MARK: - Setup DB in Application Support

    func setupAnnotationsDatabase() throws {
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

        try exec("""
        CREATE TABLE IF NOT EXISTS sync_pending (
            ck_record_id TEXT PRIMARY KEY,
            operation TEXT NOT NULL CHECK(operation IN ('upload', 'delete')),
            queued_at INTEGER NOT NULL
        );
        """)

        try backfillCloudKitFieldsIfNeeded { backfilled in
            if !backfilled.isEmpty {
                DispatchQueue.global(qos: .background).async {
                    CloudKitSyncManager.shared.upload(annotations: backfilled)
                }
            }
        }
    }

    func backfillCloudKitFieldsIfNeeded(completion: (([Annotation]) -> Void)? = nil) throws {
        guard let db else {
            completion?([])
            return
        }

        let sql = "SELECT \(colAnnId), \(colAnnBkId), \(colAnnContentId), \(colAnnStart), \(colAnnCreatedAt) FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IS NULL"
        var backfilledAnnotations: [Annotation] = []

        try transaction {
            let results = try db.fetch(query: sql) { row -> (Int64, Int, Int, Int, Int64) in
                return (
                    row.int64(at: 0),
                    row.int(at: 1),
                    row.int(at: 2),
                    row.int(at: 3),
                    row.int64(at: 4)
                )
            }

            for res in results {
                let id = res.0
                let bkId = res.1
                let contentId = res.2
                let start = res.3
                let createdAt = res.4

                let deterministicID = "legacy_\(bkId)_\(contentId)_\(start)_\(createdAt)"

                try exec("UPDATE \(annotationsTable) SET \(colAnnCkRecordId) = ?, \(colAnnLastModified) = ? WHERE \(colAnnId) = ?;", parameters: [deterministicID, now, id])

                if var annotation = loadAnnotationById(id) {
                    annotation.ckRecordId = deterministicID
                    annotation.lastModified = now
                    backfilledAnnotations.append(annotation)
                }
            }
        }

        completion?(backfilledAnnotations)
    }

    // MARK: - Sync Pending Helpers

    func addPendingSync(ckRecordId: String, operation: String) {
        guard let db else { return }
        let sql = "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES (?, ?, ?);"
        try? db.execute(query: sql, parameters: [ckRecordId, operation, now])
    }

    func removePendingSync(ckRecordIds: [String]) {
        guard let db else { return }
        let placeholders = ckRecordIds.map { _ in "?" }.joined(separator: ",")
        let sql = "DELETE FROM sync_pending WHERE ck_record_id IN (\(placeholders));"
        try? db.execute(query: sql, parameters: ckRecordIds)
    }

    func fetchPendingSync(operation: String) -> [String] {
        guard let db else { return [] }
        let sql = "SELECT ck_record_id FROM sync_pending WHERE operation = ? ORDER BY queued_at ASC;"
        return (try? db.fetch(query: sql, parameters: [operation]) { $0.string(at: 0) ?? "" }) ?? []
    }

    func disconnect() {
        db?.checkpoint()
        db = nil
    }

    func connect() {
        if let dbURL {
            do {
                db = try SQLiteDatabase(path: dbURL.path)
                enableWALMode()
            } catch {
                ReusableFunc.showAlert(title: "Error", message: "Failed to open annotations database: \(error.localizedDescription)")
            }
        }
    }

    private func enableWALMode() {
        guard let db else { return }
        do {
            let mode = try db.fetch(query: "PRAGMA journal_mode = WAL;") { row in
                row.string(at: 0) ?? ""
            }.first

            #if DEBUG
            if mode?.lowercased() != "wal" {
                let currentMode = mode ?? "unknown"
                print("AnnotationManager: failed to enable WAL mode, current mode: \(currentMode)")
            }
            #endif
        } catch {
            #if DEBUG
            print("AnnotationManager: error enabling WAL mode: \(error)")
            #endif
        }
    }

    // MARK: - Native SQLite3 Helpers

    private func exec(_ sql: String, parameters: [Any] = []) throws {
        guard let db else { return }
        try db.execute(query: sql, parameters: parameters)
    }

    private func transaction(_ block: () throws -> Void) throws {
        guard let db else { return }
        try db.transaction(block)
    }

    private func listTableColumns(tableName: String) throws -> [String] {
        guard let db else { return [] }
        let sql = "PRAGMA table_info(\(tableName));"
        return try db.fetch(query: sql) { $0.string(at: 1) ?? "" }
    }

    // MARK: - Add annotation

    @discardableResult
    func addAnnotation(_ annotation: Annotation) throws -> Int64 {
        guard let db else { throw NSError(domain: "DBNil", code: 1) }
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

            try db.execute(query: sql, parameters: params)
            rowId = db.lastInsertRowId()

            if rowId > 0 {
                try self.replaceTags(self.sanitizeTagNames(annotationToSave.tags), for: rowId)
            } else {
                throw NSError(domain: "InsertError", code: -1)
            }
        }

        // Update caches
        var saved = annotationToSave
        saved.id = rowId
        saved.pageArb = String(saved.page).convertToArabicDigits()
        saved.partArb = String(saved.part).convertToArabicDigits()
        saved.tags = sanitizeTagNames(annotationToSave.tags)
        cacheQueue.sync {
            cacheById[rowId] = saved
            cacheTagsByAnnotationId[rowId] = saved.tags
            let key = ContentKey(bkId: saved.bkId, contentId: saved.contentId)
            var arr = cacheByContent[key] ?? []
            let idx = arr.insertionIndex(for: saved) { $0.range.location < $1.range.location }
            arr.insert(saved, at: idx)
            cacheByContent[key] = arr
            // cacheByBook: append jika sudah ada, invalidate jika belum
            if cacheByBook[saved.bkId] != nil {
                cacheByBook[saved.bkId]!.append(saved)
            }
        }

        addAnnotationToTree(saved)

        return rowId
    }

    // MARK: - Update annotation

    func updateAnnotation(_ annotation: Annotation) throws {
        guard let db else { throw NSError(domain: "DBNil", code: 1) }
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

            try db.execute(query: sql, parameters: params)
            try self.replaceTags(normalizedTags, for: id)
        }

        // Update caches
        updatedAnnotation.tags = normalizedTags
        cacheQueue.sync {
            cacheById[id] = updatedAnnotation
            cacheTagsByAnnotationId[id] = normalizedTags
            let key = ContentKey(bkId: updatedAnnotation.bkId, contentId: updatedAnnotation.contentId)
            var arr = cacheByContent[key] ?? []
            if let idx = arr.firstIndex(where: { $0.id == id }) {
                arr[idx] = updatedAnnotation
            } else {
                let idx = arr.insertionIndex(for: updatedAnnotation) { $0.range.location < $1.range.location }
                arr.insert(updatedAnnotation, at: idx)
            }
            cacheByContent[key] = arr
            // cacheByBook: update in-place jika ada
            if var bookArr = cacheByBook[updatedAnnotation.bkId] {
                if let idx = bookArr.firstIndex(where: { $0.id == id }) {
                    bookArr[idx] = updatedAnnotation
                } else {
                    bookArr.append(updatedAnnotation)
                }
                cacheByBook[updatedAnnotation.bkId] = bookArr
            }
        }

        updateAnnotationInTree(updatedAnnotation)
    }

    // MARK: - Rename Tag

    /// Ganti nama tag.
    /// - Jika `newName` (setelah normalisasi) sama dengan tag lain yang sudah ada → **merge**:
    ///   semua anotasi dari tag lama dipindah ke tag yang sudah ada, tag lama dihapus.
    /// - Jika tidak → **simple rename**: hanya nama di DB & cache yang diperbarui.
    /// - Throws `NSError(domain:"EmptyTagName")` jika `newName` kosong setelah trim.
    func renameTag(from oldName: String, to newName: String) throws {
        guard let db else { throw NSError(domain: "DBNil", code: 1) }

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
        if let fetchedId = try db.fetch(query: findOldSql, parameters: [oldNormalized], mapping: { $0.int64(at: 0) }).first {
            oldTagId = fetchedId
        }

        if oldTagId == -1 { return }

        // Affected annotation IDs
        var affectedIds: [Int64] = []
        let findAffectedSql = "SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?"
        affectedIds = try db.fetch(query: findAffectedSql, parameters: [oldTagId], mapping: { $0.int64(at: 0) })

        var updatedAnnotations: [Annotation] = []

        var existingNewTagId: Int64 = -1
        let findNewSql = "SELECT \(colTagId) FROM \(tagsTable) WHERE \(colTagNormalizedName) = ? LIMIT 1"
        if let fetchedId = try db.fetch(query: findNewSql, parameters: [newNormalized], mapping: { $0.int64(at: 0) }).first {
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

                    let insertRelSql = "INSERT OR IGNORE INTO \(annotationTagsTable) (\(colAnnotationTagAnnotationId), \(colAnnotationTagTagId)) VALUES (?, ?);"
                    try exec(insertRelSql, parameters: [annId, existingNewTagId])
                    try exec("UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) = ?;", parameters: [now, annId])
                }
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
                    try exec("UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) = ?;", parameters: [now, annId])
                }
                let updateTagSql = "UPDATE \(tagsTable) SET \(colTagName) = ?, \(colTagNormalizedName) = ? WHERE \(colTagId) = ?;"
                try exec(updateTagSql, parameters: [trimmedNew, newNormalized, oldTagId])
            }
        }

        applyBatchTagUpdates(updatedAnnotations)
    }

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

    // MARK: - Delete annotation

    func deleteAnnotation(id: Int64) throws {
        // Get annotation before deleting (untuk notification)
        let annotationToDelete = loadAnnotationById(id)

        try transaction {
            try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagAnnotationId) = ?;", parameters: [id])
            try exec("DELETE FROM \(annotationsTable) WHERE \(colAnnId) = ?;", parameters: [id])
            try self.deleteUnusedTags()
        }

        // Update caches
        cacheQueue.sync {
            cacheById.removeValue(forKey: id)
            cacheTagsByAnnotationId.removeValue(forKey: id)
            if let bkId = annotationToDelete?.bkId {
                cacheByBook[bkId] = cacheByBook[bkId]?.filter { $0.id != id }
            }
            for (key, anns) in cacheByContent {
                if let idx = anns.firstIndex(where: { $0.id == id }) {
                    var copy = anns
                    copy.remove(at: idx)
                    cacheByContent[key] = copy
                }
            }
        }

        removeAnnotationFromTree(id: id, deletedAnnotation: annotationToDelete)

    }

    // MARK: - Delete Tag (hapus tag dari semua anotasi)

    /// Hapus tag dari DB dan semua anotasi yang memilikinya.
    /// Anotasi tidak dihapus — hanya kehilangan tag ini.
    func deleteTag(named tagNameToDelete: String) throws {
        guard let db else { throw NSError(domain: "DBNil", code: 1) }

        let normalized = normalizedTagName(tagNameToDelete)
        var deletedTagId: Int64 = -1
        let findTagSql = "SELECT \(colTagId) FROM \(tagsTable) WHERE \(colTagNormalizedName) = ? LIMIT 1"
        if let fetchedId = try db.fetch(query: findTagSql, parameters: [normalized], mapping: { $0.int64(at: 0) }).first {
            deletedTagId = fetchedId
        }

        if deletedTagId == -1 { return }

        // Affected annotation IDs
        let findAffectedSql = "SELECT \(colAnnotationTagAnnotationId) FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?"
        let affectedIds = try db.fetch(query: findAffectedSql, parameters: [deletedTagId], mapping: { $0.int64(at: 0) })

        // Hapus relasi & tag dari DB
        try transaction {
            try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagTagId) = ?;", parameters: [deletedTagId])
            try exec("DELETE FROM \(tagsTable) WHERE \(colTagId) = ?;", parameters: [deletedTagId])
            for annId in affectedIds {
                try exec("UPDATE \(annotationsTable) SET \(colAnnLastModified) = ? WHERE \(colAnnId) = ?;", parameters: [now, annId])
            }
        }

        // Update cache
        var updatedAnnotations: [Annotation] = []
        cacheQueue.sync {
            cachedAllTagNames = nil
            for annId in affectedIds {
                guard var ann = cacheById[annId] else { continue }
                ann.tags = ann.tags.filter { normalizedTagName($0) != normalized }
                ann.lastModified = now
                cacheById[annId] = ann
                cacheTagsByAnnotationId[annId] = ann.tags

                let key = ContentKey(bkId: ann.bkId, contentId: ann.contentId)
                var cachedArr = cacheByContent[key] ?? []
                if let idx = cachedArr.firstIndex(where: { $0.id == annId }) {
                    cachedArr[idx] = ann
                    cacheByContent[key] = cachedArr
                }
                if var bookArr = cacheByBook[ann.bkId],
                   let idx = bookArr.firstIndex(where: { $0.id == annId })
                {
                    bookArr[idx] = ann
                    cacheByBook[ann.bkId] = bookArr
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

    private func deleteTagFromTree(
        tagName: String,
        normalizedName _: String,
        updatedAnnotations: [Annotation]
    ) {
        treeQueue.async { [weak self] in
            guard let self, let root = _rootNode else { return }

            guard groupingMode == .tag else {
                // Book mode: tidak ada tag node di tree.
                // Cukup post .updated untuk masing-masing anotasi agar badge tag ter-refresh.
                for ann in updatedAnnotations {
                    postChangeNotification(type: .updated, annotation: ann)
                }
                return
            }

            guard
                let tagNode = root.children.first(where: {
                    $0.kind == .tag && $0.title == tagName
                }),
                let tagIndex = root.children.firstIndex(where: { $0 === tagNode })
            else {
                // Tidak ditemukan di tree — rebuild saja
                buildAnnotationTree()
                return
            }

            // Cukup satu entry untuk menghapus seluruh tag node dari root
            let removedEntries = [
                TagUpdateDiff.RemovedEntry(
                    annotationNode: tagNode, // Node yang dihapus adalah tagNode itu sendiri
                    tagNode: tagNode, // Parent root disimbolkan lewat tagNodeBecomesEmpty
                    tagNodeBecomesEmpty: true,
                    oldIndex: tagIndex
                )
            ]

            // Hapus tag node dari root model
            root.children.remove(at: tagIndex)

            // Anotasi yang kini tidak punya tag → pindah ke Untagged
            let nowUntagged = updatedAnnotations.filter(\.tags.isEmpty)
            var addedEntries: [TagUpdateDiff.AddedEntry] = []

            if !nowUntagged.isEmpty {
                let isNewUntaggedNode: Bool
                let untaggedNode: AnnotationNode
                if let existing = root.children.first(where: { $0.kind == .untagged }) {
                    untaggedNode = existing
                    isNewUntaggedNode = false
                } else {
                    let fresh = AnnotationNode(title: "Untagged".localized, kind: .untagged)
                    root.children.append(fresh)
                    untaggedNode = fresh
                    isNewUntaggedNode = true
                }

                for (i, ann) in nowUntagged.enumerated() {
                    let displayTitle: String = {
                        if let note = ann.note, !note.isEmpty { return note }
                        return ann.context
                    }()
                    let newNode = AnnotationNode(
                        title: displayTitle, kind: .annotation, annotation: ann
                    )
                    let idx = untaggedNode.children.insertionIndex(
                        for: newNode, using: compareNodes
                    )
                    untaggedNode.children.insert(newNode, at: idx)

                    if isNewUntaggedNode {
                        // Hanya satu entry yang dibutuhkan: DataSource insert node baru
                        // (collapsed by default, node akan terlihat saat di-expand)
                        if i == 0 {
                            addedEntries.append(
                                .init(
                                    annotationNode: newNode,
                                    tagNode: untaggedNode,
                                    tagNodeIsNew: true
                                )
                            )
                        }
                    } else {
                        addedEntries.append(
                            .init(
                                annotationNode: newNode,
                                tagNode: untaggedNode,
                                tagNodeIsNew: false
                            )
                        )
                    }
                }
            }

            let diff = TagUpdateDiff(
                removed: removedEntries,
                added: addedEntries,
                updated: []
            )

            // Post notifikasi untuk memicu handleTagModeUpdate di DataSource.
            let representativeId = updatedAnnotations.first?.id ?? -1
            postChangeNotification(type: .updated, annotation: updatedAnnotations.first, annotationsToSync: updatedAnnotations, annotationId: representativeId, diff: diff)
        }
    }

    // MARK: - Private helper

    private func makeAnnotation(from row: SQLiteRow) -> Annotation {
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

    // MARK: - Load annotations for a book content

    func loadAnnotations(bkId: Int, contentId: Int) -> [Annotation] {
        let key = ContentKey(bkId: bkId, contentId: contentId)

        if let cached = cacheQueue.sync(execute: { cacheByContent[key] }) {
            return cached
        }

        guard let db else { return [] }
        var result: [Annotation] = []
        let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnBkId) = ? AND \(colAnnContentId) = ? ORDER BY \(colAnnStart)"

        do {
            var fetched = try db.fetch(query: sql, parameters: [bkId, contentId]) { self.makeAnnotation(from: $0) }

            // Bulk load tags
            let tagsMap = fetchTagsForAnnotations(fetched)
            for i in 0..<fetched.count {
                if let id = fetched[i].id {
                    fetched[i].tags = tagsMap[id] ?? []
                }
            }
            result = fetched

            cacheQueue.sync {
                cacheByContent[key] = result
                for ann in result {
                    if let id = ann.id { cacheById[id] = ann }
                }
            }
        } catch {
            print("Failed to load annotations: \(error)")
        }
        return result
    }

    // MARK: - Load by bkId

    func loadAnnotations(bkId: Int) -> [Annotation] {
        if let cached = cacheQueue.sync(execute: { cacheByBook[bkId] }) {
            return cached
        }

        guard let db else { return [] }
        var result: [Annotation] = []
        let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnBkId) = ? ORDER BY \(colAnnStart)"

        do {
            var fetched = try db.fetch(query: sql, parameters: [bkId]) { self.makeAnnotation(from: $0) }

            // Bulk load tags
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
            cacheQueue.sync {
                cacheByBook[bkId] = result
                for (key, anns) in grouped {
                    cacheByContent[key] = anns
                }
                for ann in result {
                    if let id = ann.id { cacheById[id] = ann }
                }
            }
        } catch {
            print("Failed to load annotations for book: \(error)")
        }
        return result
    }

    // MARK: - Load single annotation by id

    func loadAnnotationById(_ id: Int64) -> Annotation? {
        if let cached = cacheQueue.sync(execute: { cacheById[id] }) {
            return cached
        }

        guard let db else { return nil }
        let sql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnId) = ? LIMIT 1"
        do {
            if var ann = try db.fetch(query: sql, parameters: [id], mapping: { self.makeAnnotation(from: $0) }).first {
                // Load tags separately
                ann.tags = loadTags(for: id)

                cacheQueue.sync {
                    cacheById[id] = ann
                    let key = ContentKey(bkId: ann.bkId, contentId: ann.contentId)
                    var arr = cacheByContent[key] ?? []
                    if !arr.contains(where: { $0.id == ann.id }) {
                        let idx = arr.insertionIndex(for: ann) { $0.range.location < $1.range.location }
                        arr.insert(ann, at: idx)
                        cacheByContent[key] = arr
                    }
                }
                return ann
            }
        } catch {
            print("Failed to load annotation by ID: \(error)")
        }
        return nil
    }

    // MARK: - Cache helpers

    func clearAllCaches() {
        cacheQueue.sync {
            cacheById.removeAll()
            cacheByContent.removeAll()
            cacheByBook.removeAll()
            cacheTagsByAnnotationId.removeAll()
            cachedAllTagNames = nil
        }
    }

    @discardableResult
    func updateAnnotationsBookId(oldId: Int, newId: Int) throws -> [Annotation] {
        guard let db else { return [] }

        // 1. Fetch ID anotasi yang akan diupdate (untuk CloudKit sync)
        let fetchSql = """
        SELECT id FROM \(annotationsTable) WHERE \(colAnnBkId) = ?;
        """

        let affectedIds = (try? db.fetch(
            query: fetchSql,
            parameters: [oldId]) {
                $0.int64(at: 0)
            }
        ) ?? []

        // 2. Update bkId di DB — harus berhasil, jika tidak anotasi menunjuk bkId lama
        let updateSql = """
        UPDATE \(annotationsTable) SET \(colAnnBkId) = ?,
        \(colAnnLastModified) = ? WHERE \(colAnnBkId) = ?;
        """

        try db.execute(query: updateSql, parameters: [newId, now, oldId])

        clearAllCaches()
        invalidateTree()

        // 3. Load anotasi yang sudah diupdate + daftarkan pending sync sebagai safety net
        // (Caller bertanggung jawab upload ke CloudKit setelah library data di-reload)
        var annotationsToSync: [Annotation] = []
        for annId in affectedIds {
            if let ann = loadAnnotationById(annId) {
                annotationsToSync.append(ann)
                if let ckId = ann.ckRecordId {
                    // Safety net: jika app crash sebelum upload, akan di-retry saat launch
                    addPendingSync(ckRecordId: ckId, operation: "upload")
                }
            }
        }

        // Post notification untuk update UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .annotationDidChange,
                object: self,
                userInfo: [AnnotationNotificationKeys.changeType: AnnotationChangeType.updated.rawValue]
            )
        }

        return annotationsToSync
    }

    // MARK: - DISPLAY ALL ANNOTATIONS

    func loadAnnotations() -> [Annotation] {
        guard let db else { return [] }
        var result: [Annotation] = []
        let sql = "SELECT * FROM \(annotationsTable) ORDER BY \(colAnnStart)"
        do {
            var fetched = try db.fetch(query: sql) { self.makeAnnotation(from: $0) }

            // Bulk load tags
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

    // MARK: - Build Tree

    func buildAnnotationTree() {
        treeQueue.async { [weak self] in
            guard let self else { return }

            let root = AnnotationNode(title: "All Annotations", kind: .root)
            var anns = loadAnnotations()
            
            if UserDefaults.standard.bool(forKey: "hideMissingBookAnnotations") {
                let uniqueBkIds = Set(anns.map { $0.bkId })
                let existingBkIds = Set(uniqueBkIds.filter { !LibraryDataManager.shared.getBook([$0]).isEmpty })
                anns = anns.filter { existingBkIds.contains($0.bkId) }
            }
            
            switch groupingMode {
            case .book:
                populateBookTree(root: root, annotations: anns)
            case .tag:
                populateTagTree(root: root, annotations: anns)
            }

            sortNodeChildren(root)

            _rootNode = root

            // Post notification bahwa tree sudah ready
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .annotationTreeDidUpdate,
                    object: self
                )
            }
        }
    }

    // MARK: - Tree Manipulation

    func updateSorting(field: AnnotationSortField, isAscending: Bool) {
        treeQueue.async { [weak self] in
            guard let self else { return }
            sortOption = .init(field: field, isAscending: isAscending)
            guard let root = _rootNode else { return }
            sortNodeChildren(root)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .annotationTreeDidUpdate, object: self)
            }
        }
    }

    private func sortNodeChildren(_ node: AnnotationNode) {
        if !node.children.isEmpty {
            node.children.sort(by: compareNodes)
        }
        for child in node.children {
            sortNodeChildren(child)
        }
    }

    private func compareNodes(_ lhs: AnnotationNode, _ rhs: AnnotationNode) -> Bool {
        // KASUS 1: Anotasi (Item di dalam buku)
        if let left = lhs.annotation, let right = rhs.annotation {
            let orderedAscending: Bool
            switch sortOption.field {
            case .createdAt:
                orderedAscending = left.createdAt == right.createdAt
                    ? left.context.localizedCaseInsensitiveCompare(right.context) == .orderedAscending
                    : left.createdAt < right.createdAt
            case .context:
                let contextOrder = left.context.localizedCaseInsensitiveCompare(right.context)
                orderedAscending = contextOrder == .orderedSame
                    ? left.createdAt < right.createdAt
                    : contextOrder == .orderedAscending
            case .page:
                orderedAscending = left.page == right.page
                    ? left.createdAt < right.createdAt
                    : left.page < right.page
            case .part:
                if left.part == right.part {
                    orderedAscending = left.page == right.page
                        ? left.createdAt < right.createdAt
                        : left.page < right.page
                } else {
                    orderedAscending = left.part < right.part
                }
            }
            return sortOption.isAscending ? orderedAscending : !orderedAscending
        }

        // KASUS 2: Buku (Parent Nodes)
        if lhs.annotation == nil, rhs.annotation == nil {
            if sortOption.field == .createdAt {
                let leftLatest = lhs.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
                let rightLatest = rhs.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
                if leftLatest != rightLatest {
                    let orderedAscending = leftLatest < rightLatest
                    return sortOption.isAscending ? orderedAscending : !orderedAscending
                }
            }
            // Selain Date Created: SELALU urutkan Buku berdasarkan Judul A-Z
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    func addAnnotationToTree(_ annotation: Annotation, uploadToCloudKit: Bool = true) {
        treeQueue.async { [weak self] in
            guard let self else { return }
            guard groupingMode == .book else {
                addAnnotationToTagTree(annotation, uploadToCloudKit: uploadToCloudKit)
                return
            }
            guard let root = _rootNode else {
                postChangeNotification(type: .added, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
                return
            }

            let bookNode = findOrCreateBookNode(for: annotation.bkId, in: root)

            let displayTitle: String = if let note = annotation.note, !note.isEmpty {
                note
            } else {
                annotation.context
            }

            let annotationNode = AnnotationNode(
                title: displayTitle,
                kind: .annotation,
                annotation: annotation
            )

            // Optimization: Use insertionIndex instead of append + sort
            let index = bookNode.children.insertionIndex(for: annotationNode, using: compareNodes)
            bookNode.children.insert(annotationNode, at: index)

            var oldParentIdx: Int?
            var newParentIdx: Int?

            // Jika sorting berdasarkan Date, posisi bookNode di root mungkin perlu bergeser
            if sortOption.field == .createdAt {
                if let oldIndex = root.children.firstIndex(where: { $0 === bookNode }) {
                    oldParentIdx = oldIndex
                    root.children.remove(at: oldIndex)
                }
                let newIndex = root.children.insertionIndex(for: bookNode, using: compareNodes)
                root.children.insert(bookNode, at: newIndex)
                newParentIdx = newIndex
            }

            postChangeNotification(type: .added, annotation: annotation, oldParentIndex: oldParentIdx, newParentIndex: newParentIdx, uploadToCloudKit: uploadToCloudKit)
        }
    }

    func updateAnnotationInTree(_ annotation: Annotation, uploadToCloudKit: Bool = true) {
        treeQueue.async { [weak self] in
            guard let self else { return }
            guard groupingMode == .book else {
                updateAnnotationInTagTree(annotation, uploadToCloudKit: uploadToCloudKit)
                return
            }
            guard let annotationId = annotation.id,
                  let node = findAnnotationNode(by: annotationId)
            else {
                postChangeNotification(type: .updated, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
                return
            }

            if let note = annotation.note, !note.isEmpty {
                node.title = note
            } else {
                node.title = annotation.context
            }
            node.annotation = annotation

            postChangeNotification(type: .updated, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
        }
    }

    func removeAnnotationFromTree(id: Int64, deletedAnnotation: Annotation?, uploadToCloudKit: Bool = true) {
        treeQueue.async { [weak self] in
            guard let self else { return }
            guard groupingMode == .book else {
                let diff = removeAnnotationFromTagTree(id: id)
                postChangeNotification(type: .deleted, annotation: deletedAnnotation, annotationId: id, diff: diff, uploadToCloudKit: uploadToCloudKit)
                return
            }
            guard let root = _rootNode else {
                postChangeNotification(type: .deleted, annotation: deletedAnnotation, annotationId: id, uploadToCloudKit: uploadToCloudKit)
                return
            }

            for bookNode in root.children {
                if let index = bookNode.children.firstIndex(where: { $0.annotation?.id == id }) {
                    bookNode.children.remove(at: index)

                    var oldParentIdx: Int?
                    var newParentIdx: Int?

                    if bookNode.children.isEmpty {
                        if let bookIndex = root.children.firstIndex(where: { $0 === bookNode }) {
                            root.children.remove(at: bookIndex)
                        }
                    } else if sortOption.field == .createdAt {
                        if let oldIdx = root.children.firstIndex(where: { $0 === bookNode }) {
                            oldParentIdx = oldIdx
                            root.children.remove(at: oldIdx)
                        }
                        let newIdx = root.children.insertionIndex(for: bookNode, using: compareNodes)
                        root.children.insert(bookNode, at: newIdx)
                        newParentIdx = newIdx
                    }

                    postChangeNotification(type: .deleted, annotation: deletedAnnotation, annotationId: id, oldParentIndex: oldParentIdx, newParentIndex: newParentIdx, uploadToCloudKit: uploadToCloudKit)
                    return
                }
            }

            postChangeNotification(type: .deleted, annotation: deletedAnnotation, annotationId: id, uploadToCloudKit: uploadToCloudKit)
        }
    }

    // MARK: - Tag Tree Manipulation (Granular)

    private func addAnnotationToTagTree(_ annotation: Annotation, uploadToCloudKit: Bool = true) {
        guard let root = _rootNode else {
            postChangeNotification(type: .added, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
            return
        }

        let tags = sanitizeTagNames(annotation.tags)
        let displayTitle =
            (annotation.note != nil && !annotation.note!.isEmpty)
                ? annotation.note! : annotation.context
        var addedEntries: [TagUpdateDiff.AddedEntry] = []

        if tags.isEmpty {
            let isNew: Bool
            let untaggedNode: AnnotationNode
            if let existing = root.children.first(where: { $0.kind == .untagged }) {
                untaggedNode = existing
                isNew = false
            } else {
                let fresh = AnnotationNode(title: "Untagged".localized, kind: .untagged)
                root.children.append(fresh)
                untaggedNode = fresh
                isNew = true
            }

            let newNode = AnnotationNode(
                title: displayTitle, kind: .annotation, annotation: annotation
            )
            let idx = untaggedNode.children.insertionIndex(for: newNode, using: compareNodes)
            untaggedNode.children.insert(newNode, at: idx)
            addedEntries.append(
                .init(annotationNode: newNode, tagNode: untaggedNode, tagNodeIsNew: isNew)
            )
        } else {
            for tag in tags {
                if let tagNode = root.children.first(where: { $0.kind == .tag && $0.title == tag }) {
                    let newNode = AnnotationNode(
                        title: displayTitle, kind: .annotation, annotation: annotation
                    )
                    let idx = tagNode.children.insertionIndex(for: newNode, using: compareNodes)
                    tagNode.children.insert(newNode, at: idx)
                    addedEntries.append(
                        .init(annotationNode: newNode, tagNode: tagNode, tagNodeIsNew: false)
                    )
                } else {
                    let tagNode = AnnotationNode(title: tag, kind: .tag)
                    let newNode = AnnotationNode(
                        title: displayTitle, kind: .annotation, annotation: annotation
                    )
                    tagNode.children.append(newNode)

                    let insertIdx =
                        root.children.firstIndex(where: { node in
                            guard node.kind == .tag else { return node.kind == .untagged }
                            return tag.localizedCaseInsensitiveCompare(node.title)
                                == .orderedAscending
                        })
                        ?? (root.children.firstIndex(where: { $0.kind == .untagged })
                            ?? root.children.endIndex)

                    root.children.insert(tagNode, at: insertIdx)
                    addedEntries.append(
                        .init(annotationNode: newNode, tagNode: tagNode, tagNodeIsNew: true)
                    )
                }
            }
        }

        let diff = TagUpdateDiff(removed: [], added: addedEntries, updated: [])
        postChangeNotification(type: .added, annotation: annotation, diff: diff)
    }

    private func updateAnnotationInTagTree(_ annotation: Annotation, uploadToCloudKit: Bool = true) {
        guard let id = annotation.id, let root = _rootNode else {
            buildAnnotationTree()
            return
        }

        let displayTitle: String = {
            if let note = annotation.note, !note.isEmpty { return note }
            return annotation.context
        }()

        let newTags = Set(sanitizeTagNames(annotation.tags))

        var existingTagNodes: [AnnotationNode] = []
        for tagNode in root.children {
            if tagNode.children.contains(where: { $0.annotation?.id == id }) {
                existingTagNodes.append(tagNode)
            }
        }

        let existingTagNames = Set(existingTagNodes.compactMap { $0.kind == .tag ? $0.title : nil })
        let isCurrentlyUntagged = existingTagNodes.contains(where: { $0.kind == .untagged })

        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        var addedEntries: [TagUpdateDiff.AddedEntry] = []
        var updatedNodes: [AnnotationNode] = []

        // Hapus dari tag yang sudah tidak ada
        for tagNode in existingTagNodes
            where existingTagNames.subtracting(newTags).contains(tagNode.title)
        {
            // Capture annotation node SEBELUM dihapus
            if let annIdx = tagNode.children.firstIndex(where: { $0.annotation?.id == id }) {
                let annNode = tagNode.children[annIdx]
                let becomesEmpty = tagNode.children.count == 1
                let oldIndex = becomesEmpty ? (root.children.firstIndex(where: { $0 === tagNode }) ?? -1) : annIdx

                removedEntries.append(.init(
                    annotationNode: annNode,
                    tagNode: tagNode,
                    tagNodeBecomesEmpty: becomesEmpty,
                    oldIndex: oldIndex
                ))

                tagNode.children.remove(at: annIdx)
                if becomesEmpty {
                    root.children.removeAll { $0 === tagNode }
                }
            }
        }

        // Hapus dari untagged jika sekarang punya tag
        if isCurrentlyUntagged, !newTags.isEmpty {
            if let untaggedNode = root.children.first(where: { $0.kind == .untagged }) {
                if let annIdx = untaggedNode.children.firstIndex(where: { $0.annotation?.id == id }) {
                    let annNode = untaggedNode.children[annIdx]
                    let becomesEmpty = untaggedNode.children.count == 1
                    let oldIndex = becomesEmpty ? (root.children.firstIndex(where: { $0 === untaggedNode }) ?? -1) : annIdx

                    removedEntries.append(.init(
                        annotationNode: annNode,
                        tagNode: untaggedNode,
                        tagNodeBecomesEmpty: becomesEmpty,
                        oldIndex: oldIndex
                    ))

                    untaggedNode.children.remove(at: annIdx)
                    if becomesEmpty {
                        root.children.removeAll { $0 === untaggedNode }
                    }
                }
            }
        }

        // Update node yang masih ada (tag tidak berubah, hanya teks/warna)
        for tagNode in root.children
            where existingTagNames.intersection(newTags).contains(tagNode.title)
        {
            if let node = tagNode.children.first(where: { $0.annotation?.id == id }) {
                node.title = displayTitle
                node.annotation = annotation
                updatedNodes.append(node)
            }
        }

        // Tambah ke tag baru
        for tag in newTags.subtracting(existingTagNames) {
            if let tagNode = root.children.first(where: { $0.kind == .tag && $0.title == tag }) {
                let newNode = AnnotationNode(
                    title: displayTitle, kind: .annotation, annotation: annotation
                )
                let idx = tagNode.children.insertionIndex(for: newNode, using: compareNodes)
                tagNode.children.insert(newNode, at: idx)
                addedEntries.append(.init(
                    annotationNode: newNode,
                    tagNode: tagNode,
                    tagNodeIsNew: false
                ))
            } else {
                let tagNode = AnnotationNode(title: tag, kind: .tag)
                let newNode = AnnotationNode(
                    title: displayTitle, kind: .annotation, annotation: annotation
                )
                tagNode.children.append(newNode)
                let insertIdx =
                    root.children.firstIndex(where: { node in
                        guard node.kind == .tag else { return node.kind == .untagged }
                        return tag.localizedCaseInsensitiveCompare(node.title) == .orderedAscending
                    })
                    ?? (root.children.firstIndex(where: { $0.kind == .untagged })
                        ?? root.children.endIndex)
                root.children.insert(tagNode, at: insertIdx)
                addedEntries.append(.init(
                    annotationNode: newNode,
                    tagNode: tagNode,
                    tagNodeIsNew: true
                ))
            }
        }

        // Masuk untagged jika sekarang tidak ada tag
        if newTags.isEmpty, !isCurrentlyUntagged {
            if let untaggedNode = root.children.first(where: { $0.kind == .untagged }) {
                let newNode = AnnotationNode(
                    title: displayTitle, kind: .annotation, annotation: annotation
                )
                let idx = untaggedNode.children.insertionIndex(for: newNode, using: compareNodes)
                untaggedNode.children.insert(newNode, at: idx)
                addedEntries.append(.init(
                    annotationNode: newNode,
                    tagNode: untaggedNode,
                    tagNodeIsNew: false
                ))
            } else {
                let untaggedNode = AnnotationNode(title: "Untagged".localized, kind: .untagged)
                let newNode = AnnotationNode(
                    title: displayTitle, kind: .annotation, annotation: annotation
                )
                untaggedNode.children.append(newNode)
                root.children.append(untaggedNode)
                addedEntries.append(.init(
                    annotationNode: newNode,
                    tagNode: untaggedNode,
                    tagNodeIsNew: true
                ))
            }
        }

        // Kirim notifikasi dengan diff
        let diff = TagUpdateDiff(
            removed: removedEntries,
            added: addedEntries,
            updated: updatedNodes
        )
        postChangeNotification(type: .updated, annotation: annotation, diff: diff, uploadToCloudKit: uploadToCloudKit)
    }

    @discardableResult
    private func removeAnnotationFromTagTree(id: Int64) -> TagUpdateDiff? {
        guard let root = _rootNode else { return nil }

        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        for tagNode in root.children {
            guard let annIdx = tagNode.children.firstIndex(where: { $0.annotation?.id == id }) else {
                continue
            }

            let annNode = tagNode.children[annIdx]
            let becomesEmpty = tagNode.children.count == 1
            let oldIndex = becomesEmpty ? (root.children.firstIndex(where: { $0 === tagNode }) ?? -1) : annIdx

            removedEntries.append(.init(
                annotationNode: annNode,
                tagNode: tagNode,
                tagNodeBecomesEmpty: becomesEmpty,
                oldIndex: oldIndex
            ))

            tagNode.children.remove(at: annIdx)
        }

        for entry in removedEntries where entry.tagNodeBecomesEmpty {
            root.children.removeAll { $0 === entry.tagNode }
        }

        return TagUpdateDiff(
            removed: removedEntries,
            added: [],
            updated: []
        )
    }

    // MARK: - Private Helpers

    private func findOrCreateBookNode(for bkId: Int, in root: AnnotationNode) -> AnnotationNode {
        if let existing = root.children.first(where: { node in
            guard let firstChild = node.children.first,
                  let annotation = firstChild.annotation else { return false }
            return annotation.bkId == bkId
        }) {
            return existing
        }

        guard let book = LibraryDataManager.shared.getBook([bkId]).first else {
            let fallbackNode = AnnotationNode(title: "Unknown Book", kind: .book)
            // Optimization: Insert using insertionIndex
            let idx = root.children.insertionIndex(for: fallbackNode, using: compareNodes)
            root.children.insert(fallbackNode, at: idx)
            return fallbackNode
        }

        let bookNode = AnnotationNode(title: book.book, kind: .book)
        // Optimization: Insert using insertionIndex
        let idx = root.children.insertionIndex(for: bookNode, using: compareNodes)
        root.children.insert(bookNode, at: idx)

        return bookNode
    }

    private func findAnnotationNode(by id: Int64) -> AnnotationNode? {
        guard let root = _rootNode else { return nil }

        for bookNode in root.children {
            if let found = bookNode.children.first(where: { $0.annotation?.id == id }) {
                return found
            }
        }
        return nil
    }

    // MARK: - Invalidate Cache

    func invalidateTree() {
        treeQueue.async { [weak self] in
            self?._rootNode = nil
        }
    }

    func updateGroupingMode(_ mode: AnnotationGroupingMode) {
        groupingMode = mode
        invalidateTree()
        buildAnnotationTree()
    }

    private func applyBatchTagUpdates(_ annotations: [Annotation], uploadToCloudKit: Bool = true) {
        guard !annotations.isEmpty else { return }

        cacheQueue.sync {
            cachedAllTagNames = nil
            for annotation in annotations {
                guard let id = annotation.id else { continue }
                cacheById[id] = annotation
                cacheTagsByAnnotationId[id] = annotation.tags

                let key = ContentKey(bkId: annotation.bkId, contentId: annotation.contentId)
                var cachedAnnotations = cacheByContent[key] ?? []
                if let index = cachedAnnotations.firstIndex(where: { $0.id == id }) {
                    cachedAnnotations[index] = annotation
                } else {
                    let index = cachedAnnotations.insertionIndex(for: annotation) {
                        $0.range.location < $1.range.location
                    }
                    cachedAnnotations.insert(annotation, at: index)
                }
                cacheByContent[key] = cachedAnnotations

                if var bookArr = cacheByBook[annotation.bkId] {
                    if let index = bookArr.firstIndex(where: { $0.id == id }) {
                        bookArr[index] = annotation
                    } else {
                        bookArr.append(annotation)
                    }
                    cacheByBook[annotation.bkId] = bookArr
                }
            }
        }

        treeQueue.async { [weak self] in
            guard let self else { return }
            if self.groupingMode == .book {
                for annotation in annotations {
                    guard let annotationId = annotation.id,
                          let node = self.findAnnotationNode(by: annotationId)
                    else {
                        self.postChangeNotification(type: .updated, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
                        continue
                    }
                    if let note = annotation.note, !note.isEmpty {
                        node.title = note
                    } else {
                        node.title = annotation.context
                    }
                    node.annotation = annotation
                    self.postChangeNotification(type: .updated, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
                }
            } else {
                self.performBatchTagTreeUpdate(annotations, uploadToCloudKit: uploadToCloudKit)
            }
        }
    }

    private func performBatchTagTreeUpdate(_ annotations: [Annotation], uploadToCloudKit: Bool = true) {
        guard let root = _rootNode else { return }

        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        var addedEntries: [TagUpdateDiff.AddedEntry] = []
        var updatedNodes: [AnnotationNode] = []

        let updatedAnnsDict = Dictionary(uniqueKeysWithValues: annotations.compactMap { ann in ann.id.map { ($0, ann) } })

        for tagNode in root.children {
            var indicesToRemove: [Int] = []

            for (idx, child) in tagNode.children.enumerated() {
                guard let id = child.annotation?.id, let updatedAnn = updatedAnnsDict[id] else { continue }

                let newTags = Set(sanitizeTagNames(updatedAnn.tags))

                let displayTitle: String = {
                    if let note = updatedAnn.note, !note.isEmpty { return note }
                    return updatedAnn.context
                }()

                let shouldRemove: Bool
                if tagNode.kind == .untagged {
                    shouldRemove = !newTags.isEmpty
                } else {
                    shouldRemove = !newTags.contains(tagNode.title)
                }

                if shouldRemove {
                    indicesToRemove.append(idx)
                } else {
                    child.title = displayTitle
                    child.annotation = updatedAnn
                    updatedNodes.append(child)
                }
            }

            if !indicesToRemove.isEmpty {
                let becomesEmpty = indicesToRemove.count == tagNode.children.count
                let oldTagIndex = root.children.firstIndex(where: { $0 === tagNode }) ?? -1

                for idx in indicesToRemove {
                    removedEntries.append(.init(
                        annotationNode: tagNode.children[idx],
                        tagNode: tagNode,
                        tagNodeBecomesEmpty: becomesEmpty,
                        oldIndex: becomesEmpty ? oldTagIndex : idx
                    ))
                }

                for idx in indicesToRemove.reversed() {
                    tagNode.children.remove(at: idx)
                }
            }
        }

        root.children.removeAll { tagNode in
            tagNode.children.isEmpty && tagNode.kind != .root
        }

        for annotation in annotations {
            guard let id = annotation.id else { continue }
            let newTags = Set(sanitizeTagNames(annotation.tags))

            let displayTitle: String = {
                if let note = annotation.note, !note.isEmpty { return note }
                return annotation.context
            }()

            if newTags.isEmpty {
                if let untaggedNode = root.children.first(where: { $0.kind == .untagged }) {
                    if !untaggedNode.children.contains(where: { $0.annotation?.id == id }) {
                        let newNode = AnnotationNode(title: displayTitle, kind: .annotation, annotation: annotation)
                        let idx = untaggedNode.children.insertionIndex(for: newNode, using: compareNodes)
                        untaggedNode.children.insert(newNode, at: idx)
                        addedEntries.append(.init(annotationNode: newNode, tagNode: untaggedNode, tagNodeIsNew: false))
                    }
                } else {
                    let untaggedNode = AnnotationNode(title: String(localized: "Untagged"), kind: .untagged)
                    let newNode = AnnotationNode(title: displayTitle, kind: .annotation, annotation: annotation)
                    untaggedNode.children.append(newNode)
                    root.children.append(untaggedNode)
                    addedEntries.append(.init(annotationNode: newNode, tagNode: untaggedNode, tagNodeIsNew: true))
                }
            } else {
                for tag in newTags {
                    if let tagNode = root.children.first(where: { $0.kind == .tag && $0.title == tag }) {
                        if !tagNode.children.contains(where: { $0.annotation?.id == id }) {
                            let newNode = AnnotationNode(title: displayTitle, kind: .annotation, annotation: annotation)
                            let idx = tagNode.children.insertionIndex(for: newNode, using: compareNodes)
                            tagNode.children.insert(newNode, at: idx)
                            addedEntries.append(.init(annotationNode: newNode, tagNode: tagNode, tagNodeIsNew: false))
                        }
                    } else {
                        let tagNode = AnnotationNode(title: tag, kind: .tag)
                        let newNode = AnnotationNode(title: displayTitle, kind: .annotation, annotation: annotation)
                        tagNode.children.append(newNode)

                        let insertIdx = root.children.firstIndex(where: { node in
                            guard node.kind == .tag else { return node.kind == .untagged }
                            return tag.localizedCaseInsensitiveCompare(node.title) == .orderedAscending
                        }) ?? (root.children.firstIndex(where: { $0.kind == .untagged }) ?? root.children.endIndex)

                        root.children.insert(tagNode, at: insertIdx)
                        addedEntries.append(.init(annotationNode: newNode, tagNode: tagNode, tagNodeIsNew: true))
                    }
                }
            }
        }

        if !removedEntries.isEmpty || !addedEntries.isEmpty || !updatedNodes.isEmpty {
            let diff = TagUpdateDiff(
                removed: removedEntries,
                added: addedEntries,
                updated: updatedNodes
            )
            let representativeId = annotations.first?.id ?? -1
            postChangeNotification(type: .updated, annotation: annotations.first, annotationsToSync: annotations, annotationId: representativeId, diff: diff, uploadToCloudKit: uploadToCloudKit)
        }
    }

    // MARK: - Helper TextViewState

    private func pushRecentColor(_ annotation: Annotation) {
        if annotation.type == .highlight,
           let color = PlatformColor(hex: annotation.colorHex)
        {
            TextViewState.shared.pushRecentHighlightColor(color)
        }
    }

    private func populateBookTree(root: AnnotationNode, annotations: [Annotation]) {
        let grouped = Dictionary(grouping: annotations, by: { $0.bkId })

        for bkId in grouped.keys {
            let annsForBook = grouped[bkId] ?? []
            let bookTitle = LibraryDataManager
                .shared.getBook([bkId]).first?.book ?? "Unknown Book" + " (\(bkId))"
            let bookNode = AnnotationNode(title: bookTitle, kind: .book)

            for ann in annsForBook {
                let child = AnnotationNode(
                    title: displayTitle(for: ann),
                    kind: .annotation,
                    annotation: ann
                )
                bookNode.children.append(child)
            }

            root.children.append(bookNode)
        }
    }

    private func populateTagTree(root: AnnotationNode, annotations: [Annotation]) {
        var grouped: [String: [Annotation]] = [:]
        var untagged: [Annotation] = []

        for annotation in annotations {
            let tags = sanitizeTagNames(annotation.tags)
            if tags.isEmpty {
                untagged.append(annotation)
                continue
            }

            for tag in tags {
                grouped[tag, default: []].append(annotation)
            }
        }

        for tag in grouped.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let tagNode = AnnotationNode(title: tag, kind: .tag)
            for annotation in grouped[tag] ?? [] {
                tagNode.children.append(
                    AnnotationNode(
                        title: displayTitle(for: annotation),
                        kind: .annotation,
                        annotation: annotation
                    )
                )
            }
            root.children.append(tagNode)
        }

        if !untagged.isEmpty {
            let untaggedNode = AnnotationNode(title: "Untagged".localized, kind: .untagged)
            for annotation in untagged {
                untaggedNode.children.append(
                    AnnotationNode(
                        title: displayTitle(for: annotation),
                        kind: .annotation,
                        annotation: annotation
                    )
                )
            }
            root.children.append(untaggedNode)
        }
    }

    private func displayTitle(for annotation: Annotation) -> String {
        if let note = annotation.note, !note.isEmpty {
            return note
        }
        return annotation.context
    }

    private func sanitizeTagNames(_ tags: [String]) -> [String] {
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

    private func normalizedTagName(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Semua nama tag unik yang ada di DB, diurutkan case-insensitive.
    func allTagNames() -> [String] {
        if let cached = cacheQueue.sync(execute: { cachedAllTagNames }) {
            return cached
        }
        guard let db else { return [] }
        var names: [String] = []
        let sql = "SELECT \(colTagName) FROM \(tagsTable) ORDER BY \(colTagName) COLLATE NOCASE"
        do {
            names = try db.fetch(query: sql) { $0.string(at: 0) ?? "" }
            cacheQueue.sync { cachedAllTagNames = names }
        } catch {
            print("Failed to fetch all tag names: \(error)")
        }
        return names
    }

    private func fetchTagsForAnnotations(_ annotations: [Annotation]) -> [Int64: [String]] {
        let ids = annotations.compactMap { $0.id }
        guard !ids.isEmpty, let db = db else { return [:] }

        var result: [Int64: [String]] = [:]

        // SQLite has limits on number of parameters, but for our case annotations count is usually reasonable.
        // If it's huge, we might need to chunk it.
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT at.\(colAnnotationTagAnnotationId), t.\(colTagName)
        FROM \(tagsTable) t
        JOIN \(annotationTagsTable) at ON t.\(colTagId) = at.\(colAnnotationTagTagId)
        WHERE at.\(colAnnotationTagAnnotationId) IN (\(placeholders))
        ORDER BY t.\(colTagName) COLLATE NOCASE
        """

        do {
            let rows = try db.fetch(query: sql, parameters: ids) { row -> (Int64, String) in
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

    private func loadTags(for annotationId: Int64) -> [String] {
        if let cached = cacheQueue.sync(execute: { cacheTagsByAnnotationId[annotationId] }) {
            return cached
        }

        guard let db else { return [] }
        var tags: [String] = []
        let sql = """
        SELECT t.\(colTagName)
        FROM \(tagsTable) t
        JOIN \(annotationTagsTable) at ON t.\(colTagId) = at.\(colAnnotationTagTagId)
        WHERE at.\(colAnnotationTagAnnotationId) = ?
        ORDER BY t.\(colTagName) COLLATE NOCASE
        """

        do {
            tags = try db.fetch(query: sql, parameters: [annotationId]) { $0.string(at: 0) ?? "" }
            cacheQueue.sync {
                cacheTagsByAnnotationId[annotationId] = tags
            }
        } catch {
            print("Failed to load tags for annotation: \(error)")
        }
        return tags
    }

    private func replaceTags(_ tags: [String], for annotationId: Int64) throws {
        guard let db else { return }

        try exec("DELETE FROM \(annotationTagsTable) WHERE \(colAnnotationTagAnnotationId) = ?;", parameters: [annotationId])

        for tag in tags {
            let normalized = normalizedTagName(tag)

            var existingTagId: Int64 = -1
            var existingTagName = ""

            let findSql = "SELECT \(colTagId), \(colTagName) FROM \(tagsTable) WHERE \(colTagNormalizedName) = ? LIMIT 1"
            if let row = try db.fetch(query: findSql, parameters: [normalized], mapping: { ($0.int64(at: 0), $0.string(at: 1) ?? "") }).first {
                existingTagId = row.0
                existingTagName = row.1
            }

            let currentTagId: Int64

            if existingTagId != -1 {
                currentTagId = existingTagId
                if existingTagName != tag {
                    let updateSql = "UPDATE \(tagsTable) SET \(colTagName) = ? WHERE \(colTagId) = ?;"
                    try db.execute(query: updateSql, parameters: [tag, currentTagId])
                }
            } else {
                let insertSql = "INSERT INTO \(tagsTable) (\(colTagName), \(colTagNormalizedName)) VALUES (?, ?);"
                try db.execute(query: insertSql, parameters: [tag, normalized])
                currentTagId = db.lastInsertRowId()
            }

            if currentTagId != -1 {
                let insertRelSql = "INSERT OR IGNORE INTO \(annotationTagsTable) (\(colAnnotationTagAnnotationId), \(colAnnotationTagTagId)) VALUES (?, ?);"
                try db.execute(query: insertRelSql, parameters: [annotationId, currentTagId])
            }
        }

        cacheQueue.sync { cachedAllTagNames = nil }
        try deleteUnusedTags()
    }

    private func deleteUnusedTags() throws {
        try exec("""
        DELETE FROM \(tagsTable)
        WHERE \(colTagId) NOT IN (
            SELECT DISTINCT \(colAnnotationTagTagId)
            FROM \(annotationTagsTable)
        )
        """)
    }

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

    // MARK: - CloudKit Sync Apply

    func applyCloudKitChanges(annotationsToSave: [Annotation], recordIdsToDelete: [String]) {
        guard let db else { return }

        var addedAnnotations: [Annotation] = []
        var updatedAnnotations: [Annotation] = []
        var deletedAnnotations: [Annotation] = []

        do {
            try transaction {
                // Process Deletions
                for ckId in recordIdsToDelete {
                    let findSql = "SELECT * FROM \(annotationsTable) WHERE \(colAnnCkRecordId) = ? LIMIT 1"
                    if let row = try db.fetch(query: findSql, parameters: [ckId], mapping: { ($0.int64(at: 0), self.makeAnnotation(from: $0)) }).first {
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
                    if let row = try db.fetch(query: findSql, parameters: [ckId], mapping: { ($0.int64(at: 0), $0.int64(at: 1)) }).first {
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

                            try db.execute(query: updateSql, parameters: params)
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

                        try db.execute(query: insertSql, parameters: params)
                        let rowId = db.lastInsertRowId()

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
                cacheQueue.sync {
                    cachedAllTagNames = nil

                    for ann in deletedAnnotations {
                        guard let id = ann.id else { continue }
                        cacheById.removeValue(forKey: id)
                        cacheTagsByAnnotationId.removeValue(forKey: id)
                    }

                    for ann in addedAnnotations {
                        guard let id = ann.id else { continue }
                        cacheById[id] = ann
                        cacheTagsByAnnotationId[id] = ann.tags
                    }

                    for ann in updatedAnnotations {
                        guard let id = ann.id else { continue }
                        cacheById[id] = ann
                        cacheTagsByAnnotationId[id] = ann.tags
                    }

                    // Per-page and per-book caches must not be rebuilt from a partial CloudKit delta,
                    // or reader views can observe only the changed annotations for a page.
                    for key in affectedContentKeys {
                        cacheByContent.removeValue(forKey: key)
                    }
                    for bkId in affectedBookIds {
                        cacheByBook.removeValue(forKey: bkId)
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
