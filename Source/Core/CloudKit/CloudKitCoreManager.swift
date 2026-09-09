//
//  CloudKitCoreManager.swift
//  Maktabah
//

import CloudKit
import Foundation
import Synchronization

/// Manajer inti untuk operasi CloudKit yang kompatibel penuh dengan Swift 6.
///
/// Menggunakan `Synchronization.Mutex` (macOS 15+ / iOS 18+) untuk menggantikan `DispatchQueue.sync`
/// dan barrier queue, sehingga thread-safe tanpa risiko deadlock saat dipanggil
/// dari dalam konteks `actor` atau Swift Concurrency Task.
final class CloudKitCoreManager: Sendable {
    /// Struktur data internal untuk membungkus state yang membutuhkan sinkronisasi mutual exclusion.
    private struct ManagerState {
        var isSyncing: Bool = false
        var notifyTask: Task<Void, Never>? = nil
    }

    /// Singleton instance thread-safe yang valid dalam Swift 6 tanpa perlu `nonisolated(unsafe)`.
    static let shared = CloudKitCoreManager()

    let container: CKContainer
    let privateDatabase: CKDatabase
    let zoneId: CKRecordZone.ID
    let changeTokenKey = "CKServerChangeToken_AnnotationsZone"

    /// Antrean operasi CloudKit untuk membatasi konkurensi agar terhindar dari rate limit.
    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.maktabah.cloudkitcore.operation"
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    /// Mutex state pengganti concurrent DispatchQueue / queue.sync
    private let state: Mutex<ManagerState>

    private init() {
        let defaultContainer = CKContainer(identifier: "iCloud.Maktabah")
        self.container = defaultContainer
        self.privateDatabase = defaultContainer.privateCloudDatabase
        self.zoneId = CKRecordZone.ID(zoneName: "AnnotationsZone", ownerName: CKCurrentUserDefaultName)
        self.state = Mutex(ManagerState())
    }

    /// Membaca status sinkronisasi secara thread-safe menggunakan Mutex `withLock`.
    /// Aman dipanggil secara sinkron dari dalam `actor` tanpa risiko blocking thread pool GCD.
    var isSyncing: Bool {
        state.withLock { $0.isSyncing }
    }

    /// Mengubah status sinkronisasi secara atomik dengan Mutex.
    /// Menggantikan `syncQueue.async(flags: .barrier)` terdahulu.
    func setSyncing(_ syncing: Bool, completion: (@Sendable () -> Void)? = nil) {
        state.withLock {
            $0.isSyncing = syncing
        }
        completion?()
    }

    // MARK: - Token Management

    func saveToken(_ token: CKServerChangeToken?) {
        guard let token else { return }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: changeTokenKey)
        }
    }

    func loadToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: changeTokenKey) else { return nil }
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            return unarchiver.decodeObject(of: CKServerChangeToken.self, forKey: NSKeyedArchiveRootObjectKey)
        } catch {
            return nil
        }
    }

    func resetToken() {
        UserDefaults.standard.removeObject(forKey: changeTokenKey)
        UserDefaults.standard.removeObject(forKey: "CloudKitSyncManager_InitialUploadDone")
        setSyncing(false)
    }

    // MARK: - Core Operations

    func upload(records: [CKRecord], completion: (@Sendable (Result<Void, any Error>) -> Void)? = nil) {
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

    func delete(recordIds: [CKRecord.ID], completion: (@Sendable (Result<Void, any Error>) -> Void)? = nil) {
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
        recordChanged: @escaping @Sendable (CKRecord) -> Void,
        recordDeleted: @escaping @Sendable (CKRecord.ID) -> Void,
        completion: @escaping @Sendable (Result<(CKServerChangeToken?, Bool), any Error>) -> Void
    ) {
        let options = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        options.previousServerChangeToken = previousToken

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneId],
            configurationsByRecordZoneID: [zoneId: options]
        )

        // Mutex lokal untuk mencegah data race saat menangkap state di callback terpisah dalam Swift 6
        struct FetchResultState: Sendable {
            var finalToken: CKServerChangeToken?
            var moreComing: Bool = false
        }
        let fetchState = Mutex(FetchResultState())

        operation.recordWasChangedBlock = { _, recordResult in
            if let record = try? recordResult.get() {
                recordChanged(record)
            }
        }

        operation.recordWithIDWasDeletedBlock = { recordId, _ in
            recordDeleted(recordId)
        }

        operation.recordZoneFetchResultBlock = { _, result in
            if case let .success(successData) = result {
                fetchState.withLock {
                    $0.finalToken = successData.serverChangeToken
                    $0.moreComing = successData.moreComing
                }
            }
        }

        operation.fetchRecordZoneChangesResultBlock = { result in
            switch result {
            case .success:
                let extracted = fetchState.withLock { ($0.finalToken, $0.moreComing) }
                completion(.success(extracted))
            case let .failure(error):
                completion(.failure(error))
            }
        }

        operation.database = privateDatabase
        operation.qualityOfService = .userInitiated
        operationQueue.addOperation(operation)
    }

    // MARK: - Modern Swift Concurrency (Actor-Friendly Async APIs)

    /// Wrapper modern berbasis async/await untuk dipanggil langsung dari konteks `actor` atau Task.
    func upload(records: [CKRecord]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            upload(records: records) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Wrapper modern berbasis async/await untuk penghapusan record.
    func delete(recordIds: [CKRecord.ID]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            delete(recordIds: recordIds) { result in
                continuation.resume(with: result)
            }
        }
    }

    // MARK: - Cross-Platform Sync Notification

    /// Membuat URLRequest untuk Cloudflare worker secara thread-safe.
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

    private func asyncWorker() {
        guard let request = makeWorker() else { return }
        URLSession.shared.dataTask(with: request).resume()
    }

    /// Menjadwalkan notifikasi worker dengan mekanisme throttling (60 detik).
    /// Menggunakan `state.withLock` untuk menjaga `notifyTask` dari data race.
    func notifyWorkerToSync() {
        state.withLock { s in
            guard s.notifyTask == nil else { return }

            s.notifyTask = Task { [weak self] in
                defer {
                    self?.state.withLock { state in
                        state.notifyTask = nil
                    }
                }

                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.asyncWorker()
            }
        }
    }

    /// Sinkronisasi darurat saat aplikasi akan ditutup (misal `applicationWillTerminate`).
    func syncWorker() {
        let hasPendingTask = state.withLock { s -> Bool in
            guard s.notifyTask != nil else { return false }
            s.notifyTask?.cancel()
            s.notifyTask = nil
            return true
        }

        guard hasPendingTask, let request = makeWorker() else { return }

        let semaphore = DispatchSemaphore(value: 0)
        let errorState = Mutex<(any Error)?>(nil)

        URLSession.shared.dataTask(with: request) { _, _, error in
            errorState.withLock { $0 = error }
            semaphore.signal()
        }.resume()

        let timeoutResult = semaphore.wait(timeout: .now() + 3.0)

        #if DEBUG
        let requestError = errorState.withLock { $0 }
        if timeoutResult == .timedOut {
            print("CloudKitSyncManager: Sync worker timed out on exit.")
        } else if let requestError {
            print("CloudKitSyncManager: Failed to notify Android: \(requestError)")
        } else {
            print("CloudKitSyncManager: Successfully notified Android to sync before termination.")
        }
        #endif
    }
}
