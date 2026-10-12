//
//  History+CloudKit.swift
//  Maktabah
//

import Foundation
import OSLog

extension HistoryViewModel {
    // MARK: - CloudKit Sync Support

    func getAllEntries() -> [ReadingEntry] {
        Array(entriesByBookId.values)
    }

    @discardableResult
    func applyCloudKitChanges(entriesToSave: [ReadingEntry], recordIdsToDelete: [String]) -> Bool {
        var didChange = false
        var deletedIds = [Int]()
        var upsertedEntries = [ReadingEntry]()

        didChange = applyDeletions(recordIdsToDelete: recordIdsToDelete, deletedIds: &deletedIds) || didChange
        didChange = applyUpserts(entriesToSave: entriesToSave, upsertedEntries: &upsertedEntries) || didChange

        if didChange {
            synchronizeHistoryOrder(deletedIds: &deletedIds, upsertedEntries: upsertedEntries)
        }
        return didChange
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
                let (merged, changed) = mergeEntries(local: localEntry, remote: remoteEntry)
                if changed {
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

    func mergeEntries(local: ReadingEntry, remote: ReadingEntry) -> (merged: ReadingEntry, changed: Bool) {
        var merged = local
        var changed = false

        if mergeFavorite(into: &merged, local: local, remote: remote) {
            changed = true
        }
        if mergePosition(into: &merged, local: local, remote: remote) {
            changed = true
        }
        if mergeMetadata(into: &merged, local: local, remote: remote) {
            changed = true
        }

        return (merged, changed)
    }

    private func mergeFavorite(into merged: inout ReadingEntry, local: ReadingEntry, remote: ReadingEntry) -> Bool {
        let localFav = local.favoritedAt ?? .distantPast
        let remoteFav = remote.favoritedAt ?? .distantPast

        if remoteFav > localFav {
            guard merged.isFavorite != remote.isFavorite || merged.favoritedAt != remote.favoritedAt else { return false }
            merged.isFavorite = remote.isFavorite
            merged.favoritedAt = remote.favoritedAt
            return true
        }

        if remoteFav == localFav, remote.isFavorite != local.isFavorite, remote.updatedAt >= local.updatedAt {
            merged.isFavorite = remote.isFavorite
            return true
        }

        return false
    }

    private func mergePosition(into merged: inout ReadingEntry, local: ReadingEntry, remote: ReadingEntry) -> Bool {
        let localPos = local.positionUpdatedAt ?? .distantPast
        let remotePos = remote.positionUpdatedAt ?? .distantPast

        if remotePos > localPos {
            guard merged.lastContentId != remote.lastContentId || merged.positionUpdatedAt != remote.positionUpdatedAt else { return false }
            merged.lastContentId = remote.lastContentId
            merged.positionUpdatedAt = remote.positionUpdatedAt
            return true
        }

        if remotePos == localPos, remote.lastContentId != local.lastContentId, remote.updatedAt >= local.updatedAt {
            merged.lastContentId = remote.lastContentId
            return true
        }

        return false
    }

    private func mergeMetadata(into merged: inout ReadingEntry, local: ReadingEntry, remote: ReadingEntry) -> Bool {
        var changed = false

        if let rOpen = remote.lastOpenedAt {
            if local.lastOpenedAt == nil || rOpen > local.lastOpenedAt! {
                merged.lastOpenedAt = rOpen
                changed = true
            }
        }

        if merged.ckRecordId == nil {
            merged.ckRecordId = remote.ckRecordId ?? String(local.bookId)
            changed = true
        }

        let maxUpdated = max(local.updatedAt, remote.updatedAt)
        if merged.updatedAt != maxUpdated {
            merged.updatedAt = maxUpdated
            changed = true
        }

        return changed
    }

    func synchronizeHistoryOrder(deletedIds: inout [Int], upsertedEntries: [ReadingEntry]) {
        let validHistoryEntries = entriesByBookId.values.filter { $0.lastOpenedAt != nil }
        let sortedIds = validHistoryEntries
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .map(\.bookId)
        historyOrder = Array(sortedIds.prefix(maxHistoryCount))

        let finalOrder = historyOrder
        loadBooksData()
        notifyHistoryChanged()

        let finalDeleted = deletedIds
        DispatchQueue.global(qos: .background).async {
            do {
                try HistoryDatabaseManager.shared.saveCloudKitChanges(deletedIds: finalDeleted, upsertedEntries: upsertedEntries, finalOrder: finalOrder)
            } catch {
                Logger.history.error("Failed to applyCloudKitChanges: \(error.localizedDescription, privacy: .public)")
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
