//
//  HistoryDatabaseManager.swift
//  Maktabah
//
//  Created by MacBook on 05/12/25.
//

import Foundation

class HistoryDatabaseManager {
    static let shared = HistoryDatabaseManager()

    private var _db: SQLiteDatabase?

    /// Legacy UserDefaults keys — used only for migration
    private let legacyStorageKey = "CloudReadingEntries"
    private let legacyPendingUploadsKey = "HistoryPendingUploads"
    private let legacyPendingDeletesKey = "HistoryPendingDeletes"
    private let migrationFlag = "HistoryVM_SQLiteMigrated"

    func setupDatabase() {
        guard let folderURL = AppConfig.folder(for: AppConfig.annotationsAndResultsFolder) else {
            #if DEBUG
            print("HistoryDatabaseManager: No folder URL available for History database")
            #endif
            return
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: folderURL.path) {
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        let url = folderURL.appendingPathComponent("History.sqlite")

        do {
            _db = try SQLiteDatabase(path: url.path)
            enableWALMode()
            try createTables()
        } catch {
            #if DEBUG
            print("HistoryDatabaseManager: Failed to setup database: \(error)")
            #endif
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
                print("HistoryDatabaseManager: failed to enable WAL mode, current: \(mode ?? "unknown")")
            }
            #endif
        } catch {
            #if DEBUG
            print("HistoryDatabaseManager: error enabling WAL mode: \(error)")
            #endif
        }
    }

    private func createTables() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS reading_entries (
            book_id INTEGER PRIMARY KEY,
            last_content_id INTEGER,
            last_opened_at REAL,
            favorited_at REAL,
            position_updated_at REAL,
            updated_at REAL NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            ck_record_id TEXT
        );
        """)

        try exec("""
        CREATE TABLE IF NOT EXISTS history_order (
            position INTEGER PRIMARY KEY,
            book_id INTEGER NOT NULL
        );
        """)

        try exec("""
        CREATE TABLE IF NOT EXISTS sync_pending (
            ck_record_id TEXT PRIMARY KEY,
            operation TEXT NOT NULL CHECK(operation IN ('upload', 'delete')),
            queued_at INTEGER NOT NULL
        );
        """)

        try exec("CREATE INDEX IF NOT EXISTS idx_re_favorite ON reading_entries (is_favorite, favorited_at);")
        try exec("CREATE INDEX IF NOT EXISTS idx_sync_pending_op ON sync_pending (operation, queued_at);")
    }

    // MARK: - SQLite Helpers

    private func exec(_ sql: String, parameters: [Any] = []) throws {
        guard let _db else { return }
        try _db.execute(query: sql, parameters: parameters)
    }

    func transaction(_ block: () throws -> Void) throws {
        guard let _db else { return }
        try _db.transaction(block)
    }

    // MARK: - Core CRUD

    func upsertEntry(_ entry: ReadingEntry) {
        let sql = """
        INSERT OR REPLACE INTO reading_entries
        (book_id, last_content_id, last_opened_at, favorited_at, position_updated_at, updated_at, is_favorite, ck_record_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        let params: [Any] = [
            entry.bookId,
            entry.lastContentId as Any? ?? NSNull(),
            entry.lastOpenedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
            entry.favoritedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
            entry.positionUpdatedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
            entry.updatedAt.timeIntervalSince1970,
            entry.isFavorite ? 1 : 0,
            entry.ckRecordId as Any? ?? NSNull(),
        ]
        try? _db?.execute(query: sql, parameters: params)
    }

    func upsertEntries(_ entries: [ReadingEntry]) throws {
        guard let _db, !entries.isEmpty else { return }
        let chunkSize = 50 // SQLite max params is 999. We have 8 params per entry. 50 * 8 = 400.
        
        for i in stride(from: 0, to: entries.count, by: chunkSize) {
            let chunk = Array(entries[i..<min(i + chunkSize, entries.count)])
            let placeholders = chunk.map { _ in "(?, ?, ?, ?, ?, ?, ?, ?)" }.joined(separator: ",")
            let sql = """
            INSERT OR REPLACE INTO reading_entries
            (book_id, last_content_id, last_opened_at, favorited_at, position_updated_at, updated_at, is_favorite, ck_record_id)
            VALUES \(placeholders);
            """
            
            var params = [Any]()
            for entry in chunk {
                params.append(contentsOf: [
                    entry.bookId,
                    entry.lastContentId as Any? ?? NSNull(),
                    entry.lastOpenedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
                    entry.favoritedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
                    entry.positionUpdatedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
                    entry.updatedAt.timeIntervalSince1970,
                    entry.isFavorite ? 1 : 0,
                    entry.ckRecordId as Any? ?? NSNull()
                ])
            }
            try _db.execute(query: sql, parameters: params)
        }
    }

