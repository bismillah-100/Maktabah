//
//  CloudKitSyncManager.swift
//  Maktabah
//

import CloudKit
import Foundation
import Network

final class CloudKitSyncManager {
    static let shared = CloudKitSyncManager()

    enum SyncTarget {
        case annotation
        case result
        case history
    }

    private let pendingUploadsKey = "CloudKitSyncManager_PendingUploads"
    private let pendingDeletesKey = "CloudKitSyncManager_PendingDeletes"
    private let syncQueue = DispatchQueue(label: "com.maktabah.cloudkitsync", attributes: .concurrent)
    private var accountChangeObserver: NSObjectProtocol?

    private var core: CloudKitCoreManager { CloudKitCoreManager.shared }

    private init() {
        setupAccountChangeObserver()
        setupNetworkMonitor()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitor() {
        NetworkMonitor.shared.onConnectivityRestored = { [weak self] in
            #if DEBUG
            print("CloudKitSyncManager: Network restored, retrying pending operations")
            #endif
            self?.retryAllPendingOperations()
        }
    }

    private func retryAllPendingOperations() {
        syncQueue.async(flags: .barrier) { [weak self] in
            self?.retryPendingUploads()
            self?.retryPendingDeletes()
        }
    }

    // MARK: - Pending Operations Tracking
    private func addPendingUploads(_ ids: [String], target: SyncTarget) {
        syncQueue.async(flags: .barrier) {
            for id in ids {
                switch target {
                case .annotation:
                    AnnotationManager.shared.addPendingSync(ckRecordId: id, operation: "upload")
                case .result:
                    ResultsHandler.shared.addPendingSync(ckRecordId: id, operation: "upload")
                case .history:
                    HistoryViewModel.shared.addPendingSync(ckRecordId: id, operation: "upload")
                }
            }
        }
    }

    private func removePendingUploads(_ ids: [String]) {
        syncQueue.async(flags: .barrier) {
            AnnotationManager.shared.removePendingSync(ckRecordIds: ids)
            ResultsHandler.shared.removePendingSync(ckRecordIds: ids)
            HistoryViewModel.shared.removePendingSync(ckRecordIds: ids)
        }
    }

    private func addPendingDeletes(_ ids: [String], target: SyncTarget) {
        syncQueue.async(flags: .barrier) {
            for id in ids {
                switch target {
                case .annotation:
                    AnnotationManager.shared.addPendingSync(ckRecordId: id, operation: "delete")
                case .result:
                    ResultsHandler.shared.addPendingSync(ckRecordId: id, operation: "delete")
                case .history:
                    HistoryViewModel.shared.addPendingSync(ckRecordId: id, operation: "delete")
                }
            }
        }
    }

    private func removePendingDeletes(_ ids: [String]) {
        syncQueue.async(flags: .barrier) {
            AnnotationManager.shared.removePendingSync(ckRecordIds: ids)
            ResultsHandler.shared.removePendingSync(ckRecordIds: ids)
            HistoryViewModel.shared.removePendingSync(ckRecordIds: ids)
        }
    }

    // MARK: - Retry Logic
    private func retryPendingUploads() {
        let annPending = AnnotationManager.shared.fetchPendingSync(operation: "upload")
        let resPending = ResultsHandler.shared.fetchPendingSync(operation: "upload")
        let histPending = HistoryViewModel.shared.fetchPendingSync(operation: "upload")
        
        guard !annPending.isEmpty || !resPending.isEmpty || !histPending.isEmpty else { return }
        
        // Paginated or direct DB fetch is recommended here, but we keep existing logic compatible
        if !annPending.isEmpty {
            let allAnnotations = AnnotationManager.shared.loadAnnotations()
            let toUploadAnn = allAnnotations.filter { annPending.contains($0.ckRecordId ?? "") }
            if !toUploadAnn.isEmpty {
                upload(annotations: toUploadAnn)
            }
        }
        
        if !resPending.isEmpty {
            let allFolders = ResultsHandler.shared.fetchAllSyncFolders()
            let toUploadFolders = allFolders.filter { resPending.contains($0.ckRecordId ?? "") }
            
            let allResults = ResultsHandler.shared.fetchAllSyncResults()
            let toUploadResults = allResults.filter { resPending.contains($0.ckRecordId ?? "") }
            
            if !toUploadFolders.isEmpty || !toUploadResults.isEmpty {
                uploadResultsData(folders: toUploadFolders, results: toUploadResults)
            }
        }
        
        if !histPending.isEmpty {
            let allHist = HistoryViewModel.shared.getAllEntries()
            let toUploadHist = allHist.filter { histPending.contains($0.ckRecordId ?? "") }
            if !toUploadHist.isEmpty {
                uploadHistory(entries: toUploadHist)
            }
        }
    }

    private func retryPendingDeletes() {
        let pending = AnnotationManager.shared.fetchPendingSync(operation: "delete") +
                      ResultsHandler.shared.fetchPendingSync(operation: "delete") +
                      HistoryViewModel.shared.fetchPendingSync(operation: "delete")
        
        guard !pending.isEmpty else { return }
        delete(ckRecordIds: pending, trackPending: false)
    }

    // MARK: - Initialization
    private func setupAccountChangeObserver() {
        accountChangeObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetChangeToken()
        }
    }

