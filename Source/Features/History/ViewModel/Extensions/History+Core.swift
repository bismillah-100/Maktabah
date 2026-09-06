//
//  History+Core.swift
//  Maktabah
//

import Foundation
import SwiftUI

extension HistoryViewModel {
    // MARK: - Core Operations

    func getOrCreateEntry(for bookId: Int) -> ReadingEntry {
        entriesByBookId[bookId] ?? ReadingEntry(defaultForBookId: bookId)
    }

    func saveAndSync(entry: inout ReadingEntry, reloadUI: Bool = true) {
        if entry.ckRecordId == nil {
            entry.ckRecordId = String(entry.bookId)
        }
        entriesByBookId[entry.bookId] = entry
        HistoryDatabaseManager.shared.upsertEntry(entry)
        if reloadUI {
            loadBooksData()
        }
        notifyHistoryChanged()
        CloudKitSyncManager.shared.uploadHistory(entries: [entry], trackPending: false)
    }

    func addBookToHistory(_ bookId: Int) {
        guard DatabaseManager.shared.bookExists(id: bookId) else { return }

        var entry = getOrCreateEntry(for: bookId)
        let now = Date()
        entry.lastOpenedAt = now
        entry.updatedAt = now

        historyOrder.removeAll { $0 == bookId }
        historyOrder.insert(bookId, at: 0)

        if historyOrder.count > maxHistoryCount {
            historyOrder = Array(historyOrder.prefix(maxHistoryCount))
        }

        pruneOrphanedEntries()
        HistoryDatabaseManager.shared.saveHistoryOrder(historyOrder)
        saveAndSync(entry: &entry, reloadUI: true)
    }

    func updateLastContentId(_ contentId: Int, for bookId: Int) {
        if var entry = entriesByBookId[bookId] {
            let now = Date()
            entry.lastContentId = contentId
            entry.positionUpdatedAt = now
            entry.updatedAt = now
            // Hanya simpan ke DB — tidak reload UI library (tidak ada perubahan visible)
            saveAndSync(entry: &entry, reloadUI: false)
        } else {
            addBookToHistory(bookId)
            updateLastContentId(contentId, for: bookId)
        }
    }

    func toggleFavorite(_ bookId: Int) {
        guard DatabaseManager.shared.bookExists(id: bookId) else { return }

        var entry = getOrCreateEntry(for: bookId)
        entry.isFavorite.toggle()
        let now = Date()
        if entry.isFavorite {
            entry.favoritedAt = now
        }
        entry.updatedAt = now
        saveAndSync(entry: &entry, reloadUI: true)
    }

    func removeHistory(for bookId: Int) {
        historyOrder.removeAll { $0 == bookId }
        notifyHistoryChanged()
        guard let entry = entriesByBookId[bookId] else { return }

        if entry.isFavorite {
            handleFavoritedHistoryRemoval(entry: entry, bookId: bookId)
        } else {
            handleNonFavoritedHistoryRemoval(entry: entry, bookId: bookId)
        }
    }

    func handleFavoritedHistoryRemoval(entry: ReadingEntry, bookId: Int) {
        var updatedEntry = entry
        updatedEntry.lastOpenedAt = nil
        updatedEntry.updatedAt = Date()
        entriesByBookId[bookId] = updatedEntry

        let upserted = [updatedEntry]
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
    }

    func handleNonFavoritedHistoryRemoval(entry: ReadingEntry, bookId: Int) {
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

    func clearHistory() {
        let historyIdsToRemove = historyOrder
        historyOrder.removeAll()
        notifyHistoryChanged()

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

        saveClearedHistoryInDatabase(
            order: historyOrder,
            deletedIds: deletedIds,
            upserted: upserted,
            ckIdsToDelete: ckIdsToDelete
        )
    }

    func isFavorite(_ bookId: Int) -> Bool {
        entriesByBookId[bookId]?.isFavorite ?? false
    }
}