    func deleteEntry(bookId: Int) {
        try? exec("DELETE FROM reading_entries WHERE book_id = ?;", parameters: [bookId])
    }

    func deleteEntries(bookIds: [Int]) throws {
        guard let _db, !bookIds.isEmpty else { return }
        let chunkSize = 500
        for i in stride(from: 0, to: bookIds.count, by: chunkSize) {
            let chunk = Array(bookIds[i..<min(i + chunkSize, bookIds.count)])
            let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
            try _db.execute(
                query: "DELETE FROM reading_entries WHERE book_id IN (\(placeholders));",
                parameters: chunk
            )
        }
    }

    func saveHistoryOrder(_ order: [Int]) {
        try? transaction {
            try exec("DELETE FROM history_order;")
            for (position, bookId) in order.enumerated() {
                try exec("INSERT INTO history_order (position, book_id) VALUES (?, ?);", parameters: [position, bookId])
            }
        }
    }

    // MARK: - Load from Database

    func fetchEntries(byCkRecordIds ids: [String]) -> [ReadingEntry] {
        guard let _db, !ids.isEmpty else { return [] }
        var entries: [ReadingEntry] = []
        let chunkSize = 500
        for i in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[i..<min(i + chunkSize, ids.count)])
            let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
            let sql = "SELECT book_id, last_content_id, last_opened_at, favorited_at, position_updated_at, updated_at, is_favorite, ck_record_id FROM reading_entries WHERE ck_record_id IN (\(placeholders));"
            if let rows = try? _db.fetch(query: sql, parameters: chunk, mapping: { row -> ReadingEntry in
                ReadingEntry(
                    bookId: row.int(at: 0),
                    lastContentId: row.isNull(at: 1) ? nil : row.int(at: 1),
                    lastOpenedAt: row.isNull(at: 2) ? nil : Date(timeIntervalSince1970: row.double(at: 2)),
                    favoritedAt: row.isNull(at: 3) ? nil : Date(timeIntervalSince1970: row.double(at: 3)),
                    positionUpdatedAt: row.isNull(at: 4) ? nil : Date(timeIntervalSince1970: row.double(at: 4)),
                    updatedAt: Date(timeIntervalSince1970: row.double(at: 5)),
                    isFavorite: row.int(at: 6) != 0,
                    ckRecordId: row.string(at: 7)
                )
            }) {
                entries.append(contentsOf: rows)
            }
        }
        return entries
    }

    func loadFromDatabase() -> (entries: [ReadingEntry], historyOrder: [Int]) {
        guard let _db else { return ([], []) }

        let entries = (try? _db.fetch(query: "SELECT book_id, last_content_id, last_opened_at, favorited_at, position_updated_at, updated_at, is_favorite, ck_record_id FROM reading_entries;") { row -> ReadingEntry in
            ReadingEntry(
                bookId: row.int(at: 0),
                lastContentId: row.isNull(at: 1) ? nil : row.int(at: 1),
                lastOpenedAt: row.isNull(at: 2) ? nil : Date(timeIntervalSince1970: row.double(at: 2)),
                favoritedAt: row.isNull(at: 3) ? nil : Date(timeIntervalSince1970: row.double(at: 3)),
                positionUpdatedAt: row.isNull(at: 4) ? nil : Date(timeIntervalSince1970: row.double(at: 4)),
                updatedAt: Date(timeIntervalSince1970: row.double(at: 5)),
                isFavorite: row.int(at: 6) != 0,
                ckRecordId: row.string(at: 7)
            )
        }) ?? []

        let order = (try? _db.fetch(query: "SELECT book_id FROM history_order ORDER BY position;") { row -> Int in
            row.int(at: 0)
        }) ?? []

        return (entries, order)
    }

    // MARK: - Pending Sync (SQLite)

    func addPendingSync(ckRecordId: String, operation: String) {
        guard let _db else { return }
        do {
            if operation == "upload" {
                let count = try _db.fetch(
                    query: "SELECT COUNT(*) FROM sync_pending WHERE ck_record_id = ? AND operation = 'delete';",
                    parameters: [ckRecordId]
                ) { $0.int64(at: 0) }.first ?? 0
                if count > 0 { return } // Delete wins
            } else if operation == "delete" {
                try _db.execute(
                    query: "DELETE FROM sync_pending WHERE ck_record_id = ? AND operation = 'upload';",
                    parameters: [ckRecordId]
                )
            }
            try _db.execute(
                query: "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES (?, ?, ?);",
                parameters: [ckRecordId, operation, Int64(Date().timeIntervalSince1970)]
            )
        } catch {
            #if DEBUG
            print("HistoryDatabaseManager: addPendingSync error: \(error)")
            #endif
        }
    }

    func removePendingSync(ckRecordIds: [String]) {
        guard let _db, !ckRecordIds.isEmpty else { return }
        let chunkSize = 500
        for i in stride(from: 0, to: ckRecordIds.count, by: chunkSize) {
            let chunk = Array(ckRecordIds[i..<min(i + chunkSize, ckRecordIds.count)])
            let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
            try? _db.execute(
                query: "DELETE FROM sync_pending WHERE ck_record_id IN (\(placeholders));",
                parameters: chunk
            )
        }
    }

    func fetchPendingSync(operation: String) -> [String] {
        guard let _db else { return [] }
        return (try? _db.fetch(
            query: "SELECT ck_record_id FROM sync_pending WHERE operation = ? ORDER BY queued_at ASC;",
            parameters: [operation]
        ) { $0.string(at: 0) ?? "" }) ?? []
    }

    // MARK: - Migration: UserDefaults → SQLite

    func migrateFromUserDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationFlag) else { return }
        guard let _db else { return }

        // Migrate main entries
        if let data = UserDefaults.standard.data(forKey: legacyStorageKey),
           let stored = try? JSONDecoder().decode(StoredReadingEntries.self, from: data)
        {
            do {
                try _db.transaction {
                    for entry in stored.entries {
                        upsertEntry(entry)
                    }
                    // Preserve exact history order
                    for (position, bookId) in stored.historyOrder.enumerated() {
                        try exec("INSERT OR REPLACE INTO history_order (position, book_id) VALUES (?, ?);", parameters: [position, bookId])
                    }
                }
            } catch {
                #if DEBUG
                print("HistoryDatabaseManager: Migration failed: \(error)")
                #endif
                return // Don't mark as migrated if failed
            }
        }

        // Migrate pending sync
        if let upData = UserDefaults.standard.data(forKey: legacyPendingUploadsKey),
           let upList = try? JSONDecoder().decode([String].self, from: upData), !upList.isEmpty
        {
            let now = Int64(Date().timeIntervalSince1970)
            try? transaction {
                let chunkSize = 300 // 3 params per entry (3 * 300 = 900)
                for i in stride(from: 0, to: upList.count, by: chunkSize) {
                    let chunk = Array(upList[i..<min(i + chunkSize, upList.count)])
                    let placeholders = chunk.map { _ in "(?, 'upload', ?)" }.joined(separator: ",")
                    var params = [Any]()
                    for ckId in chunk {
                        params.append(contentsOf: [ckId, now])
                    }
                    try _db.execute(
                        query: "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES \(placeholders);",
                        parameters: params
                    )
                }
            }
        }

        if let delData = UserDefaults.standard.data(forKey: legacyPendingDeletesKey),
           let delList = try? JSONDecoder().decode([String].self, from: delData), !delList.isEmpty
        {
            let now = Int64(Date().timeIntervalSince1970)
            try? transaction {
                let chunkSize = 300 // 3 params per entry
                for i in stride(from: 0, to: delList.count, by: chunkSize) {
                    let chunk = Array(delList[i..<min(i + chunkSize, delList.count)])
                    let placeholders = chunk.map { _ in "(?, 'delete', ?)" }.joined(separator: ",")
                    var params = [Any]()
                    for ckId in chunk {
                        params.append(contentsOf: [ckId, now])
                    }
                    try _db.execute(
                        query: "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES \(placeholders);",
                        parameters: params
                    )
                }
            }
        }

        // Mark migrated and delete old UserDefaults data
        UserDefaults.standard.set(true, forKey: migrationFlag)
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        UserDefaults.standard.removeObject(forKey: legacyPendingUploadsKey)
        UserDefaults.standard.removeObject(forKey: legacyPendingDeletesKey)

        #if DEBUG
        print("HistoryDatabaseManager: Successfully migrated from UserDefaults to SQLite")
        #endif
    }
}

/// Legacy struct — used only for migration from UserDefaults
private struct StoredReadingEntries: Codable {
    let historyOrder: [Int]
    let entries: [ReadingEntry]
}