    func setupAndInitialSync() {
        initializeOnLaunch()
    }

    func initializeOnLaunch() {
        guard AppConfig.useICloud else { return }

        checkUserIdentityChange()
        core.setSyncing(false)

        let customZone = CKRecordZone(zoneID: core.zoneId)
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: [customZone], recordZoneIDsToDelete: nil)

        operation.modifyRecordZonesResultBlock = { [weak self] result in
            switch result {
            case .success:
                self?.fetchChanges()
                self?.subscribeToChanges()
                self?.performInitialUploadCheck()
                self?.retryPendingUploads()
                self?.retryPendingDeletes()
            case .failure(let error):
                #if DEBUG
                print("CloudKitSyncManager: Error creating custom zone: \(error)")
                #endif
            }
        }
        operation.qualityOfService = .userInitiated
        core.privateDatabase.add(operation)
    }

    private func performInitialUploadCheck() {
        if let _ = AnnotationManager.shared.db {
            try? AnnotationManager.shared.backfillCloudKitFieldsIfNeeded { [weak self] backfilled in
                if !backfilled.isEmpty { self?.upload(annotations: backfilled) }
            }
        }

        if let _ = ResultsHandler.shared.db {
            try? ResultsHandler.shared.backfillResultsCloudKitFieldsIfNeeded()
        }

        HistoryViewModel.shared.backfillCloudKitFieldsIfNeeded { [weak self] backfilled in
            if !backfilled.isEmpty { self?.uploadHistory(entries: backfilled) }
        }

        if !UserDefaults.standard.bool(forKey: "CloudKitSyncManager_InitialUploadDone") {
            uploadAllLocalData { success in
                if success {
                    UserDefaults.standard.set(true, forKey: "CloudKitSyncManager_InitialUploadDone")
                }
            }
        }
    }

    private func uploadAllLocalData(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var hasError = false
        let batchSize = 200

        let allAnnotations = AnnotationManager.shared.loadAnnotations()
        for i in stride(from: 0, to: allAnnotations.count, by: batchSize) {
            let batch = Array(allAnnotations[i ..< min(i + batchSize, allAnnotations.count)])
            group.enter()
            upload(annotations: batch) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }

        let allFolders = ResultsHandler.shared.fetchAllSyncFolders()
        for i in stride(from: 0, to: allFolders.count, by: batchSize) {
            let batch = Array(allFolders[i ..< min(i + batchSize, allFolders.count)])
            group.enter()
            uploadResultsData(folders: batch, results: []) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }

        let allResults = ResultsHandler.shared.fetchAllSyncResults()
        for i in stride(from: 0, to: allResults.count, by: batchSize) {
            let batch = Array(allResults[i ..< min(i + batchSize, allResults.count)])
            group.enter()
            uploadResultsData(folders: [], results: batch) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }
        
        let allHistory = HistoryViewModel.shared.getAllEntries()
        for i in stride(from: 0, to: allHistory.count, by: batchSize) {
            let batch = Array(allHistory[i ..< min(i + batchSize, allHistory.count)])
            group.enter()
            uploadHistory(entries: batch) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(!hasError)
        }
    }

    // MARK: - Upload (Insert/Update)

    func upload(
        annotations: [Annotation],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard AppConfig.useICloud else { completion?(.success(())); return }

        let records = annotations.compactMap {
            $0.toCKRecord(zoneID: core.zoneId)
        }
        guard !records.isEmpty else { completion?(.success(())); return }

        let ids = records.map { $0.recordID.recordName }
        addPendingUploads(ids, target: .annotation)

        core.upload(records: records) { [weak self] result in
            self?.handleUploadResult(
                result,
                pendingIds: ids,
                target: .annotation,
                completion: completion
            )
        }
    }

    func uploadResultsData(
        folders: [SyncFolder],
        results: [SyncResult],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard AppConfig.useICloud else { completion?(.success(())); return }

        var records: [CKRecord] = []
        records.append(
            contentsOf: folders.compactMap {
                $0.toCKRecord(zoneID: core.zoneId)
            }
        )
        records.append(
            contentsOf: results.compactMap {
                $0.toCKRecord(zoneID: core.zoneId)
            }
        )

        guard !records.isEmpty else { completion?(.success(())); return }

        let ids = records.map { $0.recordID.recordName }
        addPendingUploads(ids, target: .result)

        core.upload(records: records) { [weak self] result in
            self?.handleUploadResult(
                result,
                pendingIds: ids,
                target: .result,
                completion: completion
            )
        }
    }

    func uploadHistory(
        entries: [ReadingEntry],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard AppConfig.useICloud else { completion?(.success(())); return }

        let records = entries.compactMap { $0.toCKRecord(zoneID: core.zoneId) }
        guard !records.isEmpty else { completion?(.success(())); return }

        let ids = records.map { $0.recordID.recordName }
        addPendingUploads(ids, target: .history)

        core.upload(records: records) { [weak self] result in
            self?.handleUploadResult(
                result,
                pendingIds: ids,
                target: .history,
                completion: completion
            )
        }
    }

    private func handleUploadResult(
        _ result: Result<Void, Error>,
        pendingIds: [String],
        target: SyncTarget,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        switch result {
        case .success:
            removePendingUploads(pendingIds)
            completion?(.success(()))
        case .failure(let error):
            handleUploadFailure(
                error,
                pendingRecordIds: pendingIds,
                completion: completion
            )
        }
    }

    // MARK: - Delete

    func delete(ckRecordIds: [String], target: SyncTarget? = nil, trackPending: Bool = true) {
        guard AppConfig.useICloud else { return }
        if trackPending, let target = target {
            addPendingDeletes(ckRecordIds, target: target)
        }

        let recordIds = ckRecordIds.map { CKRecord.ID(recordName: $0, zoneID: core.zoneId) }
        
        core.delete(recordIds: recordIds) { [weak self] result in
            switch result {
            case .success:
                self?.removePendingDeletes(ckRecordIds)
            case .failure(let error):
                self?.handleCloudKitError(error, operationType: .delete)
            }
        }
    }

    // MARK: - Fetch Changes (Delta)

    func fetchChanges(retryCount: Int = 0) {
        guard AppConfig.useICloud else { return }

        var shouldProceed = false
        syncQueue.sync {
            if !core.isSyncing {
                core.setSyncing(true)
                shouldProceed = true
            }
        }
        guard shouldProceed else { return }

        let previousToken = core.loadToken()
        let fetchStateQueue = DispatchQueue(
            label: "com.maktabah.cloudkitsync.fetch-state"
        )
        var changedRecords: [CKRecord] = []
        var deletedRecordIds: [CKRecord.ID] = []

        core.fetchChanges(
            previousToken: previousToken,
            recordChanged: { record in
                fetchStateQueue.sync { changedRecords.append(record) }
            },
            recordDeleted: { recordId in
                fetchStateQueue.sync { deletedRecordIds.append(recordId) }
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let (finalToken, moreComing)):
                    let records = fetchStateQueue.sync { changedRecords }
                    let deletes = fetchStateQueue.sync { deletedRecordIds }

                    if !records.isEmpty || !deletes.isEmpty {
                        self.applyChangesLocally(
                            recordsToSave: records,
                            recordIDsToDelete: deletes
                        )
                    }

                    if let token = finalToken {
                        self.core.saveToken(token)
                    }

                    self.core.setSyncing(false) {
                        if moreComing {
                            self.fetchChanges(retryCount: 0)
                        }
                    }
                case .failure(let error):
                    self.handleCloudKitError(
                        error,
                        operationType: .fetchChanges,
                        retryCount: retryCount
                    )
                    self.core.setSyncing(false)
                }
            }
        )
    }

    private func applyChangesLocally(
        recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID]
    ) {
        var annotations: [Annotation] = []
        var folders: [SyncFolder] = []
        var searchResults: [SyncResult] = []
        var historyEntries: [ReadingEntry] = []

        for record in recordsToSave {
            if record.recordType == AnnotationSyncHandler.recordType {
                if let ann = AnnotationSyncHandler.parse(from: record) {
                    annotations.append(ann)
                }
            } else if record.recordType == ResultSyncHandler.folderRecordType {
                if let folder = ResultSyncHandler.parseFolder(from: record) {
                    folders.append(folder)
                }
            } else if record.recordType == ResultSyncHandler.resultRecordType {
                if let res = ResultSyncHandler.parseResult(from: record) {
                    searchResults.append(res)
                }
            } else if record.recordType == HistorySyncHandler.recordType {
                if let entry = HistorySyncHandler.parse(from: record) {
                    historyEntries.append(entry)
                }
            }
        }

        let idsToDelete = recordIDsToDelete.map { $0.recordName }

        if !annotations.isEmpty || !idsToDelete.isEmpty {
            AnnotationManager.shared.applyCloudKitChanges(
                annotationsToSave: annotations,
                recordIdsToDelete: idsToDelete
            )
        }

        if !folders.isEmpty || !idsToDelete.isEmpty {
            ResultsHandler.shared.applyCloudKitFolderChanges(
                foldersToSave: folders,
                recordIdsToDelete: idsToDelete
            )
        }

        if !searchResults.isEmpty || !idsToDelete.isEmpty {
            ResultsHandler.shared.applyCloudKitResultChanges(
                resultsToSave: searchResults,
                recordIdsToDelete: idsToDelete
            )
        }

        if !historyEntries.isEmpty || !idsToDelete.isEmpty {
            HistoryViewModel.shared.applyCloudKitChanges(
                entriesToSave: historyEntries,
                recordIdsToDelete: idsToDelete
            )
        }
    }

    // MARK: - Error Handling
    private enum CKOperationType {
        case fetchChanges, upload, delete, subscribe
    }

    private func resolveServerRecordConflict(
        ckError: CKError,
        pendingRecordIds: [String] = [],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let serverRecord = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord,
              let localRecord = ckError.userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord else {
            completion?(.failure(ckError))
            return
        }

        let recordId = localRecord.recordID.recordName
        let serverLastModified = serverRecord["lastModified"] as? Int64 ?? 0
        let localLastModified = localRecord["lastModified"] as? Int64 ?? 0

        if localLastModified >= serverLastModified {
            for key in localRecord.allKeys() {
                serverRecord[key] = localRecord[key]
            }

            core.upload(records: [serverRecord]) { [weak self] result in
                if case .success = result {
                    self?.removePendingUploads([recordId])
                }
                completion?(result)
            }
        } else {
            applyChangesLocally(recordsToSave: [serverRecord], recordIDsToDelete: [])
            removePendingUploads([recordId])
            completion?(.success(()))
        }
    }

    private func handleUploadFailure(
        _ error: Error,
        pendingRecordIds: [String],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let ckError = error as? CKError else {
            completion?(.failure(error))
            return
        }

        switch ckError.code {
        case .serverRecordChanged:
            resolveServerRecordConflict(ckError: ckError, pendingRecordIds: pendingRecordIds, completion: completion)
        case .partialFailure:
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                let conflicts = partialErrors.values.compactMap { $0 as? CKError }.filter { $0.code == .serverRecordChanged }

                if !conflicts.isEmpty {
                    let group = DispatchGroup()
                    var lastError: Error?

                    for conflict in conflicts {
                        group.enter()
                        resolveServerRecordConflict(ckError: conflict) { result in
                            if case .failure(let err) = result { lastError = err }
                            group.leave()
                        }
                    }
                    
                    group.notify(queue: syncQueue) {
                        completion?(lastError.map { .failure($0) } ?? .success(()))
                    }
                } else {
                    // Non-conflict partial failure - retry pending uploads
                    self.retryPendingUploads()
                    completion?(.failure(error))
                }
            } else {
                // Partial failure without specific errors - retry pending uploads
                self.retryPendingUploads()
                completion?(.failure(error))
            }
        case .networkUnavailable, .networkFailure:
            // Network offline - retry pending uploads when connection returns
            retryPendingUploads()
            completion?(.failure(error))
        default:
            // Other errors - retry pending uploads as safety net
            retryPendingUploads()
            completion?(.failure(error))
        }
    }

    private func handleCloudKitError(_ error: Error, operationType: CKOperationType, retryCount: Int = 0) {
        guard let ckError = error as? CKError else { return }

        switch ckError.code {
        case .changeTokenExpired:
            resetChangeToken()
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            let baseDelay = ckError.retryAfterSeconds ?? 3.0
            let retryDelay = baseDelay * pow(2.0, Double(retryCount))
            if retryCount < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                    switch operationType {
                    case .fetchChanges: self.fetchChanges(retryCount: retryCount + 1)
                    case .delete, .upload: self.retryPendingDeletes()
                    default: break
                    }
                }
            }
        case .networkUnavailable, .networkFailure:
            // Network offline - retry deletes when connection returns
            retryPendingDeletes()
        case .zoneNotFound:
            initializeOnLaunch()
        case .serverRecordChanged:
            resolveServerRecordConflict(ckError: ckError)
        case .notAuthenticated:
            DispatchQueue.main.async {
                ReusableFunc.showAlert(title: "iCloud Error", message: ckError.localizedDescription)
            }
        default: break
        }
    }

    // MARK: - Account Utilities
    func resetSyncingKey(syncing: Bool, completion: (() -> Void)? = nil) {
        core.setSyncing(syncing, completion: completion)
    }

    private func checkUserIdentityChange() {
        core.container.fetchUserRecordID { [weak self] recordID, _ in
            guard let self = self, let currentID = recordID?.recordName else { return }
            let lastID = UserDefaults.standard.string(forKey: "CloudKitSyncManager_LastUserRecordID")
            if let lastID = lastID, lastID != currentID {
                self.resetChangeToken()
            }
            UserDefaults.standard.set(currentID, forKey: "CloudKitSyncManager_LastUserRecordID")
        }
    }

    private func subscribeToChanges() {
        let subscriptionId = "AnnotationsZoneSubscription"
        let subscription = CKRecordZoneSubscription(zoneID: core.zoneId, subscriptionID: subscriptionId)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
        operation.qualityOfService = .utility
        core.privateDatabase.add(operation)
    }

    func resetChangeToken() {
        AnnotationManager.shared.db?.checkpoint()
        ResultsHandler.shared.db?.checkpoint()
        core.resetToken()
        fetchChanges()
    }
}
