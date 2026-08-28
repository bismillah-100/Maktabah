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
        let localSnapshot = T.loadLocal()
        let recordId = CKRecord.ID(recordName: T.ckRecordName, zoneID: customZoneID)

        ckDatabase.fetch(withRecordID: recordId) { record, error in
            #if DEBUG
            if let error {
                print("CloudKitFetcher [\(T.self)] fetch error: \(error.localizedDescription)")
            } else if record != nil {
                print("CloudKitFetcher [\(T.self)] successfully fetched from CloudKit")
            }
            #endif

            guard let record,
                  let payload = record["payload"] as? Data,
                  let remoteSnapshot = try? JSONDecoder().decode(T.self, from: payload)
            else {
                completion(localSnapshot)
                return
            }

            let (resolved, _) = T.resolve(remote: remoteSnapshot, local: localSnapshot)
            completion(resolved)
        }
    }
}
