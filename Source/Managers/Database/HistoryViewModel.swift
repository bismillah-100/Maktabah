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

private struct StoredReadingEntries: Codable {
    let historyOrder: [Int]
    let entries: [ReadingEntry]
}

class HistoryViewModel: ObservableObject {
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
    private let storageKey = "CloudReadingEntries"

    /// For syncing KVS to CloudKit
    private let legacyHistoryKey = "iOSReadingEntries"

    // Pending sync queue
    private var pendingUploads: Set<String> = []
    private var pendingDeletes: Set<String> = []
    private let pendingQueue = DispatchQueue(label: "com.maktabah.history.pendingQueue", attributes: .concurrent)

    /// Debounce upload saat navigasi halaman
    private var contentUpdateWorkItem: DispatchWorkItem?

    var historyBookIds: [Int] {
        get { historyOrder }
        set {
            historyOrder = Array(newValue.prefix(maxHistoryCount))
            pruneOrphanedEntries()
            persistAndReload(uploadEntry: nil)
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

    private init() {
        loadFromUserDefaults()
        loadPendingSync()

        // Ensure initial books are loaded
        loadBooksData()

        // Migrate legacy KVS data if needed
        migrateLegacyKVSDataIfNeeded()

        // Backfill missing CloudKit fields and upload to CloudKit
        backfillCloudKitFieldsIfNeeded()
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
        persistAndReload(uploadEntry: entry)
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

            // Hanya simpan ke disk — tidak reload UI library (tidak ada perubahan visible)
            persistToDiskOnly()

            // Debounce upload ke CloudKit: tunggu 3 detik idle sebelum kirim
            let capturedEntry = entry
            contentUpdateWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard self != nil else { return }
                #if DEBUG
                print("HistoryViewModel: debounced upload posisi buku \(bookId)")
                #endif
                CloudKitSyncManager.shared.uploadHistory(entries: [capturedEntry])
            }
            contentUpdateWorkItem = workItem
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3.0, execute: workItem)
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
        persistAndReload(uploadEntry: entry)
    }

    func removeHistory(for bookId: Int) {
        historyOrder.removeAll { $0 == bookId }
        if var entry = entriesByBookId[bookId] {
            if entry.isFavorite {
                // Entry masih ada tapi bukan history lagi — upload perubahan
                entry.lastOpenedAt = nil
                entry.updatedAt = Date()
                entriesByBookId[bookId] = entry
                persistAndReload(uploadEntry: entry)
            } else {
                // Entry dihapus total — delete di CloudKit, tidak perlu upload
                let ckId = entry.ckRecordId
                entriesByBookId.removeValue(forKey: bookId)
                persistAndReload(uploadEntry: nil)
                if let ckId {
                    CloudKitSyncManager.shared.delete(ckRecordIds: [ckId], target: .history)
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
                } else {
                    if let ckId = entry.ckRecordId {
                        ckIdsToDelete.append(ckId)
                    }
                    entriesByBookId.removeValue(forKey: bookId)
                }
            }
        }

        // Entry sudah dihapus — deletes ditangani di bawah, tidak perlu upload
        persistAndReload(uploadEntry: nil)

        if !ckIdsToDelete.isEmpty {
            CloudKitSyncManager.shared.delete(ckRecordIds: ckIdsToDelete, target: .history)
        }
    }

    func isFavorite(_ bookId: Int) -> Bool {
        entriesByBookId[bookId]?.isFavorite ?? false
    }

    // MARK: - Internal Load/Save

    private func currentPayload() -> StoredReadingEntries {
        StoredReadingEntries(
            historyOrder: historyOrder,
            entries: Array(entriesByBookId.values)
        )
    }

