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

class ResultsHandler {
    private(set) var db: SQLiteDatabase?
    static var shared: ResultsHandler = .init()

    private let foldersTable = "folders"
    private let colId = "id"
    private let colName = "name"
    private let colParent = "parent"
    private let colCkRecordId = "ckRecordId"
    private let colLastModified = "lastModified"
    private let colParentCkRecordId = "parentCkRecordId"

    private let resultsTable = "results"
    private let colFolderId = "folder_id"
    private let colQuery = "query"
    private let colArchive = "archives"
    private let colBkId = "bkId"
    private let colContentId = "contentId"
    private let colResCkRecordId = "ckRecordId"
    private let colResLastModified = "lastModified"
    private let colFolderCkRecordId = "folder_ckrecord_id"
    private let colSearchMode = "search_mode"
    private let colNearDistance = "near_distance"

    func migrateBookId(from oldId: Int, to newId: Int) throws -> [SyncResult] {
        guard let db else { return [] }
        let now = Int64(Date().timeIntervalSince1970)

        let sql = "UPDATE \(resultsTable) SET \(colBkId) = ?, \(colResLastModified) = ? WHERE \(colBkId) = ?"
        let fetchSql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colBkId) = ?"

        var updatedResults: [SyncResult] = []
        try transaction {
            try exec(sql, parameters: [newId, now, oldId])

            // Fetch updated results to upload
            updatedResults = try db.fetch(query: fetchSql, parameters: [newId]) { self.makeSyncResult(from: $0) }

            for res in updatedResults {
                if let ckId = res.ckRecordId {
                    try addPendingSync(ckRecordId: ckId, operation: "upload")
                }
            }
        }
        return updatedResults
    }

    func disconnect() {
        db?.checkpoint()
        db = nil
    }

    private init() {}

    func setupResultDatabase(at folderURL: URL?) throws {
        guard let folderURL else { throw NSError(domain: "maktabah", code: 404) }
        let url = folderURL.appendingPathComponent("SearchResults.sqlite")

        let fm = FileManager.default
        let isNewDatabase = !fm.fileExists(atPath: url.path)

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        do {
            db = try SQLiteDatabase(path: url.path, flags: flags)
            enableWALMode()
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

    private func enableWALMode() {
        guard let db else { return }
        do {
            let mode = try db.fetch(query: "PRAGMA journal_mode = WAL;") { row in
                row.string(at: 0) ?? ""
            }.first

            #if DEBUG
            if mode?.lowercased() != "wal" {
                let currentMode = mode ?? "unknown"
                print("ResultsHandler: failed to enable WAL mode, current mode: \(currentMode)")
            }
            #endif
        } catch {
            #if DEBUG
            print("ResultsHandler: error enabling WAL mode: \(error)")
            #endif
        }
    }

    func createTables() {
        guard db != nil else {
            ReusableFunc.showAlert(title: "Database not initialized", message: "")
            return
        }

        do {
            // MARK: - folders table

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

            // MARK: - results table

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

            try exec("""
            CREATE TABLE IF NOT EXISTS sync_pending (
                ck_record_id TEXT PRIMARY KEY,
                operation TEXT NOT NULL CHECK(operation IN ('upload', 'delete')),
                queued_at INTEGER NOT NULL
            );
            """)

            try exec("CREATE INDEX IF NOT EXISTS idx_sync_pending_ck_record_id ON sync_pending (ck_record_id);")
            try exec("CREATE INDEX IF NOT EXISTS idx_sync_pending_op_queued ON sync_pending (operation, queued_at);")
            try exec("CREATE INDEX IF NOT EXISTS idx_folders_ck_record_id ON \(foldersTable) (\(colCkRecordId));")
            try exec("CREATE INDEX IF NOT EXISTS idx_results_ck_record_id ON \(resultsTable) (\(colResCkRecordId));")

            // Migration for existing databases
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
            if resultCols.contains("folderCkRecordId") && !resultCols.contains(colFolderCkRecordId) {
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

            try backfillResultsCloudKitFieldsIfNeeded()

        } catch {
            #if DEBUG
            print("Error creating tables: \(error)")
            #endif
        }

        createUniqueIndex()
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
        let sql = "PRAGMA table_info('\(tableName)');"
        return try db.fetch(query: sql) { row in
            row.string(at: 1) ?? ""
        }
    }

    func backfillResultsCloudKitFieldsIfNeeded(uploadIfNeeded: Bool = true) throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)

        // 1. Backfill Folders (Order by parent to ensure top-down backfill)
        var foldersToUpload: [SyncFolder] = []

        try transaction {
            let sql = "SELECT \(colId), \(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId) FROM \(foldersTable) WHERE \(colCkRecordId) IS NULL ORDER BY \(colParent) ASC"

            let folders = try db.fetch(query: sql) { row -> (Int64, String, Int64?) in
                let fId = row.int64(at: 0)
                let fName = row.string(at: 1) ?? ""
                let fParent = !row.isNull(at: 2) ? row.int64(at: 2) : nil
                return (fId, fName, fParent)
            }

            for folder in folders {
                let fId = folder.0
                let fName = folder.1
                let fParent = folder.2

                var parentIdentifier = "root"
                if let pid = fParent {
                    let findParentSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
                    if let parentCKId = try db.fetch(query: findParentSql, parameters: [pid], mapping: { $0.string(at: 0) }).first {
                        parentIdentifier = parentCKId ?? ""
                    } else {
                        parentIdentifier = "orphan_\(pid)"
                    }
                }

                let detId = "folder_\(fName)_\(parentIdentifier)"
                let parentCkRecordIdValue: Any = parentIdentifier == "root" ? NSNull() : parentIdentifier

                try exec("UPDATE \(foldersTable) SET \(colCkRecordId) = ?, \(colLastModified) = ?, \(colParentCkRecordId) = ? WHERE \(colId) = ?;", parameters: [detId, now, parentCkRecordIdValue, fId])

                // Reload to upload
                let reloadSql = "SELECT \(colId), \(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
                if let reloaded = try db.fetch(query: reloadSql, parameters: [fId], mapping: { self.makeSyncFolder(from: $0) }).first {
                    foldersToUpload.append(reloaded)
                }
            }
        }

        // 2. Backfill Results
        var resultsToUpload: [SyncResult] = []

        try transaction {
            let sql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colResCkRecordId) IS NULL"

            let results = try db.fetch(query: sql) { row -> (Int64, Int64?, String, Int, Int) in
                let rId = row.int64(at: 0)
                let rFolderId = !row.isNull(at: 1) ? row.int64(at: 1) : nil
                let rName = row.string(at: 2) ?? ""
                let rBkId = row.int(at: 5)
                let rArchive = row.int(at: 4)
                return (rId, rFolderId, rName, rBkId, rArchive)
            }

            for res in results {
                let rId = res.0
                let rFolderId = res.1
                let rName = res.2
                let rBkId = res.3
                let rArchive = res.4

                var folderIdentifier = "root"
                if let fid = rFolderId {
                    let findFolderSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
                    if let folderCKId = try db.fetch(query: findFolderSql, parameters: [fid], mapping: { $0.string(at: 0) }).compactMap({ $0 }).first {
                        folderIdentifier = folderCKId
                    } else {
                        folderIdentifier = "orphan_\(fid)"
                    }
                }

                let detId = "result_\(folderIdentifier)_\(rName)_\(rBkId)_\(rArchive)"
                let folderCkIdValue: Any = folderIdentifier == "root" ? NSNull() : folderIdentifier

                try exec("UPDATE \(resultsTable) SET \(colResCkRecordId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ? WHERE \(colId) = ?;", parameters: [detId, now, folderCkIdValue, rId])

                let reloadSql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colId) = ? LIMIT 1"
                if let reloaded = try db.fetch(query: reloadSql, parameters: [rId], mapping: { self.makeSyncResult(from: $0) }).first {
                    resultsToUpload.append(reloaded)
                }
            }
        }

        if !foldersToUpload.isEmpty || !resultsToUpload.isEmpty {
            guard uploadIfNeeded else { return }
            DispatchQueue.global(qos: .background).async {
                CloudKitSyncManager.shared.uploadResultsData(folders: foldersToUpload, results: resultsToUpload, trackPending: false)
            }
        }
    }

    // MARK: - Sync Pending Helpers

    func addPendingSync(ckRecordId: String, operation: String) throws {
        guard let db else { return }
        if operation == "upload" {
            let checkSql = "SELECT COUNT(*) FROM sync_pending WHERE ck_record_id = ? AND operation = 'delete';"
            if let count = try db.fetch(query: checkSql, parameters: [ckRecordId], mapping: { $0.int64(at: 0) }).first, count > 0 {
                return // Delete wins
            }
        } else if operation == "delete" {
            let delSql = "DELETE FROM sync_pending WHERE ck_record_id = ? AND operation = 'upload';"
            try db.execute(query: delSql, parameters: [ckRecordId])
        }
        let now = Int64(Date().timeIntervalSince1970)
        let sql = "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES (?, ?, ?);"
        try db.execute(query: sql, parameters: [ckRecordId, operation, now])
    }

    func removePendingSync(ckRecordIds: [String]) {
        guard let db else { return }
        let placeholders = String(repeating: "?,", count: ckRecordIds.count).dropLast()
        let sql = "DELETE FROM sync_pending WHERE ck_record_id IN (\(placeholders));"
        try? db.execute(query: sql, parameters: ckRecordIds)
    }

    func fetchPendingSync(operation: String) -> [String] {
        guard let db else { return [] }
        let sql = "SELECT ck_record_id FROM sync_pending WHERE operation = ? ORDER BY queued_at ASC;"
        return (try? db.fetch(query: sql, parameters: [operation]) { $0.string(at: 0) ?? "" }) ?? []
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

    private func makeSyncFolder(from row: SQLiteRow) -> SyncFolder {
        SyncFolder(
            id: row.int64(at: 0),
            name: row.string(at: 1) ?? "",
            parent: !row.isNull(at: 2) ? row.int64(at: 2) : nil,
            ckRecordId: row.string(at: 3),
            lastModified: !row.isNull(at: 4) ? row.int64(at: 4) : nil,
            parentCkRecordId: row.string(at: 5)
        )
    }

    private func makeSyncResult(from row: SQLiteRow) -> SyncResult {
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
            try exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_results_folder_name ON results (COALESCE(folder_id, 0), name)")
            // optional: mencegah duplikat konten yang sama di folder yang sama
            try exec("DROP INDEX IF EXISTS idx_results_folder_name")
            try exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_results_folder_name_bk ON results (COALESCE(folder_id, 0), name, bkId)")
        } catch {
            #if DEBUG
            print("Create index error:", error)
            #endif
        }
    }
}

