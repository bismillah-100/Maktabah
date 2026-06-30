//
//  CloudKitCoreManager.swift
//  Maktabah
//

import CloudKit
import Foundation

final class CloudKitCoreManager {
    static let shared = CloudKitCoreManager()

    let container: CKContainer
    let privateDatabase: CKDatabase
    let zoneId: CKRecordZone.ID

    let changeTokenKey = "CKServerChangeToken_AnnotationsZone"
    private(set) var isSyncing = false
    private let syncQueue = DispatchQueue(label: "com.maktabah.cloudkitcore.sync", attributes: .concurrent)
    private var notifyTask: Task<Void, Never>?

    /// Using OperationQueue to prevent spamming CloudKit with too many concurrent operations
    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.maktabah.cloudkitcore.operation"
        queue.maxConcurrentOperationCount = 2 // Prevent rate limiting
        return queue
    }()

    private init() {
        container = CKContainer(identifier: "iCloud.Maktabah")
        privateDatabase = container.privateCloudDatabase
        zoneId = CKRecordZone.ID(zoneName: "AnnotationsZone", ownerName: CKCurrentUserDefaultName)
    }

    func setSyncing(_ syncing: Bool, completion: (() -> Void)? = nil) {
        syncQueue.async(flags: .barrier) { [weak self] in
            self?.isSyncing = syncing
            completion?()
        }
    }

    // MARK: - Save Token

    func saveToken(_ token: CKServerChangeToken?) {
        guard let token = token else { return }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: changeTokenKey)
        }
    }

    func loadToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: changeTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    func resetToken() {
        UserDefaults.standard.removeObject(forKey: changeTokenKey)
        UserDefaults.standard.removeObject(forKey: "CloudKitSyncManager_InitialUploadDone")
        setSyncing(false)
    }

    // MARK: - Core Operations

    func upload(records: [CKRecord], completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !records.isEmpty else {
            completion?(.success(()))
            return
        }

        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys

        operation.modifyRecordsResultBlock = { [weak self] result in
            completion?(result)
            self?.notifyWorkerToSync()
        }

        operation.database = privateDatabase
        operation.qualityOfService = .userInitiated
        operationQueue.addOperation(operation)
    }

    func delete(recordIds: [CKRecord.ID], completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !recordIds.isEmpty else {
            completion?(.success(()))
            return
        }

        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIds)
        operation.modifyRecordsResultBlock = { [weak self] result in
            completion?(result)
            self?.notifyWorkerToSync()
        }

        operation.database = privateDatabase
        operation.qualityOfService = .userInitiated
        operationQueue.addOperation(operation)
    }

    func fetchChanges(
        previousToken: CKServerChangeToken?,
        recordChanged: @escaping (CKRecord) -> Void,
        recordDeleted: @escaping (CKRecord.ID) -> Void,
        completion: @escaping (Result<(CKServerChangeToken?, Bool), Error>) -> Void
    ) {
        let options = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        options.previousServerChangeToken = previousToken

        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneId], configurationsByRecordZoneID: [zoneId: options])

        var finalToken: CKServerChangeToken?
        var moreComing = false

        operation.recordWasChangedBlock = { _, recordResult in
            if let record = try? recordResult.get() {
                recordChanged(record)
            }
        }

        operation.recordWithIDWasDeletedBlock = { recordId, _ in
            recordDeleted(recordId)
        }

        operation.recordZoneFetchResultBlock = { _, result in
            switch result {
            case .success(let successData):
                finalToken = successData.serverChangeToken
                moreComing = successData.moreComing
            case .failure:
                break // Handled in overall fetch block
            }
        }

        operation.fetchRecordZoneChangesResultBlock = { result in
            switch result {
            case .success:
                completion(.success((finalToken, moreComing)))
            case .failure(let error):
                completion(.failure(error))
            }
        }

        operation.database = privateDatabase
        operation.qualityOfService = .userInitiated
        operationQueue.addOperation(operation)
    }

    // MARK: - Cross-Platform Sync Notification

    /// Private, penjagaan untuk tidak diakses dari luar ``CloudKitCoreManager``.
    private func makeWorker() -> URLRequest? {
        guard AppConfig.useCrossPlatformSync else { return nil }

        var urlString = AppConfig.customWorkerURL
        if urlString.isEmpty {
            urlString = Bundle.main.object(forInfoDictionaryKey: "WorkerURL") as? String ?? ""
        }

        guard !urlString.isEmpty, urlString != "$(WORKER_URL)",
              let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return request
    }

    /// Private, penjagaan untuk tidak dijalankan di luar `notifyTask`.
    private func asyncWorker() {
        guard let request = makeWorker() else { return }
        URLSession.shared.dataTask(with: request).resume()
    }

    /// Sync `HTTP POST` ke cloudFlare worker dengan DispatchSemaphore timeout 3 detik.
    func syncWorker() {
        guard notifyTask != nil,  let request = makeWorker() else { return }
        let semaphore = DispatchSemaphore(value: 0)
        var requestError: Error?
        URLSession.shared.dataTask(with: request) { _, _, error in
            requestError = error
            semaphore.signal()
        }.resume()

        let timeoutResult = semaphore.wait(timeout: .now() + 3.0)

        #if DEBUG
        if timeoutResult == .timedOut {
            print("CloudKitSyncManager: Sync worker timed out on exit.")
        } else if let error = requestError {
            print("CloudKitSyncManager: Failed to notify Android: \(error)")
        } else {
            print("CloudKitSyncManager: Successfully notified Android to sync before termination.")
        }
        #endif
    }

    func notifyWorkerToSync() {
        notifyTask?.cancel()
        notifyTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            asyncWorker()
            notifyTask = nil
        }
    }
}
