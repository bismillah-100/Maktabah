//
//  History+Database.swift
//  Maktabah
//

import Foundation
import OSLog

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
                Logger.history.error("Failed to save clearHistory: \(error.localizedDescription, privacy: .public)")
            }
        }
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
