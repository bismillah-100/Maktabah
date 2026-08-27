//
//  ResultsHandler.swift
//  maktab
//
//  Created by MacBook on 05/12/25.
//

import Foundation
import SQLite3

extension Notification.Name {
    static let savedResultsTreeDidUpdate = Notification.Name("savedResultsTreeDidUpdate")
}

// MARK: - Sync Models

struct SyncFolder {
    var id: Int64?
    var name: String
    var parent: Int64?
    var ckRecordId: String?
    var lastModified: Int64?
    var parentCkRecordId: String?
}

struct SyncResult {
    var id: Int64?
    var folderId: Int64?
    var name: String
    var query: String
    var searchMode: Int
    var nearDistance: Int
    var archive: Int
    var bkId: Int
    var contentId: String
    var ckRecordId: String?
    var lastModified: Int64?
    var folderCkRecordId: String?
}

struct ExistingFolderInfo {
    let id: Int64
    let lastModified: Int64
    let parentId: Int64?
}

struct ExistingResultInfo {
    let id: Int64
    let lastModified: Int64
    let folderId: Int64?
}

struct ResultsSyncContext {
    let folderMap: [String: Int64]
    let resMap: [String: ExistingResultInfo]
    let conflictMap: [String: (Int64, Int64)]
}

struct ConflictResultRow {
    let id: Int64
    let lastModified: Int64
    let folderId: Int64?
    let name: String
    let bkId: Int
}

struct ResultSaveOptions {
    var folderId: Int64?
    var query: String
    var name: String
    var searchMode: Int = 0
    var nearDistance: Int = 10
}

class ResultsHandler: SyncPendingManaging {
    private(set) var db: SQLiteDatabase?
    var syncPendingStore: SyncPendingStore?
    static var shared: ResultsHandler = .init()

    let foldersTable = "folders"
    let colId = "id"
    let colName = "name"
    let colParent = "parent"
    let colCkRecordId = "ckRecordId"
    let colLastModified = "lastModified"
    let colParentCkRecordId = "parentCkRecordId"

    let resultsTable = "results"
    let colFolderId = "folder_id"
    let colQuery = "query"
    let colArchive = "archives"
    let colBkId = "bkId"
    let colContentId = "contentId"
    let colResCkRecordId = "ckRecordId"
    let colResLastModified = "lastModified"
    let colFolderCkRecordId = "folder_ckrecord_id"
    let colSearchMode = "search_mode"
    let colNearDistance = "near_distance"

    var allFoldersColumns: String {
        "\(colId), \(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId)"
    }

    var allResultsColumns: String {
        "\(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance)"
    }

    var insertFolderSQL: String {
        "INSERT INTO \(foldersTable) (\(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId)) VALUES (?, ?, ?, ?, ?);"
    }