extension ResultsHandler {
    func insertRootFolder(name: String) throws -> Int64? {
        guard let db else { return nil }
        let cId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)

        let sql = "INSERT INTO \(foldersTable) (\(colName), \(colParent), \(colCkRecordId), \(colLastModified)) VALUES (?, NULL, ?, ?);"
        var rowId: Int64 = -1

        try transaction {
            try exec(sql, parameters: [name, cId, now])
            rowId = db.lastInsertRowId()
            try self.addPendingSync(ckRecordId: cId, operation: "upload")
        }

        let reloadSql = "SELECT \(colId), \(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
        if rowId != -1, let reloaded = try db.fetch(query: reloadSql, parameters: [rowId], mapping: { self.makeSyncFolder(from: $0) }).first {
            CloudKitSyncManager.shared.uploadResultsData(folders: [reloaded], results: [], trackPending: false)
        }

        return rowId != -1 ? rowId : nil
    }

    func insertSubFolder(parentNode: FolderNode, name: String) throws -> Int64? {
        guard let db else { return nil }
        let cId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)

        // Fetch parent ckRecordId
        var pCkId: String? = nil
        let findParentSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
        if let parentCkRecordId = try db.fetch(query: findParentSql, parameters: [parentNode.id], mapping: { $0.string(at: 0) }).compactMap({ $0 }).first {
            pCkId = parentCkRecordId
        }

        let sql = "INSERT INTO \(foldersTable) (\(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId)) VALUES (?, ?, ?, ?, ?);"
        var params: [Any] = [name, parentNode.id, cId, now]
        if let pCkId {
            params.append(pCkId)
        } else {
            params.append(NSNull())
        }

        var rowId: Int64 = -1
        try transaction {
            try exec(sql, parameters: params)
            rowId = db.lastInsertRowId()
            try self.addPendingSync(ckRecordId: cId, operation: "upload")
        }

        let reloadSql = "SELECT \(colId), \(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
        if rowId != -1, let reloaded = try db.fetch(query: reloadSql, parameters: [rowId], mapping: { self.makeSyncFolder(from: $0) }).first {
            CloudKitSyncManager.shared.uploadResultsData(folders: [reloaded], results: [], trackPending: false)
        }

        return rowId != -1 ? rowId : nil
    }

    func fetchFolderTree() -> [FolderNode] {
        guard let db else { return [] }
        var nodes: [Int64: FolderNode] = [:]
        var roots: [FolderNode] = []

        let sql = "SELECT \(colId), \(colName), \(colParent), \(colLastModified), \(colParentCkRecordId) FROM \(foldersTable)"
        do {
            let rows = try db.fetch(query: sql) { row -> (id: Int64, name: String, parent: Int64?, lastModified: Int64?, parentCkId: String?) in
                let fid = row.int64(at: 0)
                let fname = row.string(at: 1) ?? ""
                let fparent = !row.isNull(at: 2) ? row.int64(at: 2) : nil
                let flastMod = !row.isNull(at: 3) ? row.int64(at: 3) : nil
                let fparentCkId = row.string(at: 4)
                return (id: fid, name: fname, parent: fparent, lastModified: flastMod, parentCkId: fparentCkId)
            }

            for row in rows {
                let node = FolderNode(id: row.id, name: row.name, lastModified: row.lastModified)
                nodes[row.id] = node
            }

            for row in rows {
                if let parentId = row.parent, let parentNode = nodes[parentId] {
                    parentNode.children.append(nodes[row.id]!)
                } else if row.parentCkId == nil {
                    // Hide orphan folders from root until their parent arrives
                    roots.append(nodes[row.id]!)
                }
            }
        } catch {
            print("Failed to fetch folder tree: \(error)")
        }

        return roots
    }

    func deleteFolder(_ folderId: Int64) {
        guard let db else { return }
        do {
            let allFolderIds = getAllDescendantIds(of: folderId)
            var ckIdsToDelete: [String] = []

            for fId in allFolderIds {
                let findFolderSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
                if let ckId = try db.fetch(query: findFolderSql, parameters: [fId], mapping: { $0.string(at: 0) }).compactMap({ $0 }).first {
                    ckIdsToDelete.append(ckId)
                }

                let findResSql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) = ?"
                let resCkIds = try db.fetch(query: findResSql, parameters: [fId]) { $0.string(at: 0) }
                ckIdsToDelete.append(contentsOf: resCkIds.compactMap { $0 })
            }

            try transaction {
                for id in allFolderIds {
                    try exec("DELETE FROM \(resultsTable) WHERE \(colFolderId) = ?;", parameters: [id])
                }
                for id in allFolderIds.reversed() {
                    try exec("DELETE FROM \(foldersTable) WHERE \(colId) = ?;", parameters: [id])
                }
                for id in ckIdsToDelete {
                    try self.addPendingSync(ckRecordId: id, operation: "delete")
                }
            }

            if !ckIdsToDelete.isEmpty {
                CloudKitSyncManager.shared.delete(ckRecordIds: ckIdsToDelete, target: .result, trackPending: false)
            }
        } catch {
            print("❌ Delete transaction failed:", error)
        }
    }

    func deleteResult(_ folderId: Int64?, name: String) {
        guard let db else { return }
        var ckIds: [String] = []
        let sql: String
        var params: [Any] = []

        if let fid = folderId {
            sql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?"
            params = [fid, name]
        } else {
            sql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?"
            params = [name]
        }

        do {
            ckIds = try db.fetch(query: sql, parameters: params, mapping: { $0.string(at: 0) ?? "" })

            if let fid = folderId {
                try exec("DELETE FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?;", parameters: [fid, name])
            } else {
                try exec("DELETE FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?;", parameters: [name])
            }
            for id in ckIds {
                try self.addPendingSync(ckRecordId: id, operation: "delete")
            }

            if !ckIds.isEmpty {
                CloudKitSyncManager.shared.delete(ckRecordIds: ckIds, target: .result, trackPending: false)
            }
        } catch {
            print(error.localizedDescription)
        }
    }

    func updateParent(of id: Int64, to newParentId: Int64?) throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)

        var reloaded: SyncFolder?
        try transaction {
            var pCkId: String? = nil
            if let pid = newParentId {
                let findParentSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
                if let fetchedCkId = try db.fetch(query: findParentSql, parameters: [pid], mapping: { $0.string(at: 0) }).compactMap({ $0 }).first {
                    pCkId = fetchedCkId
                }
            }

            let updateSql = "UPDATE \(foldersTable) SET \(colParent) = ?, \(colLastModified) = ?, \(colParentCkRecordId) = ? WHERE \(colId) = ?;"
            let params: [Any] = [newParentId ?? NSNull(), now, pCkId ?? NSNull(), id]
            try exec(updateSql, parameters: params)

            let reloadSql = "SELECT \(colId), \(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
            if let fetched = try db.fetch(query: reloadSql, parameters: [id], mapping: { self.makeSyncFolder(from: $0) }).first {
                reloaded = fetched
                if let ckId = fetched.ckRecordId {
                    try self.addPendingSync(ckRecordId: ckId, operation: "upload")
                }
            }
        }

        if let folderToUpload = reloaded {
            CloudKitSyncManager.shared.uploadResultsData(folders: [folderToUpload], results: [], trackPending: false)
        }
    }

    func updateResultParent(newParentId: Int64?, oldParent: Int64?, name: String) throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)

        var fCkId: String? = nil
        if let fid = newParentId {
            let findFolderSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
            if let fetchedCkId = try db.fetch(query: findFolderSql, parameters: [fid], mapping: { $0.string(at: 0) }).compactMap({ $0 }).first {
                fCkId = fetchedCkId
            }
        }

        let updateSql: String
        var params: [Any] = [newParentId ?? NSNull(), now, fCkId ?? NSNull()]

        if let old = oldParent {
            updateSql = "UPDATE \(resultsTable) SET \(colFolderId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ? WHERE \(colFolderId) = ? AND \(colName) = ?;"
            params.append(contentsOf: [old, name])
        } else {
            updateSql = "UPDATE \(resultsTable) SET \(colFolderId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ? WHERE \(colFolderId) IS NULL AND \(colName) = ?;"
            params.append(name)
        }

        var ckIds: [String] = []
        try transaction {
            let findCkIdSql: String
            let findCkIdParams: [Any]
            if let old = oldParent {
                findCkIdSql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?"
                findCkIdParams = [old, name]
            } else {
                findCkIdSql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?"
                findCkIdParams = [name]
            }
            ckIds = try db.fetch(query: findCkIdSql, parameters: findCkIdParams) { $0.string(at: 0) }.compactMap { $0 }

            try exec(updateSql, parameters: params)
            for ckId in ckIds {
                try self.addPendingSync(ckRecordId: ckId, operation: "upload")
            }
        }

        let reloadSql: String
        var reloadParams: [Any] = []
        if let nid = newParentId {
            reloadSql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?"
            reloadParams = [nid, name]
        } else {
            reloadSql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?"
            reloadParams = [name]
        }

        let updated = try db.fetch(query: reloadSql, parameters: reloadParams) { self.makeSyncResult(from: $0) }
        if !updated.isEmpty {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: updated, trackPending: false)
        }
    }
}

