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

    private func retryAllPendingOperations(retryCount: Int = 0) {
        guard AppConfig.useICloud else { return }
        syncQueue.async(flags: .barrier) { [weak self] in
            self?.retryPendingUploads(retryCount: retryCount)
            self?.retryPendingDeletes(retryCount: retryCount)
        }
    }

    // MARK: - Pending Operations Tracking

    private func addPendingUploads(_ ids: [String], target: SyncTarget) {
        for id in ids {
            switch target {
            case .annotation:
                try? AnnotationManager.shared.addPendingSync(ckRecordId: id, operation: "upload")
            case .result:
                try? ResultsHandler.shared.addPendingSync(ckRecordId: id, operation: "upload")
            case .history:
                try? HistoryDatabaseManager.shared.addPendingSync(ckRecordId: id, operation: "upload")
            }
        }
    }

    private func removePendingUploads(_ ids: [String], target: SyncTarget) {
        switch target {
        case .annotation:
            AnnotationManager.shared.removePendingSync(ckRecordIds: ids)
        case .result:
            ResultsHandler.shared.removePendingSync(ckRecordIds: ids)
        case .history:
            HistoryDatabaseManager.shared.removePendingSync(ckRecordIds: ids)
        }
    }

    private func addPendingDeletes(_ ids: [String], target: SyncTarget) {
        for id in ids {
            switch target {
            case .annotation:
                try? AnnotationManager.shared.addPendingSync(ckRecordId: id, operation: "delete")
            case .result:
                try? ResultsHandler.shared.addPendingSync(ckRecordId: id, operation: "delete")
            case .history:
                try? HistoryDatabaseManager.shared.addPendingSync(ckRecordId: id, operation: "delete")
            }
        }
    }

    private func removePendingDeletes(_ ids: [String], target: SyncTarget) {
        switch target {
        case .annotation:
            AnnotationManager.shared.removePendingSync(ckRecordIds: ids)
        case .result:
            ResultsHandler.shared.removePendingSync(ckRecordIds: ids)
        case .history:
            HistoryDatabaseManager.shared.removePendingSync(ckRecordIds: ids)
        }
    }

    // MARK: - Retry Logic

    private func retryPendingUploads(retryCount: Int = 0) {
        let annPending = AnnotationManager.shared.fetchPendingSync(operation: "upload")
        let resPending = ResultsHandler.shared.fetchPendingSync(operation: "upload")
        let histPending = HistoryDatabaseManager.shared.fetchPendingSync(operation: "upload")

        guard !annPending.isEmpty || !resPending.isEmpty || !histPending.isEmpty else { return }

        var annOrphans: [String] = []
        var resOrphans: [String] = []
        var histOrphans: [String] = []

        if !annPending.isEmpty {
            let toUploadAnn = AnnotationManager.shared.fetchAnnotations(byCkRecordIds: annPending)
            if !toUploadAnn.isEmpty {
                upload(annotations: toUploadAnn, debounce: false, retryCount: retryCount, trackPending: false)
            }

            let foundIds = Set(toUploadAnn.compactMap(\.ckRecordId))
            annOrphans = annPending.filter { !foundIds.contains($0) }
        }

        if !resPending.isEmpty {
            let toUploadFolders = ResultsHandler.shared.fetchFolders(byCkRecordIds: resPending)
            let toUploadResults = ResultsHandler.shared.fetchResults(byCkRecordIds: resPending)

            if !toUploadFolders.isEmpty || !toUploadResults.isEmpty {
                uploadResultsData(folders: toUploadFolders, results: toUploadResults, debounce: false, retryCount: retryCount, trackPending: false)
            }

            let foundFolderIds = Set(toUploadFolders.compactMap(\.ckRecordId))
            let foundResultIds = Set(toUploadResults.compactMap(\.ckRecordId))
            let foundIds = foundFolderIds.union(foundResultIds)
            resOrphans = resPending.filter { !foundIds.contains($0) }
        }

        if !histPending.isEmpty {
            let toUploadHist = HistoryDatabaseManager.shared.fetchEntries(byCkRecordIds: histPending)
            if !toUploadHist.isEmpty {
                uploadHistory(entries: toUploadHist, debounce: false, retryCount: retryCount, trackPending: false)
            }

            let foundIds = Set(toUploadHist.compactMap(\.ckRecordId))
            histOrphans = histPending.filter { !foundIds.contains($0) }
        }

        // Prune orphaned records from pending queues to prevent infinite retry loops
        if !annOrphans.isEmpty { removePendingUploads(annOrphans, target: .annotation) }
        if !resOrphans.isEmpty { removePendingUploads(resOrphans, target: .result) }
        if !histOrphans.isEmpty { removePendingUploads(histOrphans, target: .history) }
    }


    private func retryPendingDeletes(retryCount: Int = 0) {
        let annPending = AnnotationManager.shared.fetchPendingSync(operation: "delete")
        let resPending = ResultsHandler.shared.fetchPendingSync(operation: "delete")
        let histPending = HistoryDatabaseManager.shared.fetchPendingSync(operation: "delete")

        if !annPending.isEmpty {
            delete(ckRecordIds: annPending, target: .annotation, trackPending: false, retryCount: retryCount)
        }
        if !resPending.isEmpty {
            delete(ckRecordIds: resPending, target: .result, trackPending: false, retryCount: retryCount)
        }
        if !histPending.isEmpty {
            delete(ckRecordIds: histPending, target: .history, trackPending: false, retryCount: retryCount)
        }
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
        // Jika initial upload belum pernah dilakukan, backfill hanya assign ckRecordId
        // tanpa upload — uploadAllLocalData yang akan handle semuanya sekaligus.
        // Jika initial upload sudah selesai (re-enable), backfill sekaligus upload
        // agar data yang dibuat saat CloudKit off tidak terlewat.
        let isInitialUpload = !UserDefaults.standard.bool(forKey: "CloudKitSyncManager_InitialUploadDone")

        if let _ = AnnotationManager.shared.db {
            try? AnnotationManager.shared.backfillCloudKitFieldsIfNeeded { [weak self] backfilled in
                if !isInitialUpload, !backfilled.isEmpty { self?.upload(annotations: backfilled, debounce: false) }
            }
        }

        if let _ = ResultsHandler.shared.db {
            try? ResultsHandler.shared.backfillResultsCloudKitFieldsIfNeeded(uploadIfNeeded: !isInitialUpload)
        }

        HistoryViewModel.shared.backfillCloudKitFieldsIfNeeded { [weak self] backfilled in
            if !isInitialUpload, !backfilled.isEmpty { self?.uploadHistory(entries: backfilled, debounce: false) }
        }

        if isInitialUpload {
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
        for batch in allAnnotations.chunked(into: batchSize) {
            group.enter()
            upload(annotations: batch, debounce: false) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }

        let allFolders = ResultsHandler.shared.fetchAllSyncFolders()
        for batch in allFolders.chunked(into: batchSize) {
            group.enter()
            uploadResultsData(folders: batch, results: [], debounce: false) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }

        let allResults = ResultsHandler.shared.fetchAllSyncResults()
        for batch in allResults.chunked(into: batchSize) {
            group.enter()
            uploadResultsData(folders: [], results: batch, debounce: false) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }

        let allHistory = HistoryViewModel.shared.getAllEntries()
        for batch in allHistory.chunked(into: batchSize) {
            group.enter()
            uploadHistory(entries: batch, debounce: false) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(!hasError)
        }
    }

    // MARK: - Upload (Insert/Update)

    private enum ResultsUploadItem: CloudKitSyncable {
        case folder(SyncFolder)
        case result(SyncResult)

        var ckRecordId: String? {
            switch self {
            case let .folder(f): f.ckRecordId
            case let .result(r): r.ckRecordId
            }
        }

        func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord? {
            switch self {
            case let .folder(f): f.toCKRecord(zoneID: zoneID)
            case let .result(r): r.toCKRecord(zoneID: zoneID)
            }
        }
    }

    private lazy var annotationDebouncer = CloudKitUploadDebouncer<Annotation>(queue: syncQueue)
    private lazy var resultsDebouncer = CloudKitUploadDebouncer<ResultsUploadItem>(queue: syncQueue)
    private lazy var historyDebouncer = CloudKitUploadDebouncer<ReadingEntry>(queue: syncQueue)

    private func uploadGeneric<T: CloudKitSyncable>(
        items: [T],
        debouncer: CloudKitUploadDebouncer<T>,
        target: SyncTarget,
        debounce: Bool = true,
        retryCount: Int = 0,
        trackPending: Bool = true,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard AppConfig.useICloud else { completion?(.success(())); return }

        let pendingIds = items.compactMap(\.ckRecordId)
        if trackPending, !pendingIds.isEmpty {
            addPendingUploads(pendingIds, target: target)
        }

        let pairedItems = items.pairedWithRecordId

        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            debouncer.add(items: pairedItems, completion: completion, debounce: debounce) { [weak self] itemsToUpload, completions in
                guard let self else { return }
                let records = itemsToUpload.compactMap { $0.toCKRecord(zoneID: self.core.zoneId) }
                executeBatchedRecordsUpload(
                    records: records,
                    target: target,
                    retryCount: retryCount,
                    pendingCompletions: completions
                )
            }
        }
    }

    func upload(
        annotations: [Annotation],
        debounce: Bool = true,
        retryCount: Int = 0,
        trackPending: Bool = true,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        uploadGeneric(
            items: annotations,
            debouncer: annotationDebouncer,
            target: .annotation,
            debounce: debounce,
            retryCount: retryCount,
            trackPending: trackPending,
            completion: completion
        )
    }

    func uploadResultsData(
        folders: [SyncFolder],
        results: [SyncResult],
        debounce: Bool = true,
        retryCount: Int = 0,
        trackPending: Bool = true,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let items = folders.map(ResultsUploadItem.folder) + results.map(ResultsUploadItem.result)
        uploadGeneric(
            items: items,
            debouncer: resultsDebouncer,
            target: .result,
            debounce: debounce,
            retryCount: retryCount,
            trackPending: trackPending,
            completion: completion
        )
    }

    func uploadHistory(
        entries: [ReadingEntry],
        debounce: Bool = true,
        retryCount: Int = 0,
        trackPending: Bool = true,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        uploadGeneric(
            items: entries,
            debouncer: historyDebouncer,
            target: .history,
            debounce: debounce,
            retryCount: retryCount,
            trackPending: trackPending,
            completion: completion
        )
    }

    private func executeBatchedRecordsUpload(
        records: [CKRecord],
        target: SyncTarget,
        retryCount: Int,
        pendingCompletions: [(Result<Void, Error>) -> Void]
    ) {
        guard !records.isEmpty else {
            DispatchQueue.main.async {
                pendingCompletions.forEach { $0(.success(())) }
            }
            return
        }

        let batchSize = 300
        let group = DispatchGroup()
        let errorLock = NSLock()
        var lastError: Error?

        for batch in records.chunked(into: batchSize) {
            let ids = batch.map(\.recordID.recordName)

            group.enter()
            core.upload(records: batch) { [weak self] result in
                guard let self else {
                    group.leave()
                    return
                }
                handleUploadResult(
                    result,
                    pendingIds: ids,
                    target: target,
                    retryCount: retryCount,
                    completion: { res in
                        if case let .failure(err) = res {
                            errorLock.lock()
                            lastError = err
                            errorLock.unlock()
                        }
                        group.leave()
                    }
                )
            }
        }

        group.notify(queue: .main) {
            if let error = lastError {
                pendingCompletions.forEach { $0(.failure(error)) }
            } else {
                pendingCompletions.forEach { $0(.success(())) }
            }
        }
    }

    private func handleUploadResult(
        _ result: Result<Void, Error>,
        pendingIds: [String],
        target: SyncTarget,
        retryCount: Int = 0,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        switch result {
        case .success:
            removePendingUploads(pendingIds, target: target)
            completion?(.success(()))
        case let .failure(error):
            handleUploadFailure(
                error,
                pendingRecordIds: pendingIds,
                target: target,
                retryCount: retryCount,
                completion: completion
            )
        }
    }

    // MARK: - Delete

    func delete(ckRecordIds: [String], target: SyncTarget? = nil, trackPending: Bool = true, retryCount: Int = 0) {
        guard AppConfig.useICloud else { return }
        if trackPending, let target {
            addPendingDeletes(ckRecordIds, target: target)
        }

        let recordIds = ckRecordIds.map { CKRecord.ID(recordName: $0, zoneID: core.zoneId) }
        let batchSize = 300

        for batch in recordIds.chunked(into: batchSize) {
            let batchStrIds = batch.map(\.recordName)

            core.delete(recordIds: batch) { [weak self] result in
                switch result {
                case .success:
                    if let target {
                        self?.removePendingDeletes(batchStrIds, target: target)
                    }
                case let .failure(error):
                    self?.handleDeleteFailure(error, batchStrIds: batchStrIds, target: target, retryCount: retryCount)
                }
            }
        }
    }

    private func handleDeleteFailure(_ error: Error, batchStrIds: [String], target: SyncTarget?, retryCount: Int) {
        if let ckError = error as? CKError {
            if ckError.code == .partialFailure,
               let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error]
            {
                let failedRecordNames = Set(partialErrors.keys.map(\.recordName))
                var idsToRemove = batchStrIds.filter { !failedRecordNames.contains($0) }
                for (recordID, itemError) in partialErrors {
                    if let itemCKError = itemError as? CKError,
                       itemCKError.code == .unknownItem || itemCKError.code == .serverRecordChanged
                    {
                        idsToRemove.append(recordID.recordName)
                    }
                }
                if !idsToRemove.isEmpty, let target {
                    removePendingDeletes(idsToRemove, target: target)
                }
            } else if ckError.code == .serverRecordChanged || ckError.code == .unknownItem {
                if let target {
                    removePendingDeletes(batchStrIds, target: target)
                }
            }
        }
        handleCloudKitError(error, operationType: .delete, retryCount: retryCount)
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
                case let .success((finalToken, moreComing)):
                    let records = fetchStateQueue.sync { changedRecords }
                    let deletes = fetchStateQueue.sync { deletedRecordIds }

                    syncQueue.async {
                        var applySuccess = true
                        if !records.isEmpty || !deletes.isEmpty {
                            applySuccess = self.applyChangesLocally(
                                recordsToSave: records,
                                recordIDsToDelete: deletes
                            )
                        }

                        DispatchQueue.main.async {
                            if let token = finalToken, applySuccess {
                                self.core.saveToken(token)
                            }

                            self.core.setSyncing(false) {
                                if moreComing {
                                    self.fetchChanges(retryCount: 0)
                                }
                            }
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

    private struct ParsedChanges {
        var annotations: [Annotation] = []
        var folders: [SyncFolder] = []
        var searchResults: [SyncResult] = []
        var historyEntries: [ReadingEntry] = []
    }

    private func parseRecordsToSave(_ records: [CKRecord]) -> ParsedChanges {
        var parsed = ParsedChanges()
        for record in records {
            if record.recordType == AnnotationSyncHandler.recordType {
                if let ann = AnnotationSyncHandler.parse(from: record) {
                    parsed.annotations.append(ann)
                }
            } else if record.recordType == ResultSyncHandler.folderRecordType {
                if let folder = ResultSyncHandler.parseFolder(from: record) {
                    parsed.folders.append(folder)
                }
            } else if record.recordType == ResultSyncHandler.resultRecordType {
                if let res = ResultSyncHandler.parseResult(from: record) {
                    parsed.searchResults.append(res)
                }
            } else if record.recordType == HistorySyncHandler.recordType {
                if let entry = HistorySyncHandler.parse(from: record) {
                    parsed.historyEntries.append(entry)
                }
            }
        }
        return parsed
    }

    @discardableResult private func applyChangesLocally(
        recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID]
    ) -> Bool {
        let parsed = parseRecordsToSave(recordsToSave)
        let idsToDelete = recordIDsToDelete.map(\.recordName)
        var success = true

        if !parsed.annotations.isEmpty || !idsToDelete.isEmpty {
            let annSuccess = AnnotationManager.shared.applyCloudKitChanges(
                annotationsToSave: parsed.annotations,
                recordIdsToDelete: idsToDelete
            )
            success = success && annSuccess
        }

        if !parsed.folders.isEmpty || !idsToDelete.isEmpty {
            let fldSuccess = ResultsHandler.shared.applyCloudKitFolderChanges(
                foldersToSave: parsed.folders,
                recordIdsToDelete: idsToDelete
            )
            success = success && fldSuccess
        }

        if !parsed.searchResults.isEmpty || !idsToDelete.isEmpty {
            let resSuccess = ResultsHandler.shared.applyCloudKitResultChanges(
                resultsToSave: parsed.searchResults,
                recordIdsToDelete: idsToDelete
            )
            success = success && resSuccess
        }

        if !parsed.historyEntries.isEmpty || !idsToDelete.isEmpty {
            let histSuccess = HistoryViewModel.shared.applyCloudKitChanges(
                entriesToSave: parsed.historyEntries,
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
        target: SyncTarget,
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
        if localLastModified >= serverLastModified || abs(localLastModified - serverLastModified) < 5 {
            for key in localRecord.allKeys() {
                serverRecord[key] = localRecord[key]
            }

            core.upload(records: [serverRecord]) { [weak self] result in
                if case .success = result {
                    self?.removePendingUploads([recordId], target: target)
                }
                completion?(result)
            }
        } else {
            if applyChangesLocally(recordsToSave: [serverRecord], recordIDsToDelete: []) {
                removePendingUploads([recordId], target: target)
            }
            completion?(.success(()))
        }
    }

    private func handleUploadFailure(
        _ error: Error,
        pendingRecordIds: [String],
        target: SyncTarget,
        retryCount: Int = 0,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let ckError = error as? CKError else {
            completion?(.failure(error))
            return
        }

        switch ckError.code {
        case .serverRecordChanged:
            resolveServerRecordConflict(ckError: ckError, target: target, pendingRecordIds: pendingRecordIds, completion: completion)
        case .partialFailure:
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                handlePartialUploadErrors(
                    partialErrors: partialErrors,
                    pendingRecordIds: pendingRecordIds,
                    target: target,
                    originalError: error,
                    retryCount: retryCount,
                    completion: completion
                )
            } else {
                handleCloudKitError(error, operationType: .upload, retryCount: retryCount)
                completion?(.failure(error))
            }
        case .networkUnavailable, .networkFailure:
            completion?(.failure(error))
        default:
            handleCloudKitError(error, operationType: .upload, retryCount: retryCount)
            completion?(.failure(error))
        }
    }

    private func handlePartialUploadErrors(
        partialErrors: [CKRecord.ID: Error],
        pendingRecordIds: [String],
        target: SyncTarget,
        originalError: Error,
        retryCount: Int,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        let failedIds = Set(partialErrors.keys.map(\.recordName))
        let successfulIds = pendingRecordIds.filter { !failedIds.contains($0) }
        if !successfulIds.isEmpty {
            removePendingUploads(successfulIds, target: target)
        }

        let innerErrors = partialErrors.values.compactMap { $0 as? CKError }
        let conflicts = innerErrors.filter { $0.code == .serverRecordChanged }
        let rateLimitErrors = innerErrors.filter { $0.code == .requestRateLimited || $0.code == .serviceUnavailable || $0.code == .zoneBusy }

        if !conflicts.isEmpty {
            // Resolve conflicts first; skip scheduling a rate-limit retry here to avoid
            // re-uploading records whose conflicts are still in-flight. retryPendingUploads
            // will pick them up again after resolution if rate-limiting is still active.
            resolveMultipleServerRecordConflicts(conflicts: conflicts, target: target, completion: completion)
        } else {
            if let firstRateLimit = rateLimitErrors.first {
                handleCloudKitError(firstRateLimit, operationType: .upload, retryCount: retryCount)
            } else {
                handleCloudKitError(originalError, operationType: .upload, retryCount: retryCount)
            }
            completion?(.failure(originalError))
        }
    }

    private func resolveMultipleServerRecordConflicts(
        conflicts: [CKError],
        target: SyncTarget,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        let group = DispatchGroup()
        let errorLock = NSLock()
        var lastError: Error?

        for conflict in conflicts {
            group.enter()
            resolveServerRecordConflict(ckError: conflict, target: target) { result in
                if case let .failure(err) = result {
                    errorLock.lock()
                    lastError = err
                    errorLock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: syncQueue) {
            completion?(lastError.map { .failure($0) } ?? .success(()))
        }
    }

    private func scheduleRateLimitRetry(error: CKError, operationType: CKOperationType, retryCount: Int) -> Bool {
        switch error.code {
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            let baseDelay = error.retryAfterSeconds ?? 3.0
            let retryDelay = baseDelay * pow(2.0, Double(retryCount))
            if retryCount < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                    guard let self else { return }
                    switch operationType {
                    case .fetchChanges: fetchChanges(retryCount: retryCount + 1)
                    case .delete, .upload: retryAllPendingOperations(retryCount: retryCount + 1)
                    default: break
                    }
                }
            }
            return true
        default:
            return false
        }
    }

    private func handlePartialFailureError(ckError: CKError, operationType: CKOperationType, retryCount: Int) -> Bool {
        guard let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] else { return false }
        for innerError in partialErrors.values {
            if let innerCKError = innerError as? CKError,
               scheduleRateLimitRetry(error: innerCKError, operationType: operationType, retryCount: retryCount)
            {
                return true
            }
        }
        return false
    }

    private func handleCloudKitError(_ error: Error, operationType: CKOperationType, retryCount: Int = 0) {
        guard let ckError = error as? CKError else { return }

        if scheduleRateLimitRetry(error: ckError, operationType: operationType, retryCount: retryCount) {
            return
        }

        switch ckError.code {
        case .changeTokenExpired:
            resetChangeToken()
        case .partialFailure:
            if handlePartialFailureError(ckError: ckError, operationType: operationType, retryCount: retryCount) {
                return
            }
        case .zoneNotFound:
            initializeOnLaunch()
        case .notAuthenticated:
            DispatchQueue.main.async {
                ReusableFunc.showAlert(title: "iCloud Error", message: ckError.localizedDescription)
            }
        default:
            break
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