    var insertResultSQL: String {
        """
        INSERT INTO \(resultsTable) (
            \(colFolderId), \(colName), \(colQuery), \(colArchive),
            \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified),
            \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance)
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
    }

    // MARK: - Centralized Query & Reload Helpers

    func fetchSyncFolders(whereClause: String = "", parameters: [Any] = []) throws -> [SyncFolder] {
        guard let db else { return [] }
        let sql = "SELECT \(allFoldersColumns) FROM \(foldersTable) \(whereClause)"
        return try db.fetch(query: sql, parameters: parameters) { self.makeSyncFolder(from: $0) }
    }

    func fetchSyncResults(whereClause: String = "", parameters: [Any] = []) throws -> [SyncResult] {
        guard let db else { return [] }
        let sql = "SELECT \(allResultsColumns) FROM \(resultsTable) \(whereClause)"
        return try db.fetch(query: sql, parameters: parameters) { self.makeSyncResult(from: $0) }
    }

    func reloadSyncFolder(id: Int64) throws -> SyncFolder? {
        try fetchSyncFolders(whereClause: "WHERE \(colId) = ? LIMIT 1", parameters: [id]).first
    }

    func reloadSyncResult(id: Int64) throws -> SyncResult? {
        try fetchSyncResults(whereClause: "WHERE \(colId) = ? LIMIT 1", parameters: [id]).first
    }

    func findFolderCkId(id: Int64) throws -> String? {
        guard let db else { return nil }
        let sql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
        return try db.fetch(query: sql, parameters: [id]) { $0.string(at: 0) }.compactMap { $0 }.first
    }

    private init() {}

    func disconnect() {
        db?.checkpoint()
        db = nil
        syncPendingStore = nil
    }

    func setupResultDatabase(at folderURL: URL?) throws {
        guard let folderURL else { throw NSError(domain: "maktabah", code: 404) }
        let url = folderURL.appendingPathComponent("SearchResults.sqlite")

        let fm = FileManager.default
        let isNewDatabase = !fm.fileExists(atPath: url.path)

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        do {
            let database = try SQLiteDatabase(path: url.path, flags: flags)
            database.enableWALMode()
            database.checkpoint() // Ensure WAL is committed and truncated
            db = database
            syncPendingStore = SyncPendingStore(database: database)
        } catch {
            throw NSError(domain: "ResultsHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to open SearchResults database: \(error.localizedDescription)"])
        }

        createTables()
        resolveOrphanFolders()
        resolveOrphanResults()

        if isNewDatabase {
            CloudKitSyncManager.shared.resetChangeToken()
        }
    }

    func createTables() {
        guard db != nil else {
            ReusableFunc.showAlert(title: "Database not initialized", message: "")
            return
        }

        do {
            try createBaseTablesAndIndices()
            try migrateTableColumnsIfNeeded()
            try backfillResultsCloudKitFieldsIfNeeded()
        } catch {
            #if DEBUG
            print("Error creating tables: \(error)")
            #endif
        }

        createUniqueIndex()
    }

    private func createBaseTablesAndIndices() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS \(foldersTable) (
            \(colId) INTEGER PRIMARY KEY AUTOINCREMENT,
            \(colName) TEXT,
            \(colParent) INTEGER,
            \(colCkRecordId) TEXT,
            \(colLastModified) INTEGER,
            \(colParentCkRecordId) TEXT,
            UNIQUE(\(colName), \(colParent))
        );
        """)

        try exec("""
        CREATE TABLE IF NOT EXISTS \(resultsTable) (
            \(colId) INTEGER PRIMARY KEY AUTOINCREMENT,
            \(colFolderId) INTEGER,
            \(colName) TEXT,
            \(colQuery) TEXT,
            \(colArchive) INTEGER,
            \(colBkId) INTEGER,
            \(colContentId) TEXT,
            \(colResCkRecordId) TEXT UNIQUE,
            \(colResLastModified) INTEGER,
            \(colFolderCkRecordId) TEXT,
            \(colSearchMode) INTEGER DEFAULT 0,
            \(colNearDistance) INTEGER DEFAULT 10,
            FOREIGN KEY(\(colFolderId)) REFERENCES \(foldersTable)(\(colId)) ON DELETE CASCADE
        );
        """)

        try syncPendingStore?.createTable()