extension ResultsHandler {
    func insertResult(_ archive: Int, bkId: Int, contentId: String, folderId: Int64?, query: String, searchMode: Int = 0, nearDistance: Int = 10, name: String) throws {
        guard let db else { return }
        let cId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)

        var fCkId: String? = nil
        if let fid = folderId {
            let findFolderSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
            if let fetchedCkId = try db.fetch(query: findFolderSql, parameters: [fid], mapping: { $0.string(at: 0) }).compactMap({ $0 }).first {
                fCkId = fetchedCkId
            }
        }

        let sql = """
        INSERT INTO \(resultsTable) (
            \(colFolderId), \(colName), \(colQuery), \(colArchive),
            \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified),
            \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance)
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        let params: [Any] = [
            folderId ?? NSNull(),
            name,
            query,
            archive,
            bkId,
            contentId,
            cId,
            now,
            fCkId ?? NSNull(),
            searchMode,
            nearDistance,
        ]

        var rowId: Int64 = -1
        try transaction {
            try exec(sql, parameters: params)
            rowId = db.lastInsertRowId()
            try self.addPendingSync(ckRecordId: cId, operation: "upload")
        }

        let reloadSql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colId) = ? LIMIT 1"
        if rowId != -1, let reloaded = try db.fetch(query: reloadSql, parameters: [rowId], mapping: { self.makeSyncResult(from: $0) }).first {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: [reloaded], trackPending: false)
        }
    }

    func insertResults(
        _ groupedResults: [String: GroupedResult],
        folderId: Int64?,
        query: String,
        searchMode: Int = 0,
        nearDistance: Int = 10,
        name: String
    ) throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)

        var fCkId: String? = nil
        if let fid = folderId {
            let findFolderSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
            if let fetchedCkId = try db.fetch(query: findFolderSql, parameters: [fid], mapping: { $0.string(at: 0) }).compactMap({ $0 }).first {
                fCkId = fetchedCkId
            }
        }

        var reloadedResults: [SyncResult] = []

        try db.transaction {
            for (_, group) in groupedResults {
                let cId = UUID().uuidString
                let commaSeparatedContentIds = group.contentIds.joined(separator: ",")

                let sql = """
                INSERT INTO \(resultsTable) (
                    \(colFolderId), \(colName), \(colQuery), \(colArchive),
                    \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified),
                    \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance)
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """

                let params: [Any] = [
                    folderId ?? NSNull(),
                    name,
                    query,
                    group.archive,
                    group.bkId,
                    commaSeparatedContentIds,
                    cId,
                    now,
                    fCkId ?? NSNull(),
                    searchMode,
                    nearDistance,
                ]

                try db.execute(query: sql, parameters: params)
                let rowId = db.lastInsertRowId()
                try self.addPendingSync(ckRecordId: cId, operation: "upload")

                let reloadSql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colId) = ? LIMIT 1"
                if let reloaded = try db.fetch(query: reloadSql, parameters: [rowId], mapping: { self.makeSyncResult(from: $0) }).first {
                    reloadedResults.append(reloaded)
                }
            }
        }

        if !reloadedResults.isEmpty {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: reloadedResults, trackPending: false)
        }
    }

    func fetchResults(forFolder folderId: Int64?) -> [ResultNode] {
        guard let db else { return [] }
        var groupedResults: [String: (id: Int64, parentId: Int64?, lastModified: Int64?, items: [SavedResultsItem])] = [:]

        let sql: String
        var params: [Any] = []
        if let fid = folderId {
            sql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colFolderId) = ?"
            params = [fid]
        } else {
            sql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colFolderCkRecordId) IS NULL"
        }

        do {
            let results = try db.fetch(query: sql, parameters: params) { row -> (Int64, Int64?, String, String, Int, Int, String, Int64?, Int, Int) in
                return (
                    row.int64(at: 0),
                    !row.isNull(at: 1) ? row.int64(at: 1) : nil,
                    row.string(at: 2) ?? "",
                    row.string(at: 3) ?? "",
                    row.int(at: 4),
                    row.int(at: 5),
                    row.string(at: 6) ?? "",
                    !row.isNull(at: 8) ? row.int64(at: 8) : nil,
                    row.int(at: 9),
                    row.int(at: 10)
                )
            }

            for res in results {
                let resultId = res.0
                let parentId = res.1
                let savedName = res.2
                let queryName = res.3
                let rArchive = res.4
                let rBkId = res.5
                let rContentId = res.6
                let rLastModified = res.7
                let rSearchMode = res.8
                let rNearDistance = res.9

                let contentsId = rContentId.components(separatedBy: ",")

                for cid in contentsId {
                    guard let idInt = Int(cid) else { continue }
                    let book = LibraryDataManager.shared.getBook([rBkId]).first

                    let item = SavedResultsItem(
                        archive: String(rArchive),
                        tableName: String(rBkId),
                        query: queryName,
                        bookId: idInt,
                        bookTitle: book?.book ?? "",
                        searchMode: rSearchMode,
                        nearDistance: rNearDistance
                    )

                    if groupedResults[savedName] == nil {
                        groupedResults[savedName] = (id: resultId, parentId: parentId, lastModified: rLastModified, items: [])
                    }

                    groupedResults[savedName]?.items.append(item)
                }
            }
        } catch {
            print("Failed to fetch results: \(error)")
        }

        return groupedResults.map {
            let mode = $0.value.items.first?.searchMode ?? 0
            let distance = $0.value.items.first?.nearDistance ?? 10
            return ResultNode(
                id: $0.value.id,
                parentId: $0.value.parentId,
                name: $0.key,
                lastModified: $0.value.lastModified,
                searchMode: mode,
                nearDistance: distance,
                items: $0.value.items
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension ResultsHandler {
    func updateFolderName(id folderId: Int64, newName: String) throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let sql = "UPDATE \(foldersTable) SET \(colName) = ?, \(colLastModified) = ? WHERE \(colId) = ?;"

        try transaction {
            let findCkIdSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
            let ckId = try db.fetch(query: findCkIdSql, parameters: [folderId]) { $0.string(at: 0) }.compactMap { $0 }.first

            try exec(sql, parameters: [newName, now, folderId])

            if let ckId = ckId {
                try self.addPendingSync(ckRecordId: ckId, operation: "upload")
            }
        }

        let reloadSql = "SELECT \(colId), \(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
        if let reloaded = try db.fetch(query: reloadSql, parameters: [folderId], mapping: { self.makeSyncFolder(from: $0) }).first {
            CloudKitSyncManager.shared.uploadResultsData(folders: [reloaded], results: [], trackPending: false)
        }
    }

    func updateResultQueryName(folderId: Int64?, oldName: String, newName: String) throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let sql: String
        var params: [Any] = []

        if let fid = folderId {
            sql = "UPDATE \(resultsTable) SET \(colName) = ?, \(colResLastModified) = ? WHERE \(colFolderId) = ? AND \(colName) = ?;"
            params = [newName, now, fid, oldName]
        } else {
            sql = "UPDATE \(resultsTable) SET \(colName) = ?, \(colResLastModified) = ? WHERE \(colFolderId) IS NULL AND \(colName) = ?;"
            params = [newName, now, oldName]
        }

        var ckIds: [String] = []
        try transaction {
            let findCkIdSql: String
            let findCkIdParams: [Any]
            if let fid = folderId {
                findCkIdSql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?"
                findCkIdParams = [fid, oldName]
            } else {
                findCkIdSql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?"
                findCkIdParams = [oldName]
            }
            ckIds = try db.fetch(query: findCkIdSql, parameters: findCkIdParams) { $0.string(at: 0) }.compactMap { $0 }

            try exec(sql, parameters: params)

            for ckId in ckIds {
                try self.addPendingSync(ckRecordId: ckId, operation: "upload")
            }
        }

        let reloadSql: String
        var reloadParams: [Any] = []
        if let fid = folderId {
            reloadSql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?"
            reloadParams = [fid, newName]
        } else {
            reloadSql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?"
            reloadParams = [newName]
        }

        let updatedResults = try db.fetch(query: reloadSql, parameters: reloadParams) { self.makeSyncResult(from: $0) }

        if !updatedResults.isEmpty {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: updatedResults, trackPending: false)
        }
    }

    func updateResultsFolder(oldFolderId: Int64, newFolderId: Int64) {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)

        do {
            var updatedResults: [SyncResult] = []
            try transaction {
                var fCkId: String? = nil
                let findFolderSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
                if let fetchedCkId = try db.fetch(query: findFolderSql, parameters: [newFolderId], mapping: { $0.string(at: 0) }).compactMap({ $0 }).first {
                    fCkId = fetchedCkId
                }

                let updateSql = "UPDATE \(resultsTable) SET \(colFolderId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ? WHERE \(colFolderId) = ?;"
                let params: [Any] = [newFolderId, now, fCkId ?? NSNull(), oldFolderId]
                try db.execute(query: updateSql, parameters: params)

                let reloadSql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colFolderId) = ?"
                updatedResults = try db.fetch(query: reloadSql, parameters: [newFolderId]) { self.makeSyncResult(from: $0) }

                for res in updatedResults {
                    if let ckId = res.ckRecordId {
                        try self.addPendingSync(ckRecordId: ckId, operation: "upload")
                    }
                }
            }

            if !updatedResults.isEmpty {
                CloudKitSyncManager.shared.uploadResultsData(folders: [], results: updatedResults, trackPending: false)
            }
        } catch {
            print("Failed to update results folder: \(error)")
        }
    }

    func getAllDescendantIds(of folderId: Int64) -> [Int64] {
        guard let db else { return [folderId] }
        var ids: [Int64] = []
        _getAllDescendantIds(of: folderId, ids: &ids, db: db)
        return ids
    }

    private func _getAllDescendantIds(of folderId: Int64, ids: inout [Int64], db: SQLiteDatabase) {
        ids.append(folderId)
        let sql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colParent) = ?"
        do {
            let children = try db.fetch(query: sql, parameters: [folderId]) { $0.int64(at: 0) }
            for childId in children {
                _getAllDescendantIds(of: childId, ids: &ids, db: db)
            }
        } catch {
            print("Failed to get descendant IDs: \(error)")
        }
    }

    func fetchFolders(byCkRecordIds ckRecordIds: [String]) -> [SyncFolder] {
        guard let db else { return [] }
        var folders: [SyncFolder] = []
        let chunkSize = 500
        for i in stride(from: 0, to: ckRecordIds.count, by: chunkSize) {
            let chunk = Array(ckRecordIds[i..<min(i + chunkSize, ckRecordIds.count)])
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let sql = "SELECT \(colId), \(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId) FROM \(foldersTable) WHERE \(colCkRecordId) IN (\(placeholders))"
            if let fetched = try? db.fetch(query: sql, parameters: chunk, mapping: { self.makeSyncFolder(from: $0) }) {
                folders.append(contentsOf: fetched)
            }
        }
        return folders
    }

    func fetchResults(byCkRecordIds ckRecordIds: [String]) -> [SyncResult] {
        guard let db else { return [] }
        var results: [SyncResult] = []
        let chunkSize = 500
        for i in stride(from: 0, to: ckRecordIds.count, by: chunkSize) {
            let chunk = Array(ckRecordIds[i..<min(i + chunkSize, ckRecordIds.count)])
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let sql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable) WHERE \(colResCkRecordId) IN (\(placeholders))"
            if let fetched = try? db.fetch(query: sql, parameters: chunk, mapping: { self.makeSyncResult(from: $0) }) {
                results.append(contentsOf: fetched)
            }
        }
        return results
    }

    func fetchAllSyncFolders() -> [SyncFolder] {
        guard let db else { return [] }
        let sql = "SELECT \(colId), \(colName), \(colParent), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId) FROM \(foldersTable)"
        do {
            return try db.fetch(query: sql) { self.makeSyncFolder(from: $0) }
        } catch {
            print("Failed to fetch all sync folders: \(error)")
            return []
        }
    }

    func fetchAllSyncResults() -> [SyncResult] {
        guard let db else { return [] }
        let sql = "SELECT \(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance) FROM \(resultsTable)"
        do {
            return try db.fetch(query: sql) { self.makeSyncResult(from: $0) }
        } catch {
            print("Failed to fetch all sync results: \(error)")
            return []
        }
    }
}

// MARK: - CloudKit Sync Apply

extension ResultsHandler {
    @discardableResult func applyCloudKitFolderChanges(foldersToSave: [SyncFolder], recordIdsToDelete: [String]) -> Bool {
        guard let db else { return false }

        do {
            try transaction {
                // 1. Process Deletions
                try processFolderDeletions(recordIdsToDelete: recordIdsToDelete, db: db)

                // 2. Sort folders topologically to ensure parents are inserted before children
                let sortedFolders = sortFoldersTopologically(folders: foldersToSave)

                // --- Prefetch mappings to avoid N+1 queries ---
                let allParentCkIds = Array(Set(foldersToSave.compactMap { $0.parentCkRecordId }))
                var folderCkIdToLocalId: [String: Int64] = [:]
                let parentChunkSize = 500
                for i in stride(from: 0, to: allParentCkIds.count, by: parentChunkSize) {
                    let chunk = Array(allParentCkIds[i..<min(i+parentChunkSize, allParentCkIds.count)])
                    let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                    let sql = "SELECT \(colCkRecordId), \(colId) FROM \(foldersTable) WHERE \(colCkRecordId) IN (\(placeholders))"

                    let rows = try db.fetch(query: sql, parameters: chunk, mapping: {
                        ($0.string(at: 0) ?? "", $0.int64(at: 1))
                    })
                    for (ckId, localId) in rows {
                        folderCkIdToLocalId[ckId] = localId
                    }
                }

                let allFolderCkIds = Array(Set(foldersToSave.compactMap { $0.ckRecordId }))
                var folderCkIdToExisting: [String: (Int64, Int64, Int64?)] = [:]
                let folderChunkSize = 500
                for i in stride(from: 0, to: allFolderCkIds.count, by: folderChunkSize) {
                    let chunk = Array(allFolderCkIds[i..<min(i+folderChunkSize, allFolderCkIds.count)])
                    let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                    let sql = "SELECT \(colCkRecordId), \(colId), \(colLastModified), \(colParent) FROM \(foldersTable) WHERE \(colCkRecordId) IN (\(placeholders))"

                    let rows = try db.fetch(query: sql, parameters: chunk, mapping: {
                        ($0.string(at: 0) ?? "", $0.int64(at: 1), $0.int64(at: 2), !$0.isNull(at: 3) ? $0.int64(at: 3) : nil)
                    })
                    for (ckId, localId, lastMod, parentId) in rows {
                        folderCkIdToExisting[ckId] = (localId, lastMod, parentId)
                    }
                }
                // --- End Prefetch ---

                // 3. Process Saves/Updates
                for folder in sortedFolders {
                    try processSingleFolderSave(folder, db: db, folderCkIdToLocalId: &folderCkIdToLocalId, folderCkIdToExisting: folderCkIdToExisting)
                }
            }

            resolveOrphanFolders()

            // Post notification for UI refresh
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .savedResultsTreeDidUpdate, object: nil)
            }
        } catch {
            print("ResultsHandler: Failed to apply folder changes - \(error)")
            return false
        }
        return true
    }

    private func processFolderDeletions(recordIdsToDelete: [String], db: SQLiteDatabase) throws {
        guard !recordIdsToDelete.isEmpty else { return }
        let chunkSize = 999
        var allLocalIdsToDelete = Set<Int64>()

        let ckIdChunks = stride(from: 0, to: recordIdsToDelete.count, by: chunkSize).map {
            Array(recordIdsToDelete[$0..<min($0 + chunkSize, recordIdsToDelete.count)])
        }

        for chunk in ckIdChunks {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let findSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colCkRecordId) IN (\(placeholders))"

            let localIds = try db.fetch(query: findSql, parameters: chunk, mapping: { $0.int64(at: 0) })

            for localId in localIds {
                let descendantIds = getAllDescendantIds(of: localId)
                allLocalIdsToDelete.formUnion(descendantIds)
            }
        }

        let uniqueLocalIds = Array(allLocalIdsToDelete)
        let localIdChunks = stride(from: 0, to: uniqueLocalIds.count, by: chunkSize).map {
            Array(uniqueLocalIds[$0..<min($0 + chunkSize, uniqueLocalIds.count)])
        }

        for chunk in localIdChunks {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            try exec("DELETE FROM \(resultsTable) WHERE \(colFolderId) IN (\(placeholders));", parameters: chunk)
            try exec("DELETE FROM \(foldersTable) WHERE \(colId) IN (\(placeholders));", parameters: chunk)
        }
    }

    private func sortFoldersTopologically(folders: [SyncFolder]) -> [SyncFolder] {
        var sortedFolders: [SyncFolder] = []
        var pendingFolders = folders
        var progress = true

        while !pendingFolders.isEmpty, progress {
            progress = false
            for i in (0 ..< pendingFolders.count).reversed() {
                let f = pendingFolders[i]
                let parentInPending = pendingFolders.contains { $0.ckRecordId == f.parentCkRecordId }
                if !parentInPending {
                    sortedFolders.append(f)
                    pendingFolders.remove(at: i)
                    progress = true
                }
            }
        }
        // Append any remaining folders in case of circular dependencies
        sortedFolders.append(contentsOf: pendingFolders)
        return sortedFolders
    }

    private func processSingleFolderSave(_ folder: SyncFolder, db: SQLiteDatabase, folderCkIdToLocalId: inout [String: Int64], folderCkIdToExisting: [String: (Int64, Int64, Int64?)]) throws {
        guard let ckId = folder.ckRecordId else { return }

        // Resolve parent locally
        var pLocalId: Int64? = nil
        if let pCkId = folder.parentCkRecordId {
            pLocalId = folderCkIdToLocalId[pCkId]
        }

        var existingLocalId: Int64 = -1
        var localLastMod: Int64 = 0
        var existingParentId: Int64? = nil

        if let existing = folderCkIdToExisting[ckId] {
            existingLocalId = existing.0
            localLastMod = existing.1
            existingParentId = existing.2
        }

        var newInsertedLocalId: Int64? = nil

        if existingLocalId != -1 {
            let remoteLastMod = folder.lastModified ?? 0
            if remoteLastMod >= localLastMod {
                let isOrphan = folder.parentCkRecordId != nil && pLocalId == nil
                let newParentForDb = isOrphan ? existingParentId : pLocalId

                if !isOrphan || newParentForDb != nil {
                    let conflictSql: String
                    let conflictParams: [Any]
                    if let pid = newParentForDb {
                        conflictSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colParent) = ? AND \(colName) = ? AND \(colId) != ? LIMIT 1"
                        conflictParams = [pid, folder.name, existingLocalId]
                    } else {
                        conflictSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colParent) IS NULL AND \(colName) = ? AND \(colId) != ? LIMIT 1"
                        conflictParams = [folder.name, existingLocalId]
                    }
                    if let conflictId = try db.fetch(query: conflictSql, parameters: conflictParams, mapping: { $0.int64(at: 0) }).first {
                        try exec("DELETE FROM \(foldersTable) WHERE \(colId) = ?;", parameters: [conflictId])
                    }
                }

                let upSql = "UPDATE \(foldersTable) SET \(colName) = ?, \(colLastModified) = ?, \(colParentCkRecordId) = ?, \(colParent) = ? WHERE \(colId) = ?;"
                try db.execute(query: upSql, parameters: [folder.name, folder.lastModified ?? 0, folder.parentCkRecordId ?? NSNull(), newParentForDb ?? NSNull(), existingLocalId])
                newInsertedLocalId = existingLocalId
            } else {
                newInsertedLocalId = existingLocalId
            }
        } else {
            var conflictLocalId: Int64 = -1
            var conflictLastMod: Int64 = 0

            let isOrphan = folder.parentCkRecordId != nil && pLocalId == nil

            if !isOrphan {
                let conflictSql: String
                let conflictParams: [Any]
                if let pid = pLocalId {
                    conflictSql = "SELECT \(colId), \(colLastModified) FROM \(foldersTable) WHERE \(colParent) = ? AND \(colName) = ? LIMIT 1"
                    conflictParams = [pid, folder.name]
                } else {
                    conflictSql = "SELECT \(colId), \(colLastModified) FROM \(foldersTable) WHERE \(colParent) IS NULL AND \(colName) = ? LIMIT 1"
                    conflictParams = [folder.name]
                }

                if let row = try db.fetch(query: conflictSql, parameters: conflictParams, mapping: { ($0.int64(at: 0), $0.int64(at: 1)) }).first {
                    conflictLocalId = row.0
                    conflictLastMod = row.1
                }
            }

            if conflictLocalId != -1 {
                let remoteLastMod = folder.lastModified ?? 0
                if remoteLastMod >= conflictLastMod {
                    let upSql = "UPDATE \(foldersTable) SET \(colCkRecordId) = ?, \(colLastModified) = ?, \(colParentCkRecordId) = ?, \(colParent) = ? WHERE \(colId) = ?;"
                    try db.execute(query: upSql, parameters: [ckId, folder.lastModified ?? 0, folder.parentCkRecordId ?? NSNull(), pLocalId ?? NSNull(), conflictLocalId])
                } else {
                    let upCkIdSql = "UPDATE \(foldersTable) SET \(colCkRecordId) = ? WHERE \(colId) = ?"
                    try db.execute(query: upCkIdSql, parameters: [ckId, conflictLocalId])
                }
                newInsertedLocalId = conflictLocalId
            } else {
                let insSql = "INSERT INTO \(foldersTable) (\(colName), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId), \(colParent)) VALUES (?, ?, ?, ?, ?);"
                try db.execute(query: insSql, parameters: [folder.name, ckId, folder.lastModified ?? 0, folder.parentCkRecordId ?? NSNull(), pLocalId ?? NSNull()])

                // Get the generated localId so children can use it
                newInsertedLocalId = db.lastInsertRowId()
            }
        }

        // Ensure that any child folders processed next in the topological sort can find this newly created/updated folder's localId
        if let newLocalId = newInsertedLocalId {
            folderCkIdToLocalId[ckId] = newLocalId
        }
    }
    @discardableResult func applyCloudKitResultChanges(resultsToSave: [SyncResult], recordIdsToDelete: [String]) -> Bool {
        guard let db else { return false }

        do {
            try transaction {
                // 1. Process Deletions
                for ckId in recordIdsToDelete {
                    try exec("DELETE FROM \(resultsTable) WHERE \(colResCkRecordId) = ?;", parameters: [ckId])
                }

                // 2. Process Saves/Updates

                // --- Prefetch mappings to avoid N+1 queries ---
                let allFolderCkIds = Array(Set(resultsToSave.compactMap { $0.folderCkRecordId }))
                var folderCkIdToLocalId: [String: Int64] = [:]
                let folderChunkSize = 500
                for i in stride(from: 0, to: allFolderCkIds.count, by: folderChunkSize) {
                    let chunk = Array(allFolderCkIds[i..<min(i+folderChunkSize, allFolderCkIds.count)])
                    let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                    let sql = "SELECT \(colCkRecordId), \(colId) FROM \(foldersTable) WHERE \(colCkRecordId) IN (\(placeholders))"

                    let rows = try db.fetch(query: sql, parameters: chunk, mapping: {
                        ($0.string(at: 0) ?? "", $0.int64(at: 1))
                    })
                    for (ckId, localId) in rows {
                        folderCkIdToLocalId[ckId] = localId
                    }
                }

                let allResCkIds = Array(Set(resultsToSave.compactMap { $0.ckRecordId }))
                var resCkIdToExisting: [String: (Int64, Int64, Int64?)] = [:]
                let resChunkSize = 500
                for i in stride(from: 0, to: allResCkIds.count, by: resChunkSize) {
                    let chunk = Array(allResCkIds[i..<min(i+resChunkSize, allResCkIds.count)])
                    let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                    let sql = "SELECT \(colResCkRecordId), \(colId), \(colResLastModified), \(colFolderId) FROM \(resultsTable) WHERE \(colResCkRecordId) IN (\(placeholders))"

                    let rows = try db.fetch(query: sql, parameters: chunk, mapping: {
                        ($0.string(at: 0) ?? "", $0.int64(at: 1), $0.int64(at: 2), !$0.isNull(at: 3) ? $0.int64(at: 3) : nil)
                    })
                    for (ckId, localId, lastMod, folderId) in rows {
                        resCkIdToExisting[ckId] = (localId, lastMod, folderId)
                    }
                }

                // Prefetch existing conflict records to avoid N+1 inside the loop
                // Conflict matching is based on (folderId, name, bkId)
                // We'll map "folderId_name_bkId" to (id, lastModified)
                // If folderId is nil, we'll map "NULL_name_bkId"
                var conflictMap: [String: (Int64, Int64)] = [:]
                // It is difficult to prefetch *all* combinations via IN effectively, so we'll
                // just do a fast fetch of the entire results table if it's small, OR
                // batch query by bkId which is usually highly overlapping.
                // Wait, resultsToSave may span multiple bkIds, let's just batch query for the bkIds present.
                let allBkIds = Array(Set(resultsToSave.compactMap { $0.bkId }))
                for i in stride(from: 0, to: allBkIds.count, by: 500) {
                    let chunk = Array(allBkIds[i..<min(i+500, allBkIds.count)])
                    let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                    let conflictSql = "SELECT \(colId), \(colResLastModified), \(colFolderId), \(colName), \(colBkId) FROM \(resultsTable) WHERE \(colBkId) IN (\(placeholders))"

                    let rows = try db.fetch(query: conflictSql, parameters: chunk, mapping: { row -> (Int64, Int64, Int64?, String, Int) in
                        return (row.int64(at: 0), row.int64(at: 1), !row.isNull(at: 2) ? row.int64(at: 2) : nil, row.string(at: 3) ?? "", row.int(at: 4))
                    })
                    for (id, lastMod, folderId, name, bkId) in rows {
                        let fIdStr = folderId != nil ? "\(folderId!)" : "NULL"
                        let key = "\(fIdStr)_\(name)_\(bkId)"
                        conflictMap[key] = (id, lastMod)
                    }
                }
                // --- End Prefetch ---

                for res in resultsToSave {
                    guard let ckId = res.ckRecordId else { continue }

                    // Resolve folderId
                    var fLocalId: Int64? = nil
                    if let fCkId = res.folderCkRecordId {
                        fLocalId = folderCkIdToLocalId[fCkId]
                    }

                    var existingLocalId: Int64 = -1
                    var localLastMod: Int64 = 0
                    var existingFolderId: Int64? = nil

                    if let existing = resCkIdToExisting[ckId] {
                        existingLocalId = existing.0
                        localLastMod = existing.1
                        existingFolderId = existing.2
                    }

                    if existingLocalId != -1 {
                        let remoteLastMod = res.lastModified ?? 0
                        if remoteLastMod >= localLastMod {
                            let isOrphan = res.folderCkRecordId != nil && fLocalId == nil
                            let newFolderForDb = isOrphan ? existingFolderId : fLocalId

                            if !isOrphan || newFolderForDb != nil {
                                let fIdStr = newFolderForDb != nil ? "\(newFolderForDb!)" : "NULL"
                                let key = "\(fIdStr)_\(res.name)_\(res.bkId)"
                                if let conflict = conflictMap[key], conflict.0 != existingLocalId {
                                    try exec("DELETE FROM \(resultsTable) WHERE \(colId) = ?;", parameters: [conflict.0])
                                    // Remove from map to avoid reusing deleted ID
                                    conflictMap.removeValue(forKey: key)
                                }
                            }

                            let upSql = """
                            UPDATE \(resultsTable) SET 
                            \(colFolderId) = ?, \(colName) = ?, \(colQuery) = ?, \(colArchive) = ?,
                            \(colBkId) = ?, \(colContentId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ?, \(colSearchMode) = ?, \(colNearDistance) = ?
                            WHERE \(colId) = ?;
                            """
                            let params: [Any] = [
                                newFolderForDb ?? NSNull(), res.name, res.query, res.archive,
                                res.bkId, res.contentId, res.lastModified ?? 0, res.folderCkRecordId ?? NSNull(),
                                res.searchMode, res.nearDistance, existingLocalId,
                            ]
                            try db.execute(query: upSql, parameters: params)

                            let finalFolderStr = newFolderForDb != nil ? "\(newFolderForDb!)" : "NULL"
                            let finalKey = "\(finalFolderStr)_\(res.name)_\(res.bkId)"
                            conflictMap[finalKey] = (existingLocalId, res.lastModified ?? 0)
                        }
                    } else {
                        var conflictLocalId: Int64 = -1
                        var conflictLastMod: Int64 = 0

                        let isOrphan = res.folderCkRecordId != nil && fLocalId == nil

                        if !isOrphan {
                            let fIdStr = fLocalId != nil ? "\(fLocalId!)" : "NULL"
                            let key = "\(fIdStr)_\(res.name)_\(res.bkId)"
                            if let conflict = conflictMap[key] {
                                conflictLocalId = conflict.0
                                conflictLastMod = conflict.1
                            }
                        }

                        if conflictLocalId != -1 {
                            let remoteLastMod = res.lastModified ?? 0
                            if remoteLastMod >= conflictLastMod {
                                let upSql = """
                                UPDATE \(resultsTable) SET 
                                \(colFolderId) = ?, \(colName) = ?, \(colQuery) = ?, \(colArchive) = ?,
                                \(colBkId) = ?, \(colContentId) = ?, \(colResCkRecordId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ?, \(colSearchMode) = ?, \(colNearDistance) = ?
                                WHERE \(colId) = ?;
                                """
                                let params: [Any] = [
                                    fLocalId ?? NSNull(), res.name, res.query, res.archive,
                                    res.bkId, res.contentId, ckId, res.lastModified ?? 0, res.folderCkRecordId ?? NSNull(),
                                    res.searchMode, res.nearDistance, conflictLocalId,
                                ]
                                try db.execute(query: upSql, parameters: params)

                                let finalFolderStr = fLocalId != nil ? "\(fLocalId!)" : "NULL"
                                let finalKey = "\(finalFolderStr)_\(res.name)_\(res.bkId)"
                                conflictMap[finalKey] = (conflictLocalId, res.lastModified ?? 0)
                            } else {
                                let upCkIdSql = "UPDATE \(resultsTable) SET \(colResCkRecordId) = ? WHERE \(colId) = ?"
                                try db.execute(query: upCkIdSql, parameters: [ckId, conflictLocalId])
                            }
                        } else {
                            let insSql = """
                            INSERT INTO \(resultsTable) (
                                \(colFolderId), \(colName), \(colQuery), \(colArchive),
                                \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified),
                                \(colFolderCkRecordId), \(colSearchMode), \(colNearDistance)
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                            """
                            let params: [Any] = [
                                fLocalId ?? NSNull(), res.name, res.query, res.archive,
                                res.bkId, res.contentId, ckId, res.lastModified ?? 0,
                                res.folderCkRecordId ?? NSNull(), res.searchMode, res.nearDistance,
                            ]
                            try db.execute(query: insSql, parameters: params)

                            let finalFolderStr = fLocalId != nil ? "\(fLocalId!)" : "NULL"
                            let finalKey = "\(finalFolderStr)_\(res.name)_\(res.bkId)"
                            conflictMap[finalKey] = (db.lastInsertRowId(), res.lastModified ?? 0)
                        }
                    }
                }
            }

            resolveOrphanResults()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .savedResultsTreeDidUpdate, object: nil)
            }
        } catch {
            print("ResultsHandler: Failed to apply result changes - \(error)")
            return false
        }
        return true
    }

    func resolveOrphanFolders() {
        guard let db else { return }
        do {
            try transaction {
                // Find folders where parentCkRecordId is not null, but parent doesn't match
                let sql = """
                SELECT f1.\(colId), f1.\(colName), f1.\(colParentCkRecordId), f2.\(colId) as expected_parent
                FROM \(foldersTable) f1
                LEFT JOIN \(foldersTable) f2 ON f1.\(colParentCkRecordId) = f2.\(colCkRecordId)
                WHERE f1.\(colParentCkRecordId) IS NOT NULL 
                AND COALESCE(f1.\(colParent), -1) != COALESCE(f2.\(colId), -1)
                """
                
                let orphans = try db.fetch(query: sql) { row -> (id: Int64, name: String, expectedParent: Int64?) in
                    return (
                        row.int64(at: 0),
                        row.string(at: 1) ?? "",
                        !row.isNull(at: 3) ? row.int64(at: 3) : nil
                    )
                }
                
                for orphan in orphans {
                    guard let newParentId = orphan.expectedParent else { continue }
                    
                    // Check if unique constraint would be violated
                    let conflictSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colParent) = ? AND \(colName) = ? AND \(colId) != ? LIMIT 1"
                    if let conflictId = try db.fetch(query: conflictSql, parameters: [newParentId, orphan.name, orphan.id], mapping: { $0.int64(at: 0) }).first {
                        // Merge orphan into existing folder
                        try exec("UPDATE \(resultsTable) SET \(colFolderId) = ? WHERE \(colFolderId) = ?;", parameters: [conflictId, orphan.id])
                        try exec("UPDATE \(foldersTable) SET \(colParent) = ? WHERE \(colParent) = ?;", parameters: [conflictId, orphan.id])
                        try exec("DELETE FROM \(foldersTable) WHERE \(colId) = ?;", parameters: [orphan.id])
                    } else {
                        // Safe to reparent
                        try exec("UPDATE \(foldersTable) SET \(colParent) = ? WHERE \(colId) = ?;", parameters: [newParentId, orphan.id])
                    }
                }
            }
        } catch {
            print("ResultsHandler: Failed to resolve orphan folders - \(error)")
        }
    }

    func resolveOrphanResults() {
        guard let db else { return }
        do {
            try transaction {
                let sql = """
                SELECT r.\(colId), r.\(colName), r.\(colBkId), f.\(colId) as expected_folder
                FROM \(resultsTable) r
                LEFT JOIN \(foldersTable) f ON r.\(colFolderCkRecordId) = f.\(colCkRecordId)
                WHERE r.\(colFolderCkRecordId) IS NOT NULL
                AND COALESCE(r.\(colFolderId), -1) != COALESCE(f.\(colId), -1)
                """
                
                let orphans = try db.fetch(query: sql) { row -> (id: Int64, name: String, bkId: Int, expectedFolder: Int64?) in
                    return (
                        row.int64(at: 0),
                        row.string(at: 1) ?? "",
                        row.int(at: 2),
                        !row.isNull(at: 3) ? row.int64(at: 3) : nil
                    )
                }
                
                for orphan in orphans {
                    guard let newFolderId = orphan.expectedFolder else { continue }
                    
                    // Check if unique constraint would be violated
                    let conflictSql = "SELECT \(colId) FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ? AND \(colBkId) = ? AND \(colId) != ? LIMIT 1"
                    if let _ = try db.fetch(query: conflictSql, parameters: [newFolderId, orphan.name, orphan.bkId, orphan.id], mapping: { $0.int64(at: 0) }).first {
                        // Conflict: just delete the orphan since it's a leaf node duplicate
                        try exec("DELETE FROM \(resultsTable) WHERE \(colId) = ?;", parameters: [orphan.id])
                    } else {
                        // Safe to reparent
                        try exec("UPDATE \(resultsTable) SET \(colFolderId) = ? WHERE \(colId) = ?;", parameters: [newFolderId, orphan.id])
                    }
                }
            }
        } catch {
            print("ResultsHandler: Failed to resolve orphan results - \(error)")
        }
    }
}
