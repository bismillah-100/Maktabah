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

    private func removePendingUploads(_ ids: [String]) {
        AnnotationManager.shared.removePendingSync(ckRecordIds: ids)
        ResultsHandler.shared.removePendingSync(ckRecordIds: ids)
        HistoryDatabaseManager.shared.removePendingSync(ckRecordIds: ids)
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

    private func removePendingDeletes(_ ids: [String]) {
        AnnotationManager.shared.removePendingSync(ckRecordIds: ids)
        ResultsHandler.shared.removePendingSync(ckRecordIds: ids)
        HistoryDatabaseManager.shared.removePendingSync(ckRecordIds: ids)
    }

    // MARK: - Retry Logic

    private func retryPendingUploads(retryCount: Int = 0) {
        let annPending = AnnotationManager.shared.fetchPendingSync(operation: "upload")
        let resPending = ResultsHandler.shared.fetchPendingSync(operation: "upload")
        let histPending = HistoryDatabaseManager.shared.fetchPendingSync(operation: "upload")

        guard !annPending.isEmpty || !resPending.isEmpty || !histPending.isEmpty else { return }

        var orphans: [String] = []

        if !annPending.isEmpty {
            let toUploadAnn = AnnotationManager.shared.fetchAnnotations(byCkRecordIds: annPending)
            if !toUploadAnn.isEmpty {
                upload(annotations: toUploadAnn, debounce: false, retryCount: retryCount, trackPending: false)
            }

            let foundIds = Set(toUploadAnn.compactMap(\.ckRecordId))
            orphans.append(contentsOf: annPending.filter { !foundIds.contains($0) })
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
            orphans.append(contentsOf: resPending.filter { !foundIds.contains($0) })
        }

        if !histPending.isEmpty {
            let toUploadHist = HistoryDatabaseManager.shared.fetchEntries(byCkRecordIds: histPending)
            if !toUploadHist.isEmpty {
                uploadHistory(entries: toUploadHist, debounce: false, retryCount: retryCount, trackPending: false)
            }

            let foundIds = Set(toUploadHist.compactMap(\.ckRecordId))
            orphans.append(contentsOf: histPending.filter { !foundIds.contains($0) })
        }

        if !orphans.isEmpty {
            // Prune orphaned records from pending queues if the local item no longer exists in DB to prevent infinite retry loops
            removePendingUploads(orphans)
            AnnotationManager.shared.removePendingSync(ckRecordIds: orphans)
            ResultsHandler.shared.removePendingSync(ckRecordIds: orphans)
            HistoryDatabaseManager.shared.removePendingSync(ckRecordIds: orphans)
        }
    }

    private func retryPendingDeletes(retryCount: Int = 0) {
        let pending = AnnotationManager.shared.fetchPendingSync(operation: "delete") +
            ResultsHandler.shared.fetchPendingSync(operation: "delete") +
            HistoryDatabaseManager.shared.fetchPendingSync(operation: "delete")

        guard !pending.isEmpty else { return }
        delete(ckRecordIds: pending, trackPending: false, retryCount: retryCount)
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
        for i in stride(from: 0, to: allAnnotations.count, by: batchSize) {
            let batch = Array(allAnnotations[i ..< min(i + batchSize, allAnnotations.count)])
            group.enter()
            upload(annotations: batch, debounce: false) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }

        let allFolders = ResultsHandler.shared.fetchAllSyncFolders()
        for i in stride(from: 0, to: allFolders.count, by: batchSize) {
            let batch = Array(allFolders[i ..< min(i + batchSize, allFolders.count)])
            group.enter()
            uploadResultsData(folders: batch, results: [], debounce: false) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }

        let allResults = ResultsHandler.shared.fetchAllSyncResults()
        for i in stride(from: 0, to: allResults.count, by: batchSize) {
            let batch = Array(allResults[i ..< min(i + batchSize, allResults.count)])
            group.enter()
            uploadResultsData(folders: [], results: batch, debounce: false) { result in
                if case .failure = result { hasError = true }
                group.leave()
            }
        }

        let allHistory = HistoryViewModel.shared.getAllEntries()
        for i in stride(from: 0, to: allHistory.count, by: batchSize) {
            let batch = Array(allHistory[i ..< min(i + batchSize, allHistory.count)])
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

    private var annotationUploadBuffer: [String: Annotation] = [:]
    private var annotationDebounceTask: DispatchWorkItem?
    private var annotationDebounceCompletions: [(Result<Void, Error>) -> Void] = []

    func upload(
        annotations: [Annotation],
        debounce: Bool = true,
        retryCount: Int = 0,
        trackPending: Bool = true,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard AppConfig.useICloud else { completion?(.success(())); return }

        // Guarantee immediate persistence into the sync_pending queue before any debounce delays
        let pendingIds = annotations.compactMap(\.ckRecordId)
        if trackPending, !pendingIds.isEmpty {
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

            self.annotationDebounceTask?.cancel()

            if debounce {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.performDebouncedAnnotationUpload(retryCount: retryCount)
                }
                self.annotationDebounceTask = workItem
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0, execute: workItem)
            } else {
                self.performDebouncedAnnotationUpload(retryCount: retryCount)
            }
        }
    }

    private func performDebouncedAnnotationUpload(retryCount: Int = 0) {
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
                DispatchQueue.main.async {
                    pendingCompletions.forEach { $0(.success(())) }
                }
                return
            }

            let batchSize = 300 // explicitly split the payload into smaller chunks
            let group = DispatchGroup()
            let errorLock = NSLock()
            var lastError: Error?

            for i in stride(from: 0, to: records.count, by: batchSize) {
                let batch = Array(records[i ..< min(i + batchSize, records.count)])
                let ids = batch.map(\.recordID.recordName)

                group.enter()
                self.core.upload(records: batch) { [weak self] result in
                    guard let self = self else {
                        group.leave()
                        return
                    }
                    self.handleUploadResult(
                        result,
                        pendingIds: ids,
                        target: .annotation,
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
    }

    private var resultFolderUploadBuffer: [String: SyncFolder] = [:]
    private var resultUploadBuffer: [String: SyncResult] = [:]
    private var resultDebounceTask: DispatchWorkItem?
    private var resultDebounceCompletions: [(Result<Void, Error>) -> Void] = []

    func uploadResultsData(
        folders: [SyncFolder],
        results: [SyncResult],
        debounce: Bool = true,
        retryCount: Int = 0,
        trackPending: Bool = true,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard AppConfig.useICloud else { completion?(.success(())); return }

        let pendingFolderIds = folders.compactMap(\.ckRecordId)
        let pendingResultIds = results.compactMap(\.ckRecordId)
        let pendingIds = pendingFolderIds + pendingResultIds

        if trackPending, !pendingIds.isEmpty {
            addPendingUploads(pendingIds, target: .result)
        }

        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            
            for folder in folders {
                if let ckId = folder.ckRecordId {
                    self.resultFolderUploadBuffer[ckId] = folder
                }
            }
            
            for result in results {
                if let ckId = result.ckRecordId {
                    self.resultUploadBuffer[ckId] = result
                }
            }

            if let completion {
                self.resultDebounceCompletions.append(completion)
            }

            self.resultDebounceTask?.cancel()

            if debounce {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.performDebouncedResultUpload(retryCount: retryCount)
                }
                self.resultDebounceTask = workItem
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0, execute: workItem)
            } else {
                self.performDebouncedResultUpload(retryCount: retryCount)
            }
        }
    }

    private func performDebouncedResultUpload(retryCount: Int = 0) {
        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }

            let foldersToUpload = Array(resultFolderUploadBuffer.values)
            let resultsToUpload = Array(resultUploadBuffer.values)
            resultFolderUploadBuffer.removeAll()
            resultUploadBuffer.removeAll()

            var records: [CKRecord] = []
            records.append(
                contentsOf: foldersToUpload.compactMap {
                    $0.toCKRecord(zoneID: self.core.zoneId)
                }
            )
            records.append(
                contentsOf: resultsToUpload.compactMap {
                    $0.toCKRecord(zoneID: self.core.zoneId)
                }
            )

            let pendingCompletions = resultDebounceCompletions
            resultDebounceCompletions.removeAll()

            guard !records.isEmpty else {
                DispatchQueue.main.async {
                    pendingCompletions.forEach { $0(.success(())) }
                }
                return
            }

            let batchSize = 300 // explicitly split the payload into smaller chunks
            let group = DispatchGroup()
            let errorLock = NSLock()
            var lastError: Error?

            for i in stride(from: 0, to: records.count, by: batchSize) {
                let batch = Array(records[i ..< min(i + batchSize, records.count)])
                let ids = batch.map(\.recordID.recordName)

                group.enter()
                self.core.upload(records: batch) { [weak self] result in
                    guard let self = self else {
                        group.leave()
                        return
                    }
                    self.handleUploadResult(
                        result,
                        pendingIds: ids,
                        target: .result,
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
    }


    private var historyUploadBuffer: [String: ReadingEntry] = [:]
    private var historyDebounceTask: DispatchWorkItem?
    private var historyDebounceCompletions: [(Result<Void, Error>) -> Void] = []

    func uploadHistory(
        entries: [ReadingEntry],
        debounce: Bool = true,
        retryCount: Int = 0,
        trackPending: Bool = true,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard AppConfig.useICloud else { completion?(.success(())); return }

        let pendingIds = entries.compactMap(\.ckRecordId)
        if trackPending, !pendingIds.isEmpty {
            addPendingUploads(pendingIds, target: .history)
        }

        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            for entry in entries {
                if let ckId = entry.ckRecordId {
                    historyUploadBuffer[ckId] = entry
                }
            }

            if let completion {
                historyDebounceCompletions.append(completion)
            }

            self.historyDebounceTask?.cancel()

            if debounce {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.performDebouncedHistoryUpload(retryCount: retryCount)
                }
                self.historyDebounceTask = workItem
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0, execute: workItem)
            } else {
                self.performDebouncedHistoryUpload(retryCount: retryCount)
            }
        }
    }

    private func performDebouncedHistoryUpload(retryCount: Int = 0) {
        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }

            let entriesToUpload = Array(historyUploadBuffer.values)
            historyUploadBuffer.removeAll()

            let records = entriesToUpload.compactMap {
                $0.toCKRecord(zoneID: self.core.zoneId)
            }

            let pendingCompletions = historyDebounceCompletions
            historyDebounceCompletions.removeAll()

            guard !records.isEmpty else {
                DispatchQueue.main.async {
                    pendingCompletions.forEach { $0(.success(())) }
                }
                return
            }

            let batchSize = 300 // explicitly split the payload into smaller chunks
            let group = DispatchGroup()
            let errorLock = NSLock()
            var lastError: Error?

            for i in stride(from: 0, to: records.count, by: batchSize) {
                let batch = Array(records[i ..< min(i + batchSize, records.count)])
                let ids = batch.map(\.recordID.recordName)

                group.enter()
                self.core.upload(records: batch) { [weak self] result in
                    guard let self = self else {
                        group.leave()
                        return
                    }
                    self.handleUploadResult(
                        result,
                        pendingIds: ids,
                        target: .history,
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
            removePendingUploads(pendingIds)
            completion?(.success(()))
        case let .failure(error):
            handleUploadFailure(
                error,
                pendingRecordIds: pendingIds,
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

        let batchSize = 300 // explicitly split the payload into smaller chunks

        for i in stride(from: 0, to: recordIds.count, by: batchSize) {
            let batch = Array(recordIds[i ..< min(i + batchSize, recordIds.count)])
            let batchStrIds = batch.map(\.recordName)

            self.core.delete(recordIds: batch) { [weak self] result in
                switch result {
                case .success:
                    self?.removePendingDeletes(batchStrIds)
                case let .failure(error):
                    if let ckError = error as? CKError, ckError.code == .partialFailure,
                       let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                        let failedRecordNames = Set(partialErrors.keys.map(\.recordName))
                        var idsToRemove = batchStrIds.filter { !failedRecordNames.contains($0) }
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
                        self?.removePendingDeletes(batchStrIds)
                    } else if let ckError = error as? CKError, ckError.code == .unknownItem {
                        self?.removePendingDeletes(batchStrIds)
                    }
                    self?.handleCloudKitError(error, operationType: .delete, retryCount: retryCount)
                }
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

                    self.syncQueue.async {
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
        if localLastModified >= serverLastModified || abs(localLastModified - serverLastModified) < 5 {
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
        retryCount: Int = 0,
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
            // Inspect individual record results in CKPartialErrorsByItemIDKey
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                let failedIds = Set(partialErrors.keys.map(\.recordName))
                let successfulIds = pendingRecordIds.filter { !failedIds.contains($0) }
                // Remove successful record IDs from sync_pending immediately
                if !successfulIds.isEmpty {
                    removePendingUploads(successfulIds)
                }

                let innerErrors = partialErrors.values.compactMap { $0 as? CKError }
                let conflicts = innerErrors.filter { $0.code == .serverRecordChanged }
                let rateLimitErrors = innerErrors.filter { $0.code == .requestRateLimited || $0.code == .serviceUnavailable || $0.code == .zoneBusy }

                // Trigger retry backoff for rate-limit errors regardless of whether
                // conflicts are also present in the same batch.
                if let firstRateLimit = rateLimitErrors.first {
                    handleCloudKitError(firstRateLimit, operationType: .upload, retryCount: retryCount)
                }

                if !conflicts.isEmpty {
                    let group = DispatchGroup()
                    let errorLock = NSLock()
                    var lastError: Error?

                    for conflict in conflicts {
                        group.enter()
                        resolveServerRecordConflict(ckError: conflict) { result in
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
                } else {
                    // Non-conflict partial failure - retain failed record IDs in sync_pending for retry
                    if rateLimitErrors.isEmpty {
                        handleCloudKitError(error, operationType: .upload, retryCount: retryCount)
                    }
                    completion?(.failure(error))
                }
            } else {
                // Partial failure without specific errors - retain failed record IDs in sync_pending for retry
                handleCloudKitError(error, operationType: .upload, retryCount: retryCount)
                completion?(.failure(error))
            }
        case .networkUnavailable, .networkFailure:
            // Network offline - network monitor will retry when connection returns
            completion?(.failure(error))
        default:
            // Other errors - leave as pending
            handleCloudKitError(error, operationType: .upload, retryCount: retryCount)
            completion?(.failure(error))
        }
    }

    private func handleCloudKitError(_ error: Error, operationType: CKOperationType, retryCount: Int = 0) {
        guard let ckError = error as? CKError else { return }

        func processError(_ error: CKError) -> Bool {
            switch error.code {
            case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                let baseDelay = error.retryAfterSeconds ?? 3.0
                let retryDelay = baseDelay * pow(2.0, Double(retryCount))
                if retryCount < 5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                        switch operationType {
                        case .fetchChanges: self.fetchChanges(retryCount: retryCount + 1)
                        case .delete, .upload: self.retryAllPendingOperations(retryCount: retryCount + 1)
                        default: break
                        }
                    }
                }
                return true
            default:
                return false
            }
        }

        switch ckError.code {
        case .changeTokenExpired:
            resetChangeToken()
        case .partialFailure:
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                for innerError in partialErrors.values {
                    if let innerCKError = innerError as? CKError, processError(innerCKError) {
                        return // Retry scheduled
                    }
                }
            }
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            _ = processError(ckError)
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
