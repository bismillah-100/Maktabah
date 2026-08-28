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
        try createTagsTablesIfNeeded()
        try createAnnotationsTableAndSchemaIfNeeded()
        try createSyncPendingTableIfNeeded()

        try backfillCloudKitFieldsIfNeeded { backfilled in
            if !backfilled.isEmpty {
                CloudKitSyncManager.shared.upload(annotations: backfilled, debounce: false)
            }
        }
    }

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
        try exec("DROP INDEX IF EXISTS idx_ann_unique_pos;")

        // Deduplicate any duplicate ckRecordIds, keeping the lowest id
        try exec("""
        DELETE FROM \(annotationsTable)
        WHERE \(colAnnCkRecordId) IS NOT NULL
          AND \(colAnnId) NOT IN (
            SELECT MIN(\(colAnnId))
            FROM \(annotationsTable)
            WHERE \(colAnnCkRecordId) IS NOT NULL
            GROUP BY \(colAnnCkRecordId)
          );
        """)

        // Clean up any orphaned tags for deleted duplicates
        try exec("""
        DELETE FROM \(annotationTagsTable)
        WHERE \(colAnnotationTagAnnotationId) NOT IN (
            SELECT \(colAnnId) FROM \(annotationsTable)
        );
        """)

        try exec("DROP INDEX IF EXISTS idx_ann_ck_record_id;")
        try exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_ann_ck_record_id ON \(annotationsTable) (\(colAnnCkRecordId));")
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

    func backfillCloudKitFieldsIfNeeded(completion: (([Annotation]) -> Void)? = nil) throws {
        guard let _db else {
            completion?([])
            return
        }

        let sql = "SELECT \(colAnnId), \(colAnnBkId), \(colAnnContentId), \(colAnnStart), \(colAnnCreatedAt) FROM \(annotationsTable) WHERE \(colAnnCkRecordId) IS NULL"
        var backfilledAnnotations: [Annotation] = []

        try transaction {
            struct BackfillAnnotationRow {
                let id: Int64
                let bkId: Int
                let contentId: Int
                let start: Int
                let createdAt: Int64
            }

            let results = try _db.fetch(query: sql) { row -> BackfillAnnotationRow in
                BackfillAnnotationRow(
                    id: row.int64(at: 0),
                    bkId: row.int(at: 1),
                    contentId: row.int(at: 2),
                    start: row.int(at: 3),
                    createdAt: row.int64(at: 4)
                )
            }

            for res in results {
                let id = res.id
                let bkId = res.bkId
                let contentId = res.contentId
                let start = res.start
                let createdAt = res.createdAt

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
        syncPendingStore = nil
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
}
