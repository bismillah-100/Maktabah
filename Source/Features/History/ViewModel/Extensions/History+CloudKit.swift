//
//  History+CloudKit.swift
//  Maktabah
//

import Foundation

extension HistoryViewModel {
    // MARK: - CloudKit Sync Support

    func getAllEntries() -> [ReadingEntry] {
        Array(entriesByBookId.values)
    }

    @discardableResult
    func applyCloudKitChanges(entriesToSave: [ReadingEntry], recordIdsToDelete: [String]) -> Bool {
        let block = { [weak self] in
            guard let self else { return }
            var didChange = false
            var deletedIds = [Int]()
            var upsertedEntries = [ReadingEntry]()

            didChange = applyDeletions(recordIdsToDelete: recordIdsToDelete, deletedIds: &deletedIds) || didChange
            didChange = applyUpserts(entriesToSave: entriesToSave, upsertedEntries: &upsertedEntries) || didChange

            if didChange {
                synchronizeHistoryOrder(deletedIds: &deletedIds, upsertedEntries: upsertedEntries)
            }
        }

        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async { block() }
        }
        return true
    }

    func applyDeletions(recordIdsToDelete: [String], deletedIds: inout [Int]) -> Bool {
        let bookIdsToDelete = entriesByBookId.values.compactMap { entry -> Int? in
            guard let ckId = entry.ckRecordId, recordIdsToDelete.contains(ckId) else { return nil }
            return entry.bookId
        }

        var didChange = false
        for bookId in bookIdsToDelete {
            entriesByBookId.removeValue(forKey: bookId)
            historyOrder.removeAll(where: { $0 == bookId })
            deletedIds.append(bookId)
            didChange = true
        }
        return didChange
    }

    func applyUpserts(entriesToSave: [ReadingEntry], upsertedEntries: inout [ReadingEntry]) -> Bool {
        var didChange = false
        for remoteEntry in entriesToSave {
            if let localEntry = entriesByBookId[remoteEntry.bookId] {
                let localModified = localEntry.updatedAt.timeIntervalSince1970
                let remoteModified = remoteEntry.updatedAt.timeIntervalSince1970

                if remoteModified >= localModified {
                    var merged = remoteEntry
                    if merged.lastOpenedAt == nil {
                        merged.lastOpenedAt = localEntry.lastOpenedAt
                    }
                    if merged.lastContentId == nil {
                        merged.lastContentId = localEntry.lastContentId
                    }
                    if merged.favoritedAt == nil {
                        merged.favoritedAt = localEntry.favoritedAt
                    }
                    if merged.positionUpdatedAt == nil {
                        merged.positionUpdatedAt = localEntry.positionUpdatedAt
                    }
                    entriesByBookId[remoteEntry.bookId] = merged
                    upsertedEntries.append(merged)
                    didChange = true
                }
            } else {
                entriesByBookId[remoteEntry.bookId] = remoteEntry
                upsertedEntries.append(remoteEntry)
                didChange = true
            }
        }
        return didChange
    }

    func synchronizeHistoryOrder(deletedIds: inout [Int], upsertedEntries: [ReadingEntry]) {
        let validHistoryEntries = entriesByBookId.values.filter { $0.lastOpenedAt != nil }
        let sortedIds = validHistoryEntries
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .map(\.bookId)
        historyOrder = Array(sortedIds.prefix(maxHistoryCount))

        let prunedIds = pruneOrphanedEntries(deleteFromDB: false)
        deletedIds.append(contentsOf: prunedIds)

        let finalOrder = historyOrder
        loadBooksData()
        notifyHistoryChanged()

        let finalDeleted = deletedIds
        DispatchQueue.global(qos: .background).async {
            do {
                try HistoryDatabaseManager.shared.saveCloudKitChanges(deletedIds: finalDeleted, upsertedEntries: upsertedEntries, finalOrder: finalOrder)
            } catch {
                #if DEBUG
                print("Failed to applyCloudKitChanges: \(error)")
                #endif
            }
        }
    }

    func triggerDeleteDebounce() {
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
}
