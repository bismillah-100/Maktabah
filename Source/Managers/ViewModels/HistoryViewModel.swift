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

    /// Legacy UserDefaults keys
    private let legacyHistoryKey = "iOSReadingEntries"

    /// Debounce for batched CloudKit deletions
    private var pendingCloudKitDeletes: Set<String> = []
    private var deleteDebounceTask: Task<Void, Never>?

    var historyBookIds: [Int] {
        get { historyOrder }
        set {
            historyOrder = Array(newValue.prefix(maxHistoryCount))
            pruneOrphanedEntries()
            HistoryDatabaseManager.shared.saveHistoryOrder(historyOrder)
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
        HistoryDatabaseManager.shared.setupDatabase()
        HistoryDatabaseManager.shared.migrateFromUserDefaultsIfNeeded()
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

    // MARK: - Load from Database

    private func loadFromDatabase() {
        let data = HistoryDatabaseManager.shared.loadFromDatabase()
        entriesByBookId = Dictionary(uniqueKeysWithValues: data.entries.map { ($0.bookId, $0) })
        historyOrder = data.historyOrder
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
        if let ckId = entry.ckRecordId {
            try? HistoryDatabaseManager.shared.addPendingSync(ckRecordId: ckId, operation: "upload")
        }
        HistoryDatabaseManager.shared.upsertEntry(entry)
        HistoryDatabaseManager.shared.saveHistoryOrder(historyOrder)
        loadBooksData()

        CloudKitSyncManager.shared.uploadHistory(entries: [entry], trackPending: false)
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

            if let ckId = entry.ckRecordId {
                try? HistoryDatabaseManager.shared.addPendingSync(ckRecordId: ckId, operation: "upload")
            }
            // Hanya simpan ke DB — tidak reload UI library (tidak ada perubahan visible)
            HistoryDatabaseManager.shared.upsertEntry(entry)
            CloudKitSyncManager.shared.uploadHistory(entries: [entry], trackPending: false)
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
        if let ckId = entry.ckRecordId {
            try? HistoryDatabaseManager.shared.addPendingSync(ckRecordId: ckId, operation: "upload")
        }
        HistoryDatabaseManager.shared.upsertEntry(entry)
        loadBooksData()

        CloudKitSyncManager.shared.uploadHistory(entries: [entry], trackPending: false)
    }

    func removeHistory(for bookId: Int) {
        historyOrder.removeAll { $0 == bookId }
        if var entry = entriesByBookId[bookId] {
            if entry.isFavorite {
                entry.lastOpenedAt = nil
                entry.updatedAt = Date()
                entriesByBookId[bookId] = entry

                let upserted = [entry]
                let order = historyOrder

                DispatchQueue.global(qos: .background).async {
                    do {
                        try HistoryDatabaseManager.shared.saveCloudKitChanges(deletedIds: [], upsertedEntries: upserted, finalOrder: order)
                        DispatchQueue.main.async {
                            self.loadBooksData()
                        }
                        CloudKitSyncManager.shared.uploadHistory(entries: upserted, trackPending: false)
                    } catch {
                        #if DEBUG
                        print("Failed to save removeHistory: \(error)")
                        #endif
                    }
                }
            } else {
                let ckId = entry.ckRecordId
                if let ckId {
                    try? HistoryDatabaseManager.shared.addPendingSync(ckRecordId: ckId, operation: "delete")
                }
                entriesByBookId.removeValue(forKey: bookId)

                let order = historyOrder
                let deletedIds = [bookId]

                DispatchQueue.global(qos: .background).async {
                    do {
                        try HistoryDatabaseManager.shared.transaction {
                            try HistoryDatabaseManager.shared.deleteEntries(bookIds: deletedIds)
                            if let ckId {
                                try HistoryDatabaseManager.shared.addPendingSync(ckRecordId: ckId, operation: "delete")
                            }
                            try HistoryDatabaseManager.shared.replaceHistoryOrder(order)
                        }
                        DispatchQueue.main.async {
                            self.loadBooksData()
                            if let ckId {
                                self.pendingCloudKitDeletes.insert(ckId)
                                self.triggerDeleteDebounce()
                            }
                        }
                    } catch {
                        #if DEBUG
                        print("Failed to save removeHistory: \(error)")
                        #endif
                    }
                }
            }
        }
    }

    private func triggerDeleteDebounce() {
        deleteDebounceTask?.cancel()
        deleteDebounceTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self, !pendingCloudKitDeletes.isEmpty else { return }
                let idsToDelete = Array(pendingCloudKitDeletes)
                pendingCloudKitDeletes.removeAll()
                CloudKitSyncManager.shared.delete(ckRecordIds: idsToDelete, target: .history, trackPending: false)
            }
        }
    }

    func clearHistory() {
        let historyIdsToRemove = historyOrder
        historyOrder.removeAll()

        var ckIdsToDelete = [String]()
        var upserted = [ReadingEntry]()
        var deletedIds = [Int]()

        for bookId in historyIdsToRemove {
            if var entry = entriesByBookId[bookId] {
                if entry.isFavorite {
                    entry.lastOpenedAt = nil
                    entry.updatedAt = Date()
                    entriesByBookId[bookId] = entry
                    upserted.append(entry)
                } else {
                    if let ckId = entry.ckRecordId {
                        ckIdsToDelete.append(ckId)
                    }
                    entriesByBookId.removeValue(forKey: bookId)
                    deletedIds.append(bookId)
                }
            }
        }

        let order = historyOrder
        let ckIdsToDeleteSafe = ckIdsToDelete

        DispatchQueue.global(qos: .background).async {
            do {
                try HistoryDatabaseManager.shared.transaction {
                    try HistoryDatabaseManager.shared.deleteEntries(bookIds: deletedIds, trackPending: false)
                    for ckId in ckIdsToDeleteSafe {
                        try HistoryDatabaseManager.shared.addPendingSync(ckRecordId: ckId, operation: "delete")
                    }
                    try HistoryDatabaseManager.shared.upsertEntries(upserted)
                    try HistoryDatabaseManager.shared.replaceHistoryOrder(order)
                }
                DispatchQueue.main.async {
                    self.loadBooksData()
                }
                if !upserted.isEmpty {
                    CloudKitSyncManager.shared.uploadHistory(entries: upserted, trackPending: false)
                }
                if !ckIdsToDeleteSafe.isEmpty {
                    CloudKitSyncManager.shared.delete(ckRecordIds: ckIdsToDeleteSafe, target: .history, trackPending: false)
                }
            } catch {
                #if DEBUG
                print("Failed to save clearHistory: \(error)")
                #endif
            }
        }
    }

    func isFavorite(_ bookId: Int) -> Bool {
        entriesByBookId[bookId]?.isFavorite ?? false
    }

    // MARK: - Pruning

    @discardableResult
    private func pruneOrphanedEntries(deleteFromDB: Bool = true) -> [Int] {
        let historySet = Set(historyOrder)
        let toRemove = entriesByBookId.keys.filter { bookId in
            let entry = entriesByBookId[bookId]
            let isFav = entry?.isFavorite ?? false
            let hasHistory = historySet.contains(bookId)
            return !isFav && !hasHistory
        }
        var removedIds = [Int]()
        var ckIdsToDelete = [String]()
        for bookId in toRemove {
            if let ckId = entriesByBookId[bookId]?.ckRecordId {
                ckIdsToDelete.append(ckId)
                pendingCloudKitDeletes.insert(ckId)
            }
            
            entriesByBookId.removeValue(forKey: bookId)
            removedIds.append(bookId)
        }

        if deleteFromDB && !removedIds.isEmpty {
            DispatchQueue.global(qos: .background).async {
                do {
                    try HistoryDatabaseManager.shared.transaction {
                        try HistoryDatabaseManager.shared.deleteEntries(bookIds: removedIds)
                        for ckId in ckIdsToDelete {
                        try HistoryDatabaseManager.shared.addPendingSync(ckRecordId: ckId, operation: "delete")
                        }
                    }
                    if !ckIdsToDelete.isEmpty {
                        DispatchQueue.main.async {
                            self.triggerDeleteDebounce()
                        }
                    }
                } catch {
                    #if DEBUG
                    print("Failed to save pruneOrphanedEntries: \(error)")
                    #endif
                }
            }
        } else if !ckIdsToDelete.isEmpty {
            triggerDeleteDebounce()
        }

        return removedIds
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

            var deletedIds = [Int]()
            for bookId in bookIdsToDelete {
                entriesByBookId.removeValue(forKey: bookId)
                historyOrder.removeAll(where: { $0 == bookId })
                deletedIds.append(bookId)
                didChange = true
            }

            // Updates/Insertions
            var upsertedEntries = [ReadingEntry]()
            for remoteEntry in entriesToSave {
                if let localEntry = entriesByBookId[remoteEntry.bookId] {
                    let localModified = localEntry.updatedAt.timeIntervalSince1970
                    let remoteModified = remoteEntry.updatedAt.timeIntervalSince1970

                    if remoteModified > localModified {
                        entriesByBookId[remoteEntry.bookId] = remoteEntry
                        upsertedEntries.append(remoteEntry)
                        didChange = true
                    }
                } else {
                    entriesByBookId[remoteEntry.bookId] = remoteEntry
                    upsertedEntries.append(remoteEntry)
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

                let prunedIds = pruneOrphanedEntries(deleteFromDB: false)
                deletedIds.append(contentsOf: prunedIds)

                let finalOrder = historyOrder
                loadBooksData()

                DispatchQueue.global(qos: .background).async {
                    do {
                        try HistoryDatabaseManager.shared.saveCloudKitChanges(deletedIds: deletedIds, upsertedEntries: upsertedEntries, finalOrder: finalOrder)
                    } catch {
                        #if DEBUG
                        print("Failed to applyCloudKitChanges: \(error)")
                        #endif
                    }
                }
            }
        }

        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async {
                block()
            }
        }
        return true
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
                didChange = true
            }
        }

        let toUpdateDb = backfilled
        if didChange {
            DispatchQueue.global(qos: .background).async {
                do {
                    try HistoryDatabaseManager.shared.saveUpsertedEntries(toUpdateDb)
                    DispatchQueue.main.async {
                        self.loadBooksData()
                    }
                } catch {
                    #if DEBUG
                    print("Failed to backfillCloudKitFields: \(error)")
                    #endif
                }
            }
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

            var newEntries = [ReadingEntry]()
            for entry in legacy.entries {
                if entriesByBookId[entry.bookId] == nil {
                    var migrated = entry
                    migrated.ckRecordId = String(entry.bookId)
                    entriesByBookId[entry.bookId] = migrated
                    newEntries.append(migrated)
                }
            }

            for hId in legacy.historyOrder {
                if !historyOrder.contains(hId) {
                    historyOrder.append(hId)
                }
            }

            let finalOrder = historyOrder
            let migratedEntries = Array(entriesByBookId.values).filter { $0.ckRecordId != nil }

            DispatchQueue.global(qos: .background).async {
                do {
                    try HistoryDatabaseManager.shared.saveMigrationChanges(newEntries: newEntries, finalOrder: finalOrder)
                    if !migratedEntries.isEmpty {
                        CloudKitSyncManager.shared.uploadHistory(entries: migratedEntries, debounce: false, trackPending: false)
                    }
                } catch {
                    #if DEBUG
                    print("Failed to migrateLegacyKVSData: \(error)")
                    #endif
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
        if let oldCkId = entry.ckRecordId {
            try? HistoryDatabaseManager.shared.addPendingSync(ckRecordId: oldCkId, operation: "delete")
        }
        HistoryDatabaseManager.shared.deleteEntry(bookId: oldId)
        if let ckId = migrated.ckRecordId {
            try? HistoryDatabaseManager.shared.addPendingSync(ckRecordId: ckId, operation: "upload")
        }
        HistoryDatabaseManager.shared.upsertEntry(migrated)
        HistoryDatabaseManager.shared.saveHistoryOrder(historyOrder)

        // Hapus entry lama dari CloudKit
        if let oldCkId = entry.ckRecordId {
            CloudKitSyncManager.shared.delete(ckRecordIds: [oldCkId], target: .history, trackPending: false)
        }

        // Upload entry baru
        loadBooksData()
        CloudKitSyncManager.shared.uploadHistory(entries: [migrated], trackPending: false)
    }
}

/// Legacy struct — used only for migration from UserDefaults
private struct StoredReadingEntries: Codable {
    let historyOrder: [Int]
    let entries: [ReadingEntry]
}
