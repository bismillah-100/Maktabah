//
//  HistoryDatabaseManager.swift
//  Maktabah
//
//  Created by MacBook on 05/12/25.
//

import Foundation

class HistoryDatabaseManager: SyncPendingManaging {
    static let shared = HistoryDatabaseManager()

    private var _db: SQLiteDatabase?

    /// Legacy UserDefaults keys — used only for migration
    private let legacyStorageKey = "CloudReadingEntries"
    private let legacyPendingUploadsKey = "HistoryPendingUploads"
    private let legacyPendingDeletesKey = "HistoryPendingDeletes"
    private let migrationFlag = "HistoryVM_SQLiteMigrated"

    var syncPendingStore: SyncPendingStore?

    private init() {
        setupDatabase()
    }

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
            let db = try SQLiteDatabase(path: url.path)
            db.enableWALMode()
            db.checkpoint() // Ensure WAL is committed and truncated
            _db = db
            syncPendingStore = SyncPendingStore(database: db)
            try createTables()
        } catch {
            #if DEBUG
            print("HistoryDatabaseManager: Failed to setup database: \(error)")
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

        try syncPendingStore?.createTable()

        try exec("CREATE INDEX IF NOT EXISTS idx_re_favorite ON reading_entries (is_favorite, favorited_at);")
        try exec("CREATE INDEX IF NOT EXISTS idx_re_ck_record_id ON reading_entries (ck_record_id);")
    }

    // MARK: - SQLite Helpers

    private func exec(_ sql: String, parameters: [Any] = []) throws {
        guard let _db else { return }
        try _db.execute(query: sql, parameters: parameters)
    }

    func replaceHistoryOrder(_ order: [Int]) throws {
        try exec("DELETE FROM history_order;")
        for (position, bookId) in order.enumerated() {
            try exec("INSERT INTO history_order (position, book_id) VALUES (?, ?);", parameters: [position, bookId])
        }
    }

    func transaction(_ block: () throws -> Void) throws {
        guard let _db else { return }
        try _db.transaction(block)
    }

    // MARK: - Core CRUD

    func upsertEntry(_ entry: ReadingEntry) {
        try? upsertEntries([entry])
    }

    func upsertEntries(_ entries: [ReadingEntry], trackPending: Bool = true) throws {
        guard let _db, !entries.isEmpty else { return }
        let chunkSize = 50 // SQLite max params is 999. We have 8 params per entry. 50 * 8 = 400.

        try transaction {
            for chunk in entries.chunked(into: chunkSize) {
                let placeholders = String(repeating: "(?, ?, ?, ?, ?, ?, ?, ?),", count: chunk.count).dropLast()
                let sql = "INSERT OR REPLACE INTO reading_entries (book_id, last_content_id, last_opened_at, favorited_at, position_updated_at, updated_at, is_favorite, ck_record_id) VALUES " + String(placeholders) + ";"

                var params = [Any]()
                for entry in chunk {
                    params.append(contentsOf: entryParams(entry))
                }
                try _db.execute(query: sql, parameters: params)

                if trackPending {
                    for entry in chunk {
                        if let ckId = entry.ckRecordId {
                            try self.addPendingSync(ckRecordId: ckId, operation: "upload")
                        }
                    }
                }
            }
        }
    }

    func deleteEntry(bookId: Int) {
        try? deleteEntries(bookIds: [bookId])
    }

    func deleteEntries(bookIds: [Int], trackPending: Bool = true) throws {
        guard let _db, !bookIds.isEmpty else { return }
        try transaction {
            for chunk in bookIds.chunked(into: 500) {
                let placeholders = String(repeating: "?,", count: chunk.count).dropLast()

                // Fetch ckRecordIds first
                var ckIds: [String] = []
                if trackPending {
                    let ckIdSql = "SELECT ck_record_id FROM reading_entries WHERE book_id IN (" + String(placeholders) + ");"
                    ckIds = try _db.fetch(query: ckIdSql, parameters: chunk, mapping: { $0.string(at: 0) }).compactMap { $0 }
                }

                try _db.execute(
                    query: "DELETE FROM reading_entries WHERE book_id IN (" + String(placeholders) + ");",
                    parameters: chunk
                )

                if trackPending {
                    for ckId in ckIds {
                        try self.addPendingSync(ckRecordId: ckId, operation: "delete")
                    }
                }
            }
        }
    }

    private func entryParams(_ entry: ReadingEntry) -> [Any] {
        [
            entry.bookId,
            entry.lastContentId as Any? ?? NSNull(),
            entry.lastOpenedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
            entry.favoritedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
            entry.positionUpdatedAt?.timeIntervalSince1970 as Any? ?? NSNull(),
            entry.updatedAt.timeIntervalSince1970,
            entry.isFavorite ? 1 : 0,
            entry.ckRecordId as Any? ?? NSNull(),
        ]
    }

    func saveHistoryOrder(_ order: [Int]) {
        do {
            try transaction {
                try replaceHistoryOrder(order)
            }
        } catch {
            #if DEBUG
            print("HistoryDatabaseManager: saveHistoryOrder failed: \(error)")
            #endif
        }
    }

    func saveCloudKitChanges(deletedIds: [Int], upsertedEntries: [ReadingEntry], finalOrder: [Int]) throws {
        try transaction {
            try deleteEntries(bookIds: deletedIds, trackPending: false)
            try upsertEntries(upsertedEntries, trackPending: false)
            try replaceHistoryOrder(finalOrder)
        }
    }

    func saveMigrationChanges(newEntries: [ReadingEntry], finalOrder: [Int]) throws {
        try transaction {
            try upsertEntries(newEntries)
            try replaceHistoryOrder(finalOrder)
        }
    }

    func saveUpsertedEntries(_ entries: [ReadingEntry]) throws {
        try transaction {
            try upsertEntries(entries)
        }
    }

    // MARK: - Load from Database

    func fetchEntries(byCkRecordIds ids: [String]) -> [ReadingEntry] {
        guard let _db, !ids.isEmpty else { return [] }
        var entries: [ReadingEntry] = []
        for chunk in ids.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let sql = "SELECT book_id, last_content_id, last_opened_at, favorited_at, position_updated_at, updated_at, is_favorite, ck_record_id FROM reading_entries WHERE ck_record_id IN (\(placeholders));"
            if let rows = try? _db.fetch(query: sql, parameters: chunk, mapping: ReadingEntry.init(row:)) {
                entries.append(contentsOf: rows)
            }
        }
        return entries
    }

    func loadFromDatabase() -> (entries: [ReadingEntry], historyOrder: [Int]) {
        guard let _db else { return ([], []) }

        let sql = "SELECT book_id, last_content_id, last_opened_at, favorited_at, position_updated_at, updated_at, is_favorite, ck_record_id FROM reading_entries;"
        let entries = (try? _db.fetch(query: sql, mapping: ReadingEntry.init(row:))) ?? []

        let order = (try? _db.fetch(query: "SELECT book_id FROM history_order ORDER BY position;") { row -> Int in
            row.int(at: 0)
        }) ?? []

        return (entries, order)
    }

    // MARK: - Migration: UserDefaults → SQLite

    func migrateFromUserDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationFlag) else { return }
        guard _db != nil else { return }

        guard migrateStoredReadingEntries() else { return }

        migratePendingSyncList(key: legacyPendingUploadsKey, operation: "upload")
        migratePendingSyncList(key: legacyPendingDeletesKey, operation: "delete")

        // Mark migrated and delete old UserDefaults data
        UserDefaults.standard.set(true, forKey: migrationFlag)
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        UserDefaults.standard.removeObject(forKey: legacyPendingUploadsKey)
        UserDefaults.standard.removeObject(forKey: legacyPendingDeletesKey)

        #if DEBUG
        print("HistoryDatabaseManager: Successfully migrated from UserDefaults to SQLite")
        #endif
    }

    private func migrateStoredReadingEntries() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: legacyStorageKey),
              let stored = try? JSONDecoder().decode(StoredReadingEntries.self, from: data),
              let _db else { return true }

        do {
            try _db.transaction {
                for entry in stored.entries {
                    upsertEntry(entry)
                }
                for (position, bookId) in stored.historyOrder.enumerated() {
                    try exec("INSERT OR REPLACE INTO history_order (position, book_id) VALUES (?, ?);", parameters: [position, bookId])
                }
            }
            return true
        } catch {
            #if DEBUG
            print("HistoryDatabaseManager: Migration failed: \(error)")
            #endif
            return false
        }
    }

    private func migratePendingSyncList(key: String, operation: String) {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([String].self, from: data),
              !list.isEmpty,
              let _db else { return }

        let now = Int64(Date().timeIntervalSince1970)
        do {
            try transaction {
                for chunk in list.chunked(into: 300) {
                    let placeholders = String(repeating: "(?, '\(operation)', ?),", count: chunk.count).dropLast()
                    var params = [Any]()
                    for ckId in chunk {
                        params.append(contentsOf: [ckId, now])
                    }
                    try _db.execute(
                        query: "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES " + String(placeholders) + ";",
                        parameters: params
                    )
                }
            }
        } catch {
            #if DEBUG
            print("HistoryDatabaseManager: \(key) migration failed: \(error)")
            #endif
        }
    }
}

/// Legacy struct — used only for migration from UserDefaults
private struct StoredReadingEntries: Codable {
    let historyOrder: [Int]
    let entries: [ReadingEntry]
}

extension ReadingEntry {
    init(row: SQLiteRow) {
        self.init(
            bookId: row.int(at: 0),
            lastContentId: row.isNull(at: 1) ? nil : row.int(at: 1),
            lastOpenedAt: row.isNull(at: 2) ? nil : Date(timeIntervalSince1970: row.double(at: 2)),
            favoritedAt: row.isNull(at: 3) ? nil : Date(timeIntervalSince1970: row.double(at: 3)),
            positionUpdatedAt: row.isNull(at: 4) ? nil : Date(timeIntervalSince1970: row.double(at: 4)),
            updatedAt: Date(timeIntervalSince1970: row.double(at: 5)),
            isFavorite: row.int(at: 6) != 0,
            ckRecordId: row.string(at: 7)
        )
    }
}
