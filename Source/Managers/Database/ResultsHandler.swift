//
//  ResultsHandler.swift
//  maktab
//
//  Created by MacBook on 05/12/25.
//

import Foundation
import SQLite3

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
    private let colFolderCkRecordId = "folderCkRecordId"

    func migrateBookId(from oldId: Int, to newId: Int) throws -> [SyncResult] {
        guard let db else { return [] }
        let now = Int64(Date().timeIntervalSince1970)
        
        let sql = "UPDATE \(resultsTable) SET \(colBkId) = ?, \(colResLastModified) = ? WHERE \(colBkId) = ?"
        try exec(sql, parameters: [newId, now, oldId])
        
        // Fetch updated results to upload
        let fetchSql = "SELECT * FROM \(resultsTable) WHERE \(colBkId) = ?"
        let updatedResults = try db.fetch(query: fetchSql, parameters: [newId]) { self.makeSyncResult(from: $0) }
        
        for res in updatedResults {
            if let ckId = res.ckRecordId {
                addPendingSync(ckRecordId: ckId, operation: "upload")
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
        guard let folderURL = folderURL else { throw NSError(domain: "maktabah", code: 404) }
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
                \(colResCkRecordId) TEXT,
                \(colResLastModified) INTEGER,
                \(colFolderCkRecordId) TEXT,
                UNIQUE(\(colFolderId), \(colName), \(colBkId))
            );
            """)

            try exec("""
            CREATE TABLE IF NOT EXISTS sync_pending (
                ck_record_id TEXT PRIMARY KEY,
                operation TEXT NOT NULL CHECK(operation IN ('upload', 'delete')),
                queued_at INTEGER NOT NULL
            );
            """)

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
            if !resultCols.contains(colFolderCkRecordId) {
                try exec("ALTER TABLE \(resultsTable) ADD COLUMN \(colFolderCkRecordId) TEXT;")
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

    func backfillResultsCloudKitFieldsIfNeeded() throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)

        // 1. Backfill Folders (Order by parent to ensure top-down backfill)
        var foldersToUpload: [SyncFolder] = []

        try transaction {
            let sql = "SELECT * FROM \(foldersTable) WHERE \(colCkRecordId) IS NULL ORDER BY \(colParent) ASC"

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
                let reloadSql = "SELECT * FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
                if let reloaded = try db.fetch(query: reloadSql, parameters: [fId], mapping: { self.makeSyncFolder(from: $0) }).first {
                    foldersToUpload.append(reloaded)
                }
            }
        }

        // 2. Backfill Results
        var resultsToUpload: [SyncResult] = []

        try transaction {
            let sql = "SELECT * FROM \(resultsTable) WHERE \(colResCkRecordId) IS NULL"

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

                let reloadSql = "SELECT * FROM \(resultsTable) WHERE \(colId) = ? LIMIT 1"
                if let reloaded = try db.fetch(query: reloadSql, parameters: [rId], mapping: { self.makeSyncResult(from: $0) }).first {
                    resultsToUpload.append(reloaded)
                }
            }
        }

        if !foldersToUpload.isEmpty || !resultsToUpload.isEmpty {
            DispatchQueue.global(qos: .background).async {
                CloudKitSyncManager.shared.uploadResultsData(folders: foldersToUpload, results: resultsToUpload)
            }
        }
    }

    // MARK: - Sync Pending Helpers

    func addPendingSync(ckRecordId: String, operation: String) {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)
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

        try db.execute(query: sql, parameters: [name, cId, now])
        let rowId = db.lastInsertRowId()

        let reloadSql = "SELECT * FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
        if let reloaded = try db.fetch(query: reloadSql, parameters: [rowId], mapping: { self.makeSyncFolder(from: $0) }).first {
            CloudKitSyncManager.shared.uploadResultsData(folders: [reloaded], results: [])
        }

        return rowId
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
        if let pCkId = pCkId {
            params.append(pCkId)
        } else {
            params.append(NSNull())
        }

        try db.execute(query: sql, parameters: params)
        let rowId = db.lastInsertRowId()

        let reloadSql = "SELECT * FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
        if let reloaded = try db.fetch(query: reloadSql, parameters: [rowId], mapping: { self.makeSyncFolder(from: $0) }).first {
            CloudKitSyncManager.shared.uploadResultsData(folders: [reloaded], results: [])
        }

        return rowId
    }

    func fetchFolderTree() -> [FolderNode] {
        guard let db else { return [] }
        var nodes: [Int64: FolderNode] = [:]
        var roots: [FolderNode] = []

        let sql = "SELECT \(colId), \(colName), \(colParent) FROM \(foldersTable)"
        do {
            let rows = try db.fetch(query: sql) { row -> (id: Int64, name: String, parent: Int64?) in
                let fid = row.int64(at: 0)
                let fname = row.string(at: 1) ?? ""
                let fparent = !row.isNull(at: 2) ? row.int64(at: 2) : nil
                return (id: fid, name: fname, parent: fparent)
            }

            for row in rows {
                let node = FolderNode(id: row.id, name: row.name)
                nodes[row.id] = node
            }

            for row in rows {
                if let parentId = row.parent, let parentNode = nodes[parentId] {
                    parentNode.children.append(nodes[row.id]!)
                } else {
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
            }

            if !ckIdsToDelete.isEmpty {
                CloudKitSyncManager.shared.delete(ckRecordIds: ckIdsToDelete, target: .result)
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

            if !ckIds.isEmpty {
                CloudKitSyncManager.shared.delete(ckRecordIds: ckIds, target: .result)
            }
        } catch {
            print(error.localizedDescription)
        }
    }

    func updateParent(of id: Int64, to newParentId: Int64?) throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)

        var pCkId: String? = nil
        if let pid = newParentId {
            let findParentSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
            if let fetchedCkId = try db.fetch(query: findParentSql, parameters: [pid], mapping: { $0.string(at: 0) }).compactMap({ $0 }).first {
                pCkId = fetchedCkId
            }
        }

        let updateSql = "UPDATE \(foldersTable) SET \(colParent) = ?, \(colLastModified) = ?, \(colParentCkRecordId) = ? WHERE \(colId) = ?;"
        let params: [Any] = [newParentId ?? NSNull(), now, pCkId ?? NSNull(), id]
        try db.execute(query: updateSql, parameters: params)

        let reloadSql = "SELECT * FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
        if let reloaded = try db.fetch(query: reloadSql, parameters: [id], mapping: { self.makeSyncFolder(from: $0) }).first {
            CloudKitSyncManager.shared.uploadResultsData(folders: [reloaded], results: [])
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

        try db.execute(query: updateSql, parameters: params)

        let reloadSql: String
        var reloadParams: [Any] = []
        if let nid = newParentId {
            reloadSql = "SELECT * FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?"
            reloadParams = [nid, name]
        } else {
            reloadSql = "SELECT * FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?"
            reloadParams = [name]
        }

        let updated = try db.fetch(query: reloadSql, parameters: reloadParams) { self.makeSyncResult(from: $0) }
        if !updated.isEmpty {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: updated)
        }
    }
}

extension ResultsHandler {
    func insertResult(_ archive: Int, bkId: Int, contentId: String, folderId: Int64?, query: String, name: String) throws {
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
            \(colFolderCkRecordId)
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
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
            fCkId ?? NSNull()
        ]

        try db.execute(query: sql, parameters: params)
        let rowId = db.lastInsertRowId()

        let reloadSql = "SELECT * FROM \(resultsTable) WHERE \(colId) = ? LIMIT 1"
        if let reloaded = try db.fetch(query: reloadSql, parameters: [rowId], mapping: { self.makeSyncResult(from: $0) }).first {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: [reloaded])
        }
    }

    func fetchResults(forFolder folderId: Int64?) -> [ResultNode] {
        guard let db else { return [] }
        var groupedResults: [String: (id: Int64, parentId: Int64?, items: [SavedResultsItem])] = [:]

        let sql: String
        var params: [Any] = []
        if let fid = folderId {
            sql = "SELECT * FROM \(resultsTable) WHERE \(colFolderId) = ?"
            params = [fid]
        } else {
            sql = "SELECT * FROM \(resultsTable) WHERE \(colFolderId) IS NULL"
        }

        do {
            let results = try db.fetch(query: sql, parameters: params) { row -> (Int64, Int64?, String, String, Int, Int, String) in
                return (
                    row.int64(at: 0),
                    !row.isNull(at: 1) ? row.int64(at: 1) : nil,
                    row.string(at: 2) ?? "",
                    row.string(at: 3) ?? "",
                    row.int(at: 4),
                    row.int(at: 5),
                    row.string(at: 6) ?? ""
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

                let contentsId = rContentId.components(separatedBy: ",")

                for cid in contentsId {
                    guard let idInt = Int(cid),
                          let book = LibraryDataManager.shared.getBook([rBkId]).first
                    else { continue }

                    let item = SavedResultsItem(
                        archive: String(rArchive),
                        tableName: String(rBkId),
                        query: queryName,
                        bookId: idInt,
                        bookTitle: book.book
                    )

                    if groupedResults[savedName] == nil {
                        groupedResults[savedName] = (id: resultId, parentId: parentId, items: [])
                    }

                    groupedResults[savedName]?.items.append(item)
                }
            }
        } catch {
            print("Failed to fetch results: \(error)")
        }

        return groupedResults.map {
            ResultNode(
                id: $0.value.id,
                parentId: $0.value.parentId,
                name: $0.key,
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
        try db.execute(query: sql, parameters: [newName, now, folderId])

        let reloadSql = "SELECT * FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
        if let reloaded = try db.fetch(query: reloadSql, parameters: [folderId], mapping: { self.makeSyncFolder(from: $0) }).first {
            CloudKitSyncManager.shared.uploadResultsData(folders: [reloaded], results: [])
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

        try db.execute(query: sql, parameters: params)

        let reloadSql: String
        var reloadParams: [Any] = []
        if let fid = folderId {
            reloadSql = "SELECT * FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?"
            reloadParams = [fid, newName]
        } else {
            reloadSql = "SELECT * FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?"
            reloadParams = [newName]
        }

        let updatedResults = try db.fetch(query: reloadSql, parameters: reloadParams) { self.makeSyncResult(from: $0) }

        if !updatedResults.isEmpty {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: updatedResults)
        }
    }

    func updateResultsFolder(oldFolderId: Int64, newFolderId: Int64) {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)

        var fCkId: String? = nil
        let findFolderSql = "SELECT \(colCkRecordId) FROM \(foldersTable) WHERE \(colId) = ? LIMIT 1"
        do {
            if let fetchedCkId = try db.fetch(query: findFolderSql, parameters: [newFolderId], mapping: { $0.string(at: 0) }).compactMap({ $0 }).first {
                fCkId = fetchedCkId
            }

            let updateSql = "UPDATE \(resultsTable) SET \(colFolderId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ? WHERE \(colFolderId) = ?;"
            let params: [Any] = [newFolderId, now, fCkId ?? NSNull(), oldFolderId]
            try db.execute(query: updateSql, parameters: params)

            let reloadSql = "SELECT * FROM \(resultsTable) WHERE \(colFolderId) = ?"
            let updatedResults = try db.fetch(query: reloadSql, parameters: [newFolderId]) { self.makeSyncResult(from: $0) }

            if !updatedResults.isEmpty {
                CloudKitSyncManager.shared.uploadResultsData(folders: [], results: updatedResults)
            }
        } catch {
            print("Failed to update results folder: \(error)")
        }
    }

    func getAllDescendantIds(of folderId: Int64) -> [Int64] {
        guard let db else { return [folderId] }
        var ids: [Int64] = [folderId]

        let sql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colParent) = ?"
        do {
            let children = try db.fetch(query: sql, parameters: [folderId]) { $0.int64(at: 0) }
            for childId in children {
                ids.append(contentsOf: getAllDescendantIds(of: childId))
            }
        } catch {
            print("Failed to get descendant IDs: \(error)")
        }

        return ids
    }

    func fetchAllSyncFolders() -> [SyncFolder] {
        guard let db else { return [] }
        let sql = "SELECT * FROM \(foldersTable)"
        do {
            return try db.fetch(query: sql) { self.makeSyncFolder(from: $0) }
        } catch {
            print("Failed to fetch all sync folders: \(error)")
            return []
        }
    }

    func fetchAllSyncResults() -> [SyncResult] {
        guard let db else { return [] }
        let sql = "SELECT * FROM \(resultsTable)"
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
    func applyCloudKitFolderChanges(foldersToSave: [SyncFolder], recordIdsToDelete: [String]) {
        guard let db else { return }

        do {
            try transaction {
                // 1. Process Deletions
                for ckId in recordIdsToDelete {
                    let findSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colCkRecordId) = ? LIMIT 1"
                    if let localId = try db.fetch(query: findSql, parameters: [ckId], mapping: { $0.int64(at: 0) }).first {
                        let allLocalIds = getAllDescendantIds(of: localId)
                        for fId in allLocalIds {
                            try exec("DELETE FROM \(resultsTable) WHERE \(colFolderId) = ?;", parameters: [fId])
                            try exec("DELETE FROM \(foldersTable) WHERE \(colId) = ?;", parameters: [fId])
                        }
                    }
                }

                // 2. Process Saves/Updates (Pass 1: Upsert Folders)
                for folder in foldersToSave {
                    guard let ckId = folder.ckRecordId else { continue }

                    var existingLocalId: Int64 = -1
                    var localLastMod: Int64 = 0
                    let findSql = "SELECT \(colId), \(colLastModified) FROM \(foldersTable) WHERE \(colCkRecordId) = ? LIMIT 1"
                    if let row = try db.fetch(query: findSql, parameters: [ckId], mapping: { ($0.int64(at: 0), $0.int64(at: 1)) }).first {
                        existingLocalId = row.0
                        localLastMod = row.1
                    }

                    if existingLocalId != -1 {
                        let remoteLastMod = folder.lastModified ?? 0
                        if remoteLastMod >= localLastMod {
                            let upSql = "UPDATE \(foldersTable) SET \(colName) = ?, \(colLastModified) = ?, \(colParentCkRecordId) = ? WHERE \(colId) = ?;"
                            try db.execute(query: upSql, parameters: [folder.name, folder.lastModified ?? 0, folder.parentCkRecordId ?? NSNull(), existingLocalId])
                        }
                    } else {
                        let insSql = "INSERT INTO \(foldersTable) (\(colName), \(colCkRecordId), \(colLastModified), \(colParentCkRecordId)) VALUES (?, ?, ?, ?);"
                        try db.execute(query: insSql, parameters: [folder.name, ckId, folder.lastModified ?? 0, folder.parentCkRecordId ?? NSNull()])
                    }
                }

                // 3. Pass 2: Resolve Parent Pointers
                for folder in foldersToSave {
                    guard let ckId = folder.ckRecordId else { continue }
                    if let pCkId = folder.parentCkRecordId {
                        let findParentSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colCkRecordId) = ? LIMIT 1"
                        if let pLocalId = try db.fetch(query: findParentSql, parameters: [pCkId], mapping: { $0.int64(at: 0) }).first {
                            try exec("UPDATE \(foldersTable) SET \(colParent) = ? WHERE \(colCkRecordId) = ?;", parameters: [pLocalId, ckId])
                        }
                    } else {
                        try exec("UPDATE \(foldersTable) SET \(colParent) = NULL WHERE \(colCkRecordId) = ?;", parameters: [ckId])
                    }
                }
            }

            // Post notification for UI refresh
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .annotationTreeDidUpdate, object: nil)
            }
        } catch {
            print("ResultsHandler: Failed to apply folder changes - \(error)")
        }
    }

    func applyCloudKitResultChanges(resultsToSave: [SyncResult], recordIdsToDelete: [String]) {
        guard let db else { return }

        do {
            try transaction {
                // 1. Process Deletions
                for ckId in recordIdsToDelete {
                    try exec("DELETE FROM \(resultsTable) WHERE \(colResCkRecordId) = ?;", parameters: [ckId])
                }

                // 2. Process Saves/Updates
                for res in resultsToSave {
                    guard let ckId = res.ckRecordId else { continue }

                    // Resolve folderId
                    var fLocalId: Int64? = nil
                    if let fCkId = res.folderCkRecordId {
                        let findFolderSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colCkRecordId) = ? LIMIT 1"
                        if let localFid = try db.fetch(query: findFolderSql, parameters: [fCkId], mapping: { $0.int64(at: 0) }).first {
                            fLocalId = localFid
                        }
                    }

                    var existingLocalId: Int64 = -1
                    var localLastMod: Int64 = 0
                    let findResSql = "SELECT \(colId), \(colResLastModified) FROM \(resultsTable) WHERE \(colResCkRecordId) = ? LIMIT 1"
                    if let row = try db.fetch(query: findResSql, parameters: [ckId], mapping: { ($0.int64(at: 0), $0.int64(at: 1)) }).first {
                        existingLocalId = row.0
                        localLastMod = row.1
                    }

                    if existingLocalId != -1 {
                        let remoteLastMod = res.lastModified ?? 0
                        if remoteLastMod >= localLastMod {
                            let upSql = """
                            UPDATE \(resultsTable) SET 
                            \(colFolderId) = ?, \(colName) = ?, \(colQuery) = ?, \(colArchive) = ?,
                            \(colBkId) = ?, \(colContentId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ?
                            WHERE \(colId) = ?;
                            """
                            let params: [Any] = [
                                fLocalId ?? NSNull(), res.name, res.query, res.archive,
                                res.bkId, res.contentId, res.lastModified ?? 0, res.folderCkRecordId ?? NSNull(),
                                existingLocalId
                            ]
                            try db.execute(query: upSql, parameters: params)
                        }
                    } else {
                        let insSql = """
                        INSERT INTO \(resultsTable) (
                            \(colFolderId), \(colName), \(colQuery), \(colArchive),
                            \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified),
                            \(colFolderCkRecordId)
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                        """
                        let params: [Any] = [
                            fLocalId ?? NSNull(), res.name, res.query, res.archive,
                            res.bkId, res.contentId, ckId, res.lastModified ?? 0,
                            res.folderCkRecordId ?? NSNull()
                        ]
                        try db.execute(query: insSql, parameters: params)
                    }
                }
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .annotationTreeDidUpdate, object: nil)
            }
        } catch {
            print("ResultsHandler: Failed to apply result changes - \(error)")
        }
    }
}
