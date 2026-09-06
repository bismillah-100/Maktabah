//
//  History+Database.swift
//  Maktabah
//

import Foundation

extension HistoryViewModel {
    // MARK: - Load from Database

    func reloadFromDatabase() {
        loadFromDatabase()
        loadBooksData()
    }

    func loadFromDatabase() {
        let data = HistoryDatabaseManager.shared.loadFromDatabase()
        entriesByBookId = Dictionary(uniqueKeysWithValues: data.entries.map { ($0.bookId, $0) })
        historyOrder = data.historyOrder
    }

    func saveClearedHistoryInDatabase(
        order: [Int],
        deletedIds: [Int],
        upserted: [ReadingEntry],
        ckIdsToDelete: [String]
    ) {
        let ckIdsToDeleteSafe = ckIdsToDelete
        DispatchQueue.global(qos: .background).async {
            do {
                try HistoryDatabaseManager.shared.saveCloudKitChanges(
                    deletedIds: deletedIds,
                    upsertedEntries: upserted,
                    finalOrder: order
                )
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

    // MARK: - Pruning

    @discardableResult
    func pruneOrphanedEntries(deleteFromDB: Bool = true) -> [Int] {
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

        if deleteFromDB, !removedIds.isEmpty {
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

    func loadBooksData() {
        let hIds = historyOrder
        let fIds = favoriteBookIds
        let allNeededIds = Set(hIds).union(Set(fIds))

        let books = LibraryDataManager.shared.getBook(Array(allNeededIds))
        let booksDict = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })

        historyBooks = hIds.compactMap { booksDict[$0] }
        favoriteBooks = fIds.compactMap { booksDict[$0] }
    }
}