    private func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(StoredReadingEntries.self, from: data)
        {
            applyPayload(stored, persistToDisk: false)
        }
    }

    /// Persist ke disk + reload data buku di UI + upload satu entry ke CloudKit (jika ada).
    private func persistAndReload(uploadEntry: ReadingEntry? = nil) {
        let payload = currentPayload()
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }

        loadBooksData()

        if let entry = uploadEntry, entry.ckRecordId != nil {
            #if DEBUG
            print("HistoryViewModel: upload 1 entry (bookId=\(entry.bookId))")
            #endif
            CloudKitSyncManager.shared.uploadHistory(entries: [entry])
        }
    }

    /// Hanya simpan ke disk — tidak reload UI library, tidak upload ke CloudKit.
    /// Digunakan saat navigasi halaman agar tidak memicu observer di LibraryViewManager.
    private func persistToDiskOnly() {
        let payload = currentPayload()
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

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
        }
    }

    private func applyPayload(_ payload: StoredReadingEntries, persistToDisk: Bool) {
        entriesByBookId = Dictionary(uniqueKeysWithValues: payload.entries.map { ($0.bookId, $0) })
        historyOrder = payload.historyOrder
        pruneOrphanedEntries()

        if persistToDisk {
            persistAndReload(uploadEntry: nil)
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

    // MARK: - CloudKit Migration & Sync Support

    func getAllEntries() -> [ReadingEntry] {
        Array(entriesByBookId.values)
    }

    func applyCloudKitChanges(entriesToSave: [ReadingEntry], recordIdsToDelete: [String]) {
        DispatchQueue.main.async { [weak self] in
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
                historyOrder.removeAll(where: { $0 == bookId })
                didChange = true
            }

            // Updates/Insertions
            for remoteEntry in entriesToSave {
                if let localEntry = entriesByBookId[remoteEntry.bookId] {
                    // Conflict resolution based on updatedAt
                    let localModified = localEntry.updatedAt.timeIntervalSince1970
                    let remoteModified = remoteEntry.updatedAt.timeIntervalSince1970

                    if remoteModified > localModified {
                        entriesByBookId[remoteEntry.bookId] = remoteEntry
                        didChange = true
                    }
                } else {
                    entriesByBookId[remoteEntry.bookId] = remoteEntry
                    didChange = true
                }
            }

            if didChange {
                // Sinkronkan urutan history di semua devices berdasarkan `lastOpenedAt`.
                // Ini akan memastikan buku yang baru dibaca di device lain akan pindah ke atas.
                let validHistoryEntries = entriesByBookId.values.filter { $0.lastOpenedAt != nil }
                let sortedIds = validHistoryEntries
                    .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
                    .map(\.bookId)
                historyOrder = Array(sortedIds.prefix(maxHistoryCount))

                pruneOrphanedEntries()
                // Persist but don't re-upload to cloud since it came from cloud
                let payload = currentPayload()
                if let data = try? JSONEncoder().encode(payload) {
                    UserDefaults.standard.set(data, forKey: storageKey)
                }
                loadBooksData()
            }
        }
    }

    // MARK: - Pending Sync Handling

    func addPendingSync(ckRecordId: String, operation: String) {
        pendingQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if operation == "upload" {
                if !pendingDeletes.contains(ckRecordId) {
                    pendingUploads.insert(ckRecordId)
                }
            } else {
                pendingDeletes.insert(ckRecordId)
                pendingUploads.remove(ckRecordId)
            }
            savePendingSync()
        }
    }

    func removePendingSync(ckRecordIds: [String]) {
        pendingQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            for id in ckRecordIds {
                pendingUploads.remove(id)
                pendingDeletes.remove(id)
            }
            savePendingSync()
        }
    }

    func fetchPendingSync(operation: String) -> [String] {
        pendingQueue.sync {
            if operation == "upload" {
                Array(pendingUploads)
            } else {
                Array(pendingDeletes)
            }
        }
    }

    private func loadPendingSync() {
        pendingQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if let upData = UserDefaults.standard.data(forKey: "HistoryPendingUploads"),
               let upList = try? JSONDecoder().decode([String].self, from: upData)
            {
                pendingUploads = Set(upList)
            }
            if let delData = UserDefaults.standard.data(forKey: "HistoryPendingDeletes"),
               let delList = try? JSONDecoder().decode([String].self, from: delData)
            {
                pendingDeletes = Set(delList)
            }
        }
    }

    private func savePendingSync() {
        if let upData = try? JSONEncoder().encode(Array(pendingUploads)) {
            UserDefaults.standard.set(upData, forKey: "HistoryPendingUploads")
        }
        if let delData = try? JSONEncoder().encode(Array(pendingDeletes)) {
            UserDefaults.standard.set(delData, forKey: "HistoryPendingDeletes")
        }
    }

    // MARK: - KVS Migration

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

        if didChange {
            // Simpan ke disk + refresh UI; upload ditangani oleh caller via completion
            persistToDiskOnly()
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
            // Apply it as cloud change
            for entry in legacy.entries {
                if entriesByBookId[entry.bookId] == nil {
                    var migrated = entry
                    migrated.ckRecordId = String(entry.bookId)
                    entriesByBookId[entry.bookId] = migrated
                }
            }

            for hId in legacy.historyOrder {
                if !historyOrder.contains(hId) {
                    historyOrder.append(hId)
                }
            }

            // Simpan ke disk dan refresh UI
            persistToDiskOnly()
            loadBooksData()

            // Upload semua entry hasil migrasi ke CloudKit (satu kali, batch)
            let migratedEntries = Array(entriesByBookId.values).filter { $0.ckRecordId != nil }
            if !migratedEntries.isEmpty {
                CloudKitSyncManager.shared.uploadHistory(entries: migratedEntries)
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

        // Hapus entry lama dari CloudKit
        if let oldCkId = entry.ckRecordId {
            CloudKitSyncManager.shared.delete(ckRecordIds: [oldCkId], target: .history)
        }

        // Upload hanya entry yang baru (hasil migrasi)
        persistAndReload(uploadEntry: migrated)
    }
}
