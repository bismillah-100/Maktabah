//
//  CloudKitFetcher.swift
//  Maktabah
//
//  Created by Ghoys on 30/08/2026.
//

import CloudKit
import Foundation
import WidgetKit

final class CloudKitFetcher: @unchecked Sendable {
    static let shared = CloudKitFetcher()

    private let ckDatabase = CKContainer(identifier: "iCloud.Maktabah").privateCloudDatabase
    private let customZoneID = CKRecordZone.ID(zoneName: "AnnotationsZone", ownerName: CKCurrentUserDefaultName)

    private init() {}

    /// Mengambil snapshot aktif secara generik dari CloudKit atau fallback ke lokal dengan strategi local-first
    func fetchActive<T: WidgetSnapshotRecord>() async -> T? {
        // 1. Muat snapshot lokal terlebih dahulu secara instan (< 2ms)
        let localSnapshot = await T.loadLocal()

        // 2. Coba sinkronisasi data remote dari CloudKit dengan batas waktu 3.0 detik
        let remoteSnapshot = await fetchRemoteWithTimeout(type: T.self, timeoutSeconds: 3.0)

        guard let remoteSnapshot else {
            return await T.loadLocal() ?? localSnapshot
        }

        // 3. Baca ulang snapshot lokal terbaru untuk mencegah TOCTOU tanpa menulis ulang dari ekstensi sandbox
        let latestLocal = await T.loadLocal() ?? localSnapshot
        let (resolved, _) = await T.resolve(remote: remoteSnapshot, local: latestLocal, persistToLocal: false)
        return resolved ?? latestLocal
    }

    private func fetchRemoteWithTimeout<T: WidgetSnapshotRecord>(
        type: T.Type,
        timeoutSeconds: Double = 3.0
    ) async -> T? {
        let recordId = CKRecord.ID(recordName: T.ckRecordName, zoneID: customZoneID)

        return await withTaskGroup(of: T?.self) { group in
            // Task 1: CloudKit Fetch dengan async murni
            group.addTask {
                do {
                    let result = try await self.ckDatabase.records(for: [recordId], desiredKeys: ["payload"])
                    guard let recordRes = result[recordId],
                          case let .success(record) = recordRes,
                          let data = record["payload"] as? Data,
                          var decoded = try? JSONDecoder().decode(T.self, from: data)
                    else {
                        return nil
                    }
                    decoded.recordChangeTag = record.recordChangeTag
                    return decoded
                } catch {
                    return nil
                }
            }

            // Task 2: Batas Waktu
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return nil
            }

            // Ambil pemenang pertama (Implicit cancellation akan menghentikan request CloudKit jika timeout menang)
            let firstResult = await group.next() ?? nil
            group.cancelAll()
            return firstResult
        }
    }
}
