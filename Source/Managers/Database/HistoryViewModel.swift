import Combine
import Foundation
import SwiftUI

struct ReadingEntry: Codable, Identifiable, Hashable {
    let bookId: Int
    var lastContentId: Int?
    var lastOpenedAt: Date?
    var favoritedAt: Date?
    var positionUpdatedAt: Date?
    var updatedAt: Date
    var isFavorite: Bool

    var ckRecordId: String?

    var id: Int {
        bookId
    }
}

class HistoryViewModel: ViewModelBase, ObservableObject {
    static let shared = HistoryViewModel()

    @Published private(set) var entriesByBookId: [Int: ReadingEntry] = [:]
    @Published private(set) var historyOrder: [Int] = []

    @Published var historyBooks: [BooksData] = []
    @Published var favoriteBooks: [BooksData] = []
    @Published var searchText: String = ""

    var filteredFavorites: [BooksData] {
        if searchText.isEmpty { return favoriteBooks }
        let normalizedSearchText = searchText.normalizeArabic(false)
        return favoriteBooks.filter { book in
            book.book.normalizeArabic(false).localizedStandardContains(normalizedSearchText)
        }
    }

    var filteredHistory: [BooksData] {
        if searchText.isEmpty { return historyBooks }
        let normalizedSearchText = searchText.normalizeArabic(false)
        return historyBooks.filter { book in
            book.book.normalizeArabic(false).localizedStandardContains(normalizedSearchText)
        }
    }

    private let maxHistoryCount = 50

    /// Legacy UserDefaults keys — used only for migration
    private let legacyStorageKey = "CloudReadingEntries"
    private let legacyHistoryKey = "iOSReadingEntries"
    private let legacyPendingUploadsKey = "HistoryPendingUploads"
    private let legacyPendingDeletesKey = "HistoryPendingDeletes"
    private let migrationFlag = "HistoryVM_SQLiteMigrated"

    /// Debounce for batched CloudKit deletions
    private var pendingCloudKitDeletes: Set<String> = []
    private var deleteDebounceTask: Task<Void, Never>?

    // MARK: - Database

    private var _db: SQLiteDatabase?

    var historyBookIds: [Int] {
        get { historyOrder }
        set {
            historyOrder = Array(newValue.prefix(maxHistoryCount))
            pruneOrphanedEntries()
            saveHistoryOrder()
            loadBooksData()
        }
    }

    var favoriteBookIds: [Int] {
        entriesByBookId.values
            .filter(\.isFavorite)
            .sorted { lhs, rhs in
                // Gunakan favoritedAt atau favoriteUpdatedAt.
                // Jangan gunakan updatedAt/lastOpenedAt karena nilainya akan berubah
                // saat user membaca buku, membuat posisinya naik ke atas.
                let lDate = lhs.favoritedAt ?? Date.distantPast
                let rDate = rhs.favoritedAt ?? Date.distantPast
                if lDate != rDate { return lDate > rDate }
                return lhs.bookId < rhs.bookId
            }
            .map(\.bookId)
    }

    override init() {
        super.init()
        setupDatabase()
        migrateFromUserDefaultsIfNeeded()
        migrateLegacyKVSDataIfNeeded()
        loadFromDatabase()
        backfillCloudKitFieldsIfNeeded()
        loadBooksData()

        addObserver(
            forName: .bookIntegrated,
            object: nil, queue: .main
        ) { [weak self] _ in self?.loadBooksData() }

        addObserver(
            forName: .booksChanged,
            object: nil, queue: .main
        ) { [weak self] _ in self?.loadBooksData() }

        addObserver(
            forName: .bookIdMigrated,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let oldId = userInfo["oldId"] as? Int,
                  let newId = userInfo["newId"] as? Int else { return }
            self?.migrateBookId(from: oldId, to: newId)
        }
    }

    // MARK: - Database Setup

