//
//  AnnMgr+DB.swift
//  Maktabah
//

import Foundation

extension AnnotationManager {
    // MARK: - Setup

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

    // MARK: - Schema Setup

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

        try exec("CREATE INDEX IF NOT EXISTS idx_sync_pending_ck_record_id ON sync_pending (ck_record_id);")
        try exec("CREATE INDEX IF NOT EXISTS idx_sync_pending_op_queued ON sync_pending (operation, queued_at);")
        try exec("CREATE INDEX IF NOT EXISTS idx_ann_ck_record_id ON \(annotationsTable) (\(colAnnCkRecordId));")

        try backfillCloudKitFieldsIfNeeded { backfilled in
            if !backfilled.isEmpty {
                CloudKitSyncManager.shared.upload(annotations: backfilled, debounce: false)
            }
        }
    }

    func backfillCloudKitFieldsIfNeeded(completion: (([Annotation]) -> Void)? = nil) throws {
        guard let _db else {
            completion?([])
            return
        }

        let sql = "SELECT \(colAnnId), \(colAnnBkId), \(colAnnContentId), \(colAnnStart), \(colAnnCreatedAt) FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IS NULL"
        var backfilledAnnotations: [Annotation] = []

        try transaction {
            let results = try _db.fetch(query: sql) { row -> (Int64, Int, Int, Int, Int64) in
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

    // MARK: - Connect / Disconnect

    func disconnect() {
        _db?.checkpoint()
        _db = nil
    }

    func connect() {
        if let dbURL {
            do {
                _db = try SQLiteDatabase(path: dbURL.path)
                enableWALMode()
            } catch {
                ReusableFunc.showAlert(title: "Error", message: "Failed to open annotations database: \(error.localizedDescription)")
            }
        }
    }

    private func enableWALMode() {
        guard let _db else { return }
        do {
            let mode = try _db.fetch(query: "PRAGMA journal_mode = WAL;") { row in
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
        let sql = "PRAGMA table_info(\(tableName));"
        return try _db.fetch(query: sql) { $0.string(at: 1) ?? "" }
    }
}