        try exec("CREATE INDEX IF NOT EXISTS idx_folders_ck_record_id ON \(foldersTable) (\(colCkRecordId));")
        try exec("CREATE INDEX IF NOT EXISTS idx_results_ck_record_id ON \(resultsTable) (\(colResCkRecordId));")
    }

    private func migrateTableColumnsIfNeeded() throws {
        let folderCols = try listTableColumns(tableName: foldersTable)
        if !folderCols.contains(colCkRecordId) {
            try exec("ALTER TABLE \(foldersTable) ADD COLUMN \(colCkRecordId) TEXT;")
        }
        if !folderCols.contains(colLastModified) {
            try exec("ALTER TABLE \(foldersTable) ADD COLUMN \(colLastModified) INTEGER;")
        }
        if !folderCols.contains(colParentCkRecordId) {
            try exec("ALTER TABLE \(foldersTable) ADD COLUMN \(colParentCkRecordId) TEXT;")
        }

        let resultCols = try listTableColumns(tableName: resultsTable)
        if !resultCols.contains(colResCkRecordId) {
            try exec("ALTER TABLE \(resultsTable) ADD COLUMN \(colResCkRecordId) TEXT;")
        }
        if !resultCols.contains(colResLastModified) {
            try exec("ALTER TABLE \(resultsTable) ADD COLUMN \(colResLastModified) INTEGER;")
        }
        if resultCols.contains("folderCkRecordId"), !resultCols.contains(colFolderCkRecordId) {
            try exec("ALTER TABLE \(resultsTable) RENAME COLUMN folderCkRecordId TO \(colFolderCkRecordId);")
        } else if !resultCols.contains(colFolderCkRecordId) {
            try exec("ALTER TABLE \(resultsTable) ADD COLUMN \(colFolderCkRecordId) TEXT;")
        }
        if !resultCols.contains(colSearchMode) {
            try exec("ALTER TABLE \(resultsTable) ADD COLUMN \(colSearchMode) INTEGER DEFAULT 0;")
        }
        if !resultCols.contains(colNearDistance) {
            try exec("ALTER TABLE \(resultsTable) ADD COLUMN \(colNearDistance) INTEGER DEFAULT 10;")
        }
    }

    // MARK: - Native SQLite3 Helpers

    func exec(_ sql: String, parameters: [Any] = []) throws {
        guard let db else { return }
        try db.execute(query: sql, parameters: parameters)
    }

    func transaction(_ block: () throws -> Void) throws {
        guard let db else { return }
        try db.transaction(block)
    }

    private func listTableColumns(tableName: String) throws -> [String] {
        guard let db else { return [] }
        return db.tableColumns(tableName: tableName)
    }

    func nukeDatabase() {
        do {
            try transaction {
                try exec("DELETE FROM \(resultsTable);")
                try exec("DELETE FROM \(foldersTable);")
            }
            #if DEBUG
            print("ResultsHandler: Local database purged.")
            #endif
        } catch {
            print("ResultsHandler: Failed to purge database - \(error)")
        }
    }

    func makeSyncFolder(from row: SQLiteRow) -> SyncFolder {
        SyncFolder(
            id: row.int64(at: 0),
            name: row.string(at: 1) ?? "",
            parent: !row.isNull(at: 2) ? row.int64(at: 2) : nil,
            ckRecordId: row.string(at: 3),
            lastModified: !row.isNull(at: 4) ? row.int64(at: 4) : nil,
            parentCkRecordId: row.string(at: 5)
        )
    }

    func makeSyncResult(from row: SQLiteRow) -> SyncResult {
        SyncResult(
            id: row.int64(at: 0),
            folderId: !row.isNull(at: 1) ? row.int64(at: 1) : nil,
            name: row.string(at: 2) ?? "",
            query: row.string(at: 3) ?? "",
            searchMode: row.int(at: 10),
            nearDistance: row.int(at: 11),
            archive: row.int(at: 4),
            bkId: row.int(at: 5),
            contentId: row.string(at: 6) ?? "",
            ckRecordId: row.string(at: 7),
            lastModified: !row.isNull(at: 8) ? row.int64(at: 8) : nil,
            folderCkRecordId: row.string(at: 9)
        )
    }

    func createUniqueIndex() {
        do {
            try exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_parent_name ON folders (COALESCE(parent, 0), name)")
            try exec("DROP INDEX IF EXISTS idx_results_folder_name")
            try exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_results_folder_name_bk ON results (COALESCE(folder_id, 0), name, bkId)")
        } catch {
            #if DEBUG
            print("Create index error:", error)
            #endif
        }
    }
}