    private func setupDatabase() {
        guard let folderURL = AppConfig.folder(for: AppConfig.annotationsAndResultsFolder) else {
            #if DEBUG
            print("HistoryViewModel: No folder URL available for History database")
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
            print("HistoryViewModel: Failed to setup database: \(error)")
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
                print("HistoryViewModel: failed to enable WAL mode, current: \(mode ?? "unknown")")
            }
            #endif
        } catch {
            #if DEBUG
            print("HistoryViewModel: error enabling WAL mode: \(error)")
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

    private func transaction(_ block: () throws -> Void) throws {
        guard let _db else { return }
        try _db.transaction(block)
    }

    // MARK: - Core CRUD

    private func upsertEntry(_ entry: ReadingEntry) {
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

    private func deleteEntry(bookId: Int) {
        try? exec("DELETE FROM reading_entries WHERE book_id = ?;", parameters: [bookId])
    }

    private func saveHistoryOrder() {
        try? transaction {
            try exec("DELETE FROM history_order;")
            for (position, bookId) in historyOrder.enumerated() {
                try exec("INSERT INTO history_order (position, book_id) VALUES (?, ?);", parameters: [position, bookId])
            }
        }
    }

    // MARK: - Load from Database

    private func loadFromDatabase() {
        guard let _db else { return }

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

        entriesByBookId = Dictionary(uniqueKeysWithValues: entries.map { ($0.bookId, $0) })

        historyOrder = (try? _db.fetch(query: "SELECT book_id FROM history_order ORDER BY position;") { row -> Int in
            row.int(at: 0)
        }) ?? []
    }

    // MARK: - Core Operations

    func addBookToHistory(_ bookId: Int) {
        guard DatabaseManager.shared.bookExists(id: bookId) else { return }

        var entry = entriesByBookId[bookId] ?? ReadingEntry(
            bookId: bookId,
            lastContentId: nil,
            lastOpenedAt: nil,
            favoritedAt: nil,
            positionUpdatedAt: nil,
            updatedAt: Date(),
            isFavorite: false,
            ckRecordId: String(bookId)
        )

        entry.lastOpenedAt = Date()
        entry.updatedAt = Date()

        if entry.ckRecordId == nil {
            entry.ckRecordId = String(bookId)
        }

        entriesByBookId[bookId] = entry
        historyOrder.removeAll { $0 == bookId }
        historyOrder.insert(bookId, at: 0)

        if historyOrder.count > maxHistoryCount {
            historyOrder = Array(historyOrder.prefix(maxHistoryCount))
        }

        pruneOrphanedEntries()
        upsertEntry(entry)
        saveHistoryOrder()
        loadBooksData()

        CloudKitSyncManager.shared.uploadHistory(entries: [entry])
    }

    func updateLastContentId(_ contentId: Int, for bookId: Int) {
        if var entry = entriesByBookId[bookId] {
            entry.lastContentId = contentId
            entry.positionUpdatedAt = Date()
            entry.updatedAt = Date()
            if entry.ckRecordId == nil {
                entry.ckRecordId = String(bookId)
            }
            entriesByBookId[bookId] = entry

            // Hanya simpan ke DB — tidak reload UI library (tidak ada perubahan visible)
            upsertEntry(entry)

            if let ckId = entry.ckRecordId {
                addPendingSync(ckRecordId: ckId, operation: "upload")
            }
            CloudKitSyncManager.shared.uploadHistory(entries: [entry])
        } else {
            addBookToHistory(bookId)
            updateLastContentId(contentId, for: bookId)
        }
    }

    func toggleFavorite(_ bookId: Int) {
        guard DatabaseManager.shared.bookExists(id: bookId) else { return }

        var entry = entriesByBookId[bookId] ?? ReadingEntry(
            bookId: bookId,
            lastContentId: nil,
            lastOpenedAt: nil,
            favoritedAt: nil,
            positionUpdatedAt: nil,
            updatedAt: Date(),
            isFavorite: false,
            ckRecordId: String(bookId)
        )

        entry.isFavorite.toggle()
        let now = Date()
        if entry.isFavorite {
            entry.favoritedAt = now
        }
        entry.updatedAt = now
        if entry.ckRecordId == nil {
            entry.ckRecordId = String(bookId)
        }

        entriesByBookId[bookId] = entry
        upsertEntry(entry)
        loadBooksData()

        CloudKitSyncManager.shared.uploadHistory(entries: [entry])
    }

    func removeHistory(for bookId: Int) {
        historyOrder.removeAll { $0 == bookId }
        if var entry = entriesByBookId[bookId] {
            if entry.isFavorite {
                // Entry masih ada tapi bukan history lagi — upload perubahan
                entry.lastOpenedAt = nil
                entry.updatedAt = Date()
                entriesByBookId[bookId] = entry
                upsertEntry(entry)
                saveHistoryOrder()
                loadBooksData()
                CloudKitSyncManager.shared.uploadHistory(entries: [entry])
            } else {
                // Entry dihapus total — delete di CloudKit, tidak perlu upload
                let ckId = entry.ckRecordId
                entriesByBookId.removeValue(forKey: bookId)
                deleteEntry(bookId: bookId)
                saveHistoryOrder()
                loadBooksData()
                if let ckId {
                    addPendingSync(ckRecordId: ckId, operation: "delete")
                    pendingCloudKitDeletes.insert(ckId)

                    deleteDebounceTask?.cancel()
                    deleteDebounceTask = Task {
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }

                        await MainActor.run { [weak self] in
                            guard let self, !pendingCloudKitDeletes.isEmpty else { return }
                            let idsToDelete = Array(pendingCloudKitDeletes)
                            pendingCloudKitDeletes.removeAll()
                            CloudKitSyncManager.shared.delete(ckRecordIds: idsToDelete, target: .history)
                        }
                    }
                }
            }
        }
    }

    func clearHistory() {
        let historyIdsToRemove = historyOrder
        historyOrder.removeAll()

        var ckIdsToDelete = [String]()
        for bookId in historyIdsToRemove {
            if var entry = entriesByBookId[bookId] {
                if entry.isFavorite {
                    entry.lastOpenedAt = nil
                    entry.updatedAt = Date()
                    entriesByBookId[bookId] = entry
                    upsertEntry(entry)
                } else {
                    if let ckId = entry.ckRecordId {
                        ckIdsToDelete.append(ckId)
                    }
                    entriesByBookId.removeValue(forKey: bookId)
                    deleteEntry(bookId: bookId)
                }
            }
        }

        saveHistoryOrder()
        loadBooksData()

        if !ckIdsToDelete.isEmpty {
            CloudKitSyncManager.shared.delete(ckRecordIds: ckIdsToDelete, target: .history)
        }
    }

    func isFavorite(_ bookId: Int) -> Bool {
        entriesByBookId[bookId]?.isFavorite ?? false
    }

    // MARK: - Pruning

    private func pruneOrphanedEntries() {
        let historySet = Set(historyOrder)
        let toRemove = entriesByBookId.keys.filter { bookId in
            let entry = entriesByBookId[bookId]
            let isFav = entry?.isFavorite ?? false
            let hasHistory = historySet.contains(bookId)
            return !isFav && !hasHistory
        }
        for bookId in toRemove {
            entriesByBookId.removeValue(forKey: bookId)
            deleteEntry(bookId: bookId)
        }
    }

    private func loadBooksData() {
        let hIds = historyOrder
        let fIds = favoriteBookIds
        let allNeededIds = Set(hIds).union(Set(fIds))

        let books = LibraryDataManager.shared.getBook(Array(allNeededIds))
        let booksDict = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })

