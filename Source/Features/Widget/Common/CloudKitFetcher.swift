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
    func fetchActive<T: WidgetSnapshotRecord>(completion: @escaping (T?) -> Void) {
        Task {
            let remoteSnapshot = await fetchRemoteWithTimeout(type: T.self)

            guard let remoteSnapshot else {
                let localSnapshot = await T.loadLocal()
                completion(localSnapshot)
                return
            }

            let (resolved, _) = await T.resolve(remote: remoteSnapshot)
            completion(resolved)
        }
    }

    private func fetchRemoteWithTimeout<T: WidgetSnapshotRecord>(type: T.Type) async -> T? {
        let recordId = CKRecord.ID(recordName: T.ckRecordName, zoneID: customZoneID)

        return await withTaskGroup(of: T?.self) { group in
            // Task 1: CloudKit Fetch dengan pembatalan eksplisit
            group.addTask {
                let operation = CKFetchRecordsOperation(recordIDs: [recordId])
                operation.desiredKeys = ["payload"]

                let config = CKOperation.Configuration()
                config.timeoutIntervalForRequest = 8.0
                operation.configuration = config

                return await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        var fetchedData: Data?
                        var fetchedChangeTag: String?

                        operation.perRecordResultBlock = { _, result in
                            if case let .success(record) = result {
                                fetchedData = record["payload"] as? Data
                                fetchedChangeTag = record.recordChangeTag
                            }
                        }

                        operation.fetchRecordsResultBlock = { [weak operation] _ in
                            if operation?.isCancelled == true {
                                continuation.resume(returning: nil)
                                return
                            }
                            if let data = fetchedData, var decoded = try? JSONDecoder().decode(T.self, from: data) {
                                decoded.recordChangeTag = fetchedChangeTag
                                continuation.resume(returning: decoded)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }

                        self.ckDatabase.add(operation)
                    }
                } onCancel: {
                    operation.cancel() // Batalkan CloudKit seketika jika Task 2 menang. Dilarang memanggil resume di sini!
                }
            }

            // Task 2: Batas Waktu 6 Detik
            group.addTask {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                return nil
            }

            // Ambil pemenang pertama
            let firstResult = await group.next() ?? nil
            group.cancelAll()
            return firstResult
        }
    }
}
