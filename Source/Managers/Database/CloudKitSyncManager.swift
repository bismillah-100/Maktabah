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

    private var core: CloudKitCoreManager {
        CloudKitCoreManager.shared
    }

    private init() {
        setupAccountChangeObserver()
        setupNetworkMonitor()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitor() {
        Task {
            await NetworkMonitor.shared.registerConnectivityCallbacks(
                onRestored: { [weak self] in
                    #if DEBUG
                    print("CloudKitSyncManager: Network restored, retrying pending operations")
                    #endif
                    self?.retryAllPendingOperations()
                }
            )
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

    private func removePendingUploads(_ ids: [String]) {
        AnnotationManager.shared.removePendingSync(ckRecordIds: ids)
        ResultsHandler.shared.removePendingSync(ckRecordIds: ids)
        HistoryViewModel.shared.removePendingSync(ckRecordIds: ids)
    }

    private func addPendingDeletes(_ ids: [String], target: SyncTarget) {
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

    private func removePendingDeletes(_ ids: [String]) {
        AnnotationManager.shared.removePendingSync(ckRecordIds: ids)
        ResultsHandler.shared.removePendingSync(ckRecordIds: ids)
        HistoryViewModel.shared.removePendingSync(ckRecordIds: ids)
    }

    // MARK: - Retry Logic

    private func retryPendingUploads() {
        let annPending = AnnotationManager.shared.fetchPendingSync(operation: "upload")
        let resPending = ResultsHandler.shared.fetchPendingSync(operation: "upload")
        let histPending = HistoryViewModel.shared.fetchPendingSync(operation: "upload")

        guard !annPending.isEmpty || !resPending.isEmpty || !histPending.isEmpty else { return }

        var orphans: [String] = []

        // Paginated or direct DB fetch is recommended here, but we keep existing logic compatible
        if !annPending.isEmpty {
            let allAnnotations = AnnotationManager.shared.loadAnnotations()
            let toUploadAnn = allAnnotations.filter { annPending.contains($0.ckRecordId ?? "") }
            if !toUploadAnn.isEmpty {
                upload(annotations: toUploadAnn)
            }

            let foundIds = Set(toUploadAnn.compactMap(\.ckRecordId))
            orphans.append(contentsOf: annPending.filter { !foundIds.contains($0) })
        }

        if !resPending.isEmpty {
            let allFolders = ResultsHandler.shared.fetchAllSyncFolders()
            let toUploadFolders = allFolders.filter { resPending.contains($0.ckRecordId ?? "") }

            let allResults = ResultsHandler.shared.fetchAllSyncResults()
            let toUploadResults = allResults.filter { resPending.contains($0.ckRecordId ?? "") }

            if !toUploadFolders.isEmpty || !toUploadResults.isEmpty {
                uploadResultsData(folders: toUploadFolders, results: toUploadResults)
            }

            let foundFolderIds = Set(toUploadFolders.compactMap(\.ckRecordId))
            let foundResultIds = Set(toUploadResults.compactMap(\.ckRecordId))
            let foundIds = foundFolderIds.union(foundResultIds)
            orphans.append(contentsOf: resPending.filter { !foundIds.contains($0) })
        }

        if !histPending.isEmpty {
            let allHist = HistoryViewModel.shared.getAllEntries()
            let toUploadHist = allHist.filter { histPending.contains($0.ckRecordId ?? "") }
            if !toUploadHist.isEmpty {
                uploadHistory(entries: toUploadHist)
            }

            let foundIds = Set(toUploadHist.compactMap(\.ckRecordId))
            orphans.append(contentsOf: histPending.filter { !foundIds.contains($0) })
        }

        if !orphans.isEmpty {
            // Orphan & Desync Cleanup: Prune record IDs from pending uploads if the local item no longer exists
            removePendingUploads(orphans)
            AnnotationManager.shared.removePendingSync(ckRecordIds: orphans)
            ResultsHandler.shared.removePendingSync(ckRecordIds: orphans)
            HistoryViewModel.shared.removePendingSync(ckRecordIds: orphans)
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
            case let .failure(error):
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

    private var annotationUploadBuffer: [String: Annotation] = [:]
    private var annotationDebounceTask: DispatchWorkItem?
    private var annotationDebounceCompletions: [(Result<Void, Error>) -> Void] = []

    func upload(
        annotations: [Annotation],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard AppConfig.useICloud else { completion?(.success(())); return }

        // Guarantee immediate persistence into the sync_pending queue before any debounce delays
        let pendingIds = annotations.compactMap(\.ckRecordId)
        if !pendingIds.isEmpty {
            addPendingUploads(pendingIds, target: .annotation)
        }

        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            for ann in annotations {
                if let ckId = ann.ckRecordId {
                    annotationUploadBuffer[ckId] = ann
                }
            }

            if let completion {
                annotationDebounceCompletions.append(completion)
            }

            annotationDebounceTask?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.performDebouncedAnnotationUpload()
            }
            annotationDebounceTask = workItem
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }
    }

    private func performDebouncedAnnotationUpload() {
        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }

            let annotationsToUpload = Array(annotationUploadBuffer.values)
            annotationUploadBuffer.removeAll()

            let records = annotationsToUpload.compactMap {
                $0.toCKRecord(zoneID: self.core.zoneId)
            }

            let pendingCompletions = annotationDebounceCompletions
            annotationDebounceCompletions.removeAll()

            guard !records.isEmpty else {
                pendingCompletions.forEach { $0(.success(())) }
                return
            }

            let ids = records.map(\.recordID.recordName)

            core.upload(records: records) { [weak self] result in
                self?.handleUploadResult(
                    result,
                    pendingIds: ids,
                    target: .annotation,
                    completion: { res in
                        pendingCompletions.forEach { $0(res) }
                    }
                )
            }
        }
    }

    func uploadResultsData(
        folders: [SyncFolder],
        results: [SyncResult],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard AppConfig.useICloud else { completion?(.success(())); return }

        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            var records: [CKRecord] = []
            records.append(
                contentsOf: folders.compactMap {
                    $0.toCKRecord(zoneID: self.core.zoneId)
                }
            )
            records.append(
                contentsOf: results.compactMap {
                    $0.toCKRecord(zoneID: self.core.zoneId)
                }
            )

            guard !records.isEmpty else {
                completion?(.success(()))
                return
            }

            let ids = records.map(\.recordID.recordName)
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
    }

    func uploadHistory(
        entries: [ReadingEntry],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard AppConfig.useICloud else { completion?(.success(())); return }

        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            let records = entries.compactMap { $0.toCKRecord(zoneID: self.core.zoneId) }
            guard !records.isEmpty else {
                completion?(.success(()))
                return
            }

            let ids = records.map(\.recordID.recordName)
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
        case let .failure(error):
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
        if trackPending, let target {
            addPendingDeletes(ckRecordIds, target: target)
        }

        let recordIds = ckRecordIds.map { CKRecord.ID(recordName: $0, zoneID: core.zoneId) }

        core.delete(recordIds: recordIds) { [weak self] result in
            switch result {
            case .success:
                self?.removePendingDeletes(ckRecordIds)
            case let .failure(error):
                if let ckError = error as? CKError, ckError.code == .partialFailure,
                   let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                    var idsToRemove = ckRecordIds.filter { !partialErrors.keys.map(\.recordName).contains($0) }
                    for (recordID, itemError) in partialErrors {
                        if let itemCKError = itemError as? CKError {
                            if itemCKError.code == .unknownItem || itemCKError.code == .serverRecordChanged {
                                idsToRemove.append(recordID.recordName)
                            }
                        }
                    }
                    if !idsToRemove.isEmpty {
                        self?.removePendingDeletes(idsToRemove)
                    }
                } else if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                    self?.removePendingDeletes(ckRecordIds)
                } else if let ckError = error as? CKError, ckError.code == .unknownItem {
                    self?.removePendingDeletes(ckRecordIds)
                }
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
                guard let self else { return }
                switch result {
                case .success(let (finalToken, moreComing)):
                    let records = fetchStateQueue.sync { changedRecords }
                    let deletes = fetchStateQueue.sync { deletedRecordIds }

                    var applySuccess = true
                    if !records.isEmpty || !deletes.isEmpty {
                        applySuccess = self.applyChangesLocally(
                            recordsToSave: records,
                            recordIDsToDelete: deletes
                        )
                    }

                    if let token = finalToken, applySuccess {
                        core.saveToken(token)
                    }

                    core.setSyncing(false) {
                        if moreComing {
                            self.fetchChanges(retryCount: 0)
                        }
                    }
                case let .failure(error):
                    handleCloudKitError(
                        error,
                        operationType: .fetchChanges,
                        retryCount: retryCount
                    )
                    core.setSyncing(false)
                }
            }
        )
    }

    @discardableResult private func applyChangesLocally(
        recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID]
    ) -> Bool {
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

        let idsToDelete = recordIDsToDelete.map(\.recordName)

        var success = true

        if !annotations.isEmpty || !idsToDelete.isEmpty {
            let annSuccess = AnnotationManager.shared.applyCloudKitChanges(
                annotationsToSave: annotations,
                recordIdsToDelete: idsToDelete
            )
            success = success && annSuccess
        }

        if !folders.isEmpty || !idsToDelete.isEmpty {
            let fldSuccess = ResultsHandler.shared.applyCloudKitFolderChanges(
                foldersToSave: folders,
                recordIdsToDelete: idsToDelete
            )
            success = success && fldSuccess
        }

        if !searchResults.isEmpty || !idsToDelete.isEmpty {
            let resSuccess = ResultsHandler.shared.applyCloudKitResultChanges(
                resultsToSave: searchResults,
                recordIdsToDelete: idsToDelete
            )
            success = success && resSuccess
        }

        if !historyEntries.isEmpty || !idsToDelete.isEmpty {
            let histSuccess = HistoryViewModel.shared.applyCloudKitChanges(
                entriesToSave: historyEntries,
                recordIdsToDelete: idsToDelete
            )
            success = success && histSuccess
        }

        return success
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
              let localRecord = ckError.userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord
        else {
            completion?(.failure(ckError))
            return
        }

        let recordId = localRecord.recordID.recordName
        let serverLastModified = serverRecord["lastModified"] as? Int64 ?? 0
        let localLastModified = localRecord["lastModified"] as? Int64 ?? 0

        // Clock drift allowance: prefer safe merge if timestamps are very close
        if localLastModified >= serverLastModified || abs(localLastModified - serverLastModified) < 300 {
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
            if applyChangesLocally(recordsToSave: [serverRecord], recordIDsToDelete: []) {
                removePendingUploads([recordId])
            }
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
                let failedIds = Set(partialErrors.keys.map(\.recordName))
                let successfulIds = pendingRecordIds.filter { !failedIds.contains($0) }
                if !successfulIds.isEmpty { removePendingUploads(successfulIds) }
                let conflicts = partialErrors.values.compactMap { $0 as? CKError }.filter { $0.code == .serverRecordChanged }

                if !conflicts.isEmpty {
                    let group = DispatchGroup()
                    var lastError: Error?

                    for conflict in conflicts {
                        group.enter()
                        resolveServerRecordConflict(ckError: conflict) { result in
                            if case let .failure(err) = result { lastError = err }
                            group.leave()
                        }
                    }

                    group.notify(queue: syncQueue) {
                        completion?(lastError.map { .failure($0) } ?? .success(()))
                    }
                } else {
                    // Non-conflict partial failure - leave as pending to be retried later
                    completion?(.failure(error))
                }
            } else {
                // Partial failure without specific errors - leave as pending
                completion?(.failure(error))
            }
        case .networkUnavailable, .networkFailure:
            // Network offline - network monitor will retry when connection returns
            completion?(.failure(error))
        default:
            // Other errors - leave as pending
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
            // Network offline - network monitor will retry deletes when connection returns
            break
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
            guard let self, let currentID = recordID?.recordName else { return }
            let lastID = UserDefaults.standard.string(forKey: "CloudKitSyncManager_LastUserRecordID")
            if let lastID, lastID != currentID {
                resetChangeToken()
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