        historyBooks = hIds.compactMap { booksDict[$0] }
        favoriteBooks = fIds.compactMap { booksDict[$0] }
    }

    // MARK: - CloudKit Sync Support

    func getAllEntries() -> [ReadingEntry] {
        Array(entriesByBookId.values)
    }

    @discardableResult func applyCloudKitChanges(entriesToSave: [ReadingEntry], recordIdsToDelete: [String]) -> Bool {
        let block = { [weak self] in
            guard let self else { return }
            var didChange = false

            // Deletions
            let bookIdsToDelete = entriesByBookId.values
                .compactMap { entry -> Int? in
                    guard let ckId = entry.ckRecordId, recordIdsToDelete.contains(ckId) else { return nil }
                    return entry.bookId
                }

            for bookId in bookIdsToDelete {
                entriesByBookId.removeValue(forKey: bookId)
                deleteEntry(bookId: bookId)
                historyOrder.removeAll(where: { $0 == bookId })
                didChange = true
            }

            // Updates/Insertions
            for remoteEntry in entriesToSave {
                if let localEntry = entriesByBookId[remoteEntry.bookId] {
                    let localModified = localEntry.updatedAt.timeIntervalSince1970
                    let remoteModified = remoteEntry.updatedAt.timeIntervalSince1970

                    if remoteModified > localModified {
                        entriesByBookId[remoteEntry.bookId] = remoteEntry
                        upsertEntry(remoteEntry)
                        didChange = true
                    }
                } else {
                    entriesByBookId[remoteEntry.bookId] = remoteEntry
                    upsertEntry(remoteEntry)
                    didChange = true
                }
            }

            if didChange {
                // Sinkronkan urutan history di semua devices berdasarkan `lastOpenedAt`.
                let validHistoryEntries = entriesByBookId.values.filter { $0.lastOpenedAt != nil }
                let sortedIds = validHistoryEntries
                    .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
                    .map(\.bookId)
                historyOrder = Array(sortedIds.prefix(maxHistoryCount))

                pruneOrphanedEntries()
                saveHistoryOrder()
                loadBooksData()
            }
        }

        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync {
                block()
            }
        }
        return true
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
            print("HistoryViewModel: addPendingSync error: \(error)")
            #endif
        }
    }

    func removePendingSync(ckRecordIds: [String]) {
        guard let _db, !ckRecordIds.isEmpty else { return }
        let placeholders = ckRecordIds.map { _ in "?" }.joined(separator: ",")
        try? _db.execute(
            query: "DELETE FROM sync_pending WHERE ck_record_id IN (\(placeholders));",
            parameters: ckRecordIds
        )
    }

    func fetchPendingSync(operation: String) -> [String] {
        guard let _db else { return [] }
        return (try? _db.fetch(
            query: "SELECT ck_record_id FROM sync_pending WHERE operation = ? ORDER BY queued_at ASC;",
            parameters: [operation]
        ) { $0.string(at: 0) ?? "" }) ?? []
    }

    // MARK: - Migration: UserDefaults → SQLite

    private func migrateFromUserDefaultsIfNeeded() {
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
                print("HistoryViewModel: Migration failed: \(error)")
                #endif
                return // Don't mark as migrated if failed
            }
        }

        // Migrate pending sync
        if let upData = UserDefaults.standard.data(forKey: legacyPendingUploadsKey),
           let upList = try? JSONDecoder().decode([String].self, from: upData)
        {
            let now = Int64(Date().timeIntervalSince1970)
            for ckId in upList {
                try? _db.execute(
                    query: "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES (?, 'upload', ?);",
                    parameters: [ckId, now]
                )
            }
        }

        if let delData = UserDefaults.standard.data(forKey: legacyPendingDeletesKey),
           let delList = try? JSONDecoder().decode([String].self, from: delData)
        {
            let now = Int64(Date().timeIntervalSince1970)
            for ckId in delList {
                try? _db.execute(
                    query: "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES (?, 'delete', ?);",
                    parameters: [ckId, now]
                )
            }
        }

        // Mark migrated and delete old UserDefaults data
        UserDefaults.standard.set(true, forKey: migrationFlag)
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        UserDefaults.standard.removeObject(forKey: legacyPendingUploadsKey)
        UserDefaults.standard.removeObject(forKey: legacyPendingDeletesKey)

        #if DEBUG
        print("HistoryViewModel: Successfully migrated from UserDefaults to SQLite")
        #endif
    }

    // MARK: - KVS Migration (Legacy)

    func backfillCloudKitFieldsIfNeeded(completion: (([ReadingEntry]) -> Void)? = nil) {
        var backfilled = [ReadingEntry]()
        var didChange = false

        for (bookId, entry) in entriesByBookId {
            if entry.ckRecordId == nil || entry.ckRecordId?.hasPrefix("history_") == true {
                var updated = entry
                updated.ckRecordId = String(bookId)
                entriesByBookId[bookId] = updated
                backfilled.append(updated)
                upsertEntry(updated)
                didChange = true
            }
        }

        if didChange {
            loadBooksData()
        }

        completion?(backfilled)
    }

    private func migrateLegacyKVSDataIfNeeded() {
        if UserDefaults.standard.bool(forKey: "HistoryViewModel_LegacyMigrated_v2") { return }

        let kvs = NSUbiquitousKeyValueStore.default
        var legacyPayload: StoredReadingEntries?

        if let data = UserDefaults.standard.data(forKey: legacyHistoryKey),
           let decoded = try? JSONDecoder().decode(StoredReadingEntries.self, from: data)
        {
            legacyPayload = decoded
        } else if let data = kvs.data(forKey: legacyHistoryKey),
                  let decoded = try? JSONDecoder().decode(StoredReadingEntries.self, from: data)
        {
            legacyPayload = decoded
        }

        if let legacy = legacyPayload {
            // Load current state from DB first
            loadFromDatabase()

            for entry in legacy.entries {
                if entriesByBookId[entry.bookId] == nil {
                    var migrated = entry
                    migrated.ckRecordId = String(entry.bookId)
                    entriesByBookId[entry.bookId] = migrated
                    upsertEntry(migrated)
                }
            }

            for hId in legacy.historyOrder {
                if !historyOrder.contains(hId) {
                    historyOrder.append(hId)
                }
            }

            saveHistoryOrder()

            // Upload semua entry hasil migrasi ke CloudKit (satu kali, batch)
            let migratedEntries = Array(entriesByBookId.values).filter { $0.ckRecordId != nil }
            if !migratedEntries.isEmpty {
                Task {
                    CloudKitSyncManager.shared.uploadHistory(entries: migratedEntries, debounce: false)
                }
            }
        }

        UserDefaults.standard.set(true, forKey: "HistoryViewModel_LegacyMigrated_v2")
    }

    func migrateBookId(from oldId: Int, to newId: Int) {
        guard let entry = entriesByBookId.removeValue(forKey: oldId) else { return }
        let migrated = ReadingEntry(
            bookId: newId,
            lastContentId: entry.lastContentId,
            lastOpenedAt: entry.lastOpenedAt,
            favoritedAt: entry.favoritedAt,
            positionUpdatedAt: entry.positionUpdatedAt,
            updatedAt: Date(),
            isFavorite: entry.isFavorite,
            ckRecordId: String(newId)
        )
        entriesByBookId[newId] = migrated
        if let idx = historyOrder.firstIndex(of: oldId) {
            historyOrder[idx] = newId
        }

        // Update DB: delete old, insert new
        deleteEntry(bookId: oldId)
        upsertEntry(migrated)
        saveHistoryOrder()

        // Hapus entry lama dari CloudKit
        if let oldCkId = entry.ckRecordId {
            CloudKitSyncManager.shared.delete(ckRecordIds: [oldCkId], target: .history)
        }

        // Upload entry baru
        loadBooksData()
        CloudKitSyncManager.shared.uploadHistory(entries: [migrated])
    }
}

/// Legacy struct — used only for migration from UserDefaults
private struct StoredReadingEntries: Codable {
    let historyOrder: [Int]
    let entries: [ReadingEntry]
}
