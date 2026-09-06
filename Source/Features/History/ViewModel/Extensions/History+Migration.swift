//
//  History+Migration.swift
//  Maktabah
//

import Foundation

extension HistoryViewModel {
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

    func migrateLegacyKVSDataIfNeeded() {
        if UserDefaults.standard.bool(forKey: "HistoryViewModel_LegacyMigrated_v2") {
            return
        }

        if let legacy = loadLegacyPayload() {
            loadFromDatabase()

            var newEntries = [ReadingEntry]()
            for entry in legacy.entries where entriesByBookId[entry.bookId] == nil {
                var migrated = entry
                migrated.ckRecordId = String(entry.bookId)
                entriesByBookId[entry.bookId] = migrated
                newEntries.append(migrated)
            }

            for hId in legacy.historyOrder where !historyOrder.contains(hId) {
                historyOrder.append(hId)
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

    func loadLegacyPayload() -> StoredReadingEntries? {
        let kvs = NSUbiquitousKeyValueStore.default
        if let data = UserDefaults.standard.data(forKey: legacyHistoryKey),
           let decoded = try? JSONDecoder().decode(StoredReadingEntries.self, from: data)
        {
            return decoded
        } else if let data = kvs.data(forKey: legacyHistoryKey),
                  let decoded = try? JSONDecoder().decode(StoredReadingEntries.self, from: data)
        {
            return decoded
        }
        return nil
    }
}
