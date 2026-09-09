import Foundation
import Observation
import SwiftUI

@Observable
class HistoryViewModel: ViewModelBase {
    static let shared = HistoryViewModel()

    var entriesByBookId: [Int: ReadingEntry] = [:]
    var historyOrder: [Int] = []

    var historyBooks: [BooksData] = []
    var favoriteBooks: [BooksData] = []
    var searchText: String = ""

    func filterBooks(_ books: [BooksData]) -> [BooksData] {
        guard !searchText.isEmpty else { return books }
        let normalizedSearchText = searchText.normalizeArabic(false)
        return books.filter { book in
            book.book.normalizeArabic(false).localizedStandardContains(normalizedSearchText)
        }
    }

    var filteredFavorites: [BooksData] {
        filterBooks(favoriteBooks)
    }

    var filteredHistory: [BooksData] {
        filterBooks(historyBooks)
    }

    let maxHistoryCount = 50

    /// Legacy UserDefaults keys
    let legacyHistoryKey = "iOSReadingEntries"

    /// Debounce for batched CloudKit deletions
    var pendingCloudKitDeletes: Set<String> = []
    var deleteDebounceTask: Task<Void, Never>?

    private var saveDebounceTask: Task<Void, Never>?
    private var reloadDebounceTask: Task<Void, Never>?

    var historyBookIds: [Int] {
        get { historyOrder }
        set {
            historyOrder = Array(newValue.prefix(maxHistoryCount))
            pruneOrphanedEntries()
            scheduleSave()
            loadBooksData()
            notifyHistoryChanged()
        }
    }

    private func scheduleSave() {
        saveDebounceTask?.cancel()
        let order = historyOrder
        saveDebounceTask = Task.detached {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            HistoryDatabaseManager.shared.saveHistoryOrder(order)
            await MainActor.run { [weak self] in
                self?.saveDebounceTask = nil
            }
        }
    }

    private func scheduleReloadBooksData() {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.loadBooksData()
            self?.reloadDebounceTask = nil
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
                if lDate != rDate {
                    return lDate > rDate
                }
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

        for name in [Notification.Name.bookIntegrated, .booksChanged] {
            addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleReloadBooksData()
                }
            }
        }

        enableBookIdMigrationObserver()
    }

    override func migrateBookId(from oldId: Int, to newId: Int) {
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
        notifyHistoryChanged()
        CloudKitSyncManager.shared.uploadHistory(entries: [migrated], trackPending: false)
    }

    // MARK: - Notifications

    func notifyHistoryChanged() {
        NotificationCenter.default.post(name: .historyDidChange, object: self)
    }
}
