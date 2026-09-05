//
//  CloudKitFetcher.swift
//  Maktabah
//
//  Created by Ghoys on 30/08/2026.
//

import CloudKit
import Foundation

final class CloudKitFetcher: @unchecked Sendable {
    static let shared = CloudKitFetcher()

    private let ckDatabase = CKContainer(identifier: "iCloud.Maktabah").privateCloudDatabase
    private let customZoneID = CKRecordZone.ID(zoneName: "AnnotationsZone", ownerName: CKCurrentUserDefaultName)

    private init() {}

    /// Mengambil snapshot aktif secara generik dari CloudKit atau fallback ke lokal
    func fetchActive<T: WidgetSnapshotRecord>() async -> T? {
        let remoteSnapshot = await fetchRemoteWithTimeout(type: T.self)

        guard let remoteSnapshot else {
            return await T.loadLocal()
        }

        let (resolved, _) = await T.resolve(remote: remoteSnapshot)
        return resolved
    }

    private func fetchRemoteWithTimeout<T: WidgetSnapshotRecord>(type: T.Type) async -> T? {
        let recordId = CKRecord.ID(recordName: T.ckRecordName, zoneID: customZoneID)

        return await withTaskGroup(of: T?.self) { group in
            // Task 1: CloudKit Fetch dengan async murni
            group.addTask {
                do {
                    let result = try await self.ckDatabase.records(for: [recordId], desiredKeys: ["payload"])
                    guard let recordRes = result[recordId],
                          case let .success(record) = recordRes,
                          let data = record["payload"] as? Data,
                          var decoded = try? JSONDecoder().decode(T.self, from: data) else {
                        return nil
                    }
                    decoded.recordChangeTag = record.recordChangeTag
                    return decoded
                } catch {
                    return nil
                }
            }

            // Task 2: Batas Waktu 6 Detik
            group.addTask {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                return nil
            }

            // Ambil pemenang pertama (Implicit cancellation akan menghentikan request CloudKit jika timeout menang)
            let firstResult = await group.next() ?? nil
            group.cancelAll()
            return firstResult
        }
    }
}
