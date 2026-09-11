//
//  CloudKitSyncManager.swift
//  Maktabah
//

import CloudKit
import Foundation
import Network
import Synchronization

/// Manajer sinkronisasi tingkat tinggi yang mengoordinasikan CloudKit, debounce upload,
/// resolusi konflik, dan pelacakan pending sync secara thread-safe di Swift 6.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
final class CloudKitSyncManager: Sendable {
    static let shared = CloudKitSyncManager()

    typealias SyncTarget = PendingSyncCoordinator.SyncTarget
    typealias SyncProgress = (@Sendable (Result<Void, any Error>) -> Void)?

    private enum ResultsUploadItem: CloudKitSyncable, Sendable {
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

    private var core: CloudKitCoreManager {
        CloudKitCoreManager.shared
    }

    private let pendingCoordinator = PendingSyncCoordinator.shared
    private let annotationDebouncer = CloudKitUploadDebouncer<Annotation>()
    private let resultsDebouncer = CloudKitUploadDebouncer<ResultsUploadItem>()
    private let historyDebouncer = CloudKitUploadDebouncer<ReadingEntry>()

    /// State mutable dibungkus dengan Mutex untuk keamanan konkurensi Swift 6 tanpa @unchecked Sendable
    private let accountChangeTask = Mutex<Task<Void, Never>?>(nil)
    private let retryState = Mutex<(isRunning: Bool, pendingRetryCount: Int?)>((false, nil))
    private let isSyncingLock = Mutex<Void>(())

    private init() {
        setupAccountChangeObserver()
        setupNetworkMonitor()
    }

    deinit {
        accountChangeTask.withLock { task in
            task?.cancel()
            task = nil
        }
    }

    private func setupNetworkMonitor() {
        Task.detached { [weak self] in
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

    private func setupAccountChangeObserver() {
        let task = Task.detached { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard !Task.isCancelled else { break }
                self?.resetChangeToken()
            }
        }
        accountChangeTask.withLock { $0 = task }
    }

    // MARK: - Retry Coalescing

    func retryAllPendingOperations(retryCount: Int = 0) {
        guard AppConfig.useICloud else { return }

        let shouldStart = retryState.withLock { state -> Bool in
            if state.isRunning {
                state.pendingRetryCount = retryCount
                return false
            } else {
                state.isRunning = true
                state.pendingRetryCount = nil
                return true
            }
        }
        guard shouldStart else { return }

        Task.detached { [weak self] in
            await self?.runRetryCoalescingLoop(retryCount: retryCount)
        }
    }

    private func runRetryCoalescingLoop(retryCount: Int) async {
        var currentRetryCount = retryCount
        while true {
            await performRetrySequence(retryCount: currentRetryCount)

            let next = retryState.withLock { state -> Int? in
                if let pending = state.pendingRetryCount {
                    state.pendingRetryCount = nil
                    return pending
                } else {
                    state.isRunning = false
                    return nil
                }
            }
            guard let next else { break }
            currentRetryCount = next
        }
    }

    private func performRetrySequence(retryCount: Int) async {
        await retryPendingUploads(retryCount: retryCount)
        await retryPendingDeletes(retryCount: retryCount)
    }

    private func retryPendingUploads(retryCount: Int = 0) async {
        let batch = await pendingCoordinator.preparePendingUploads()
        guard !batch.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            if !batch.annotations.isEmpty {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await withCheckedContinuation { continuation in
                        self.upload(annotations: batch.annotations, debounce: false, retryCount: retryCount, trackPending: false) { _ in
                            continuation.resume()
                        }
                    }
                }
            }
            if !batch.folders.isEmpty || !batch.results.isEmpty {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await withCheckedContinuation { continuation in
                        self.uploadResultsData(folders: batch.folders, results: batch.results, debounce: false, retryCount: retryCount, trackPending: false) { _ in
                            continuation.resume()
                        }
                    }
                }
            }
            if !batch.history.isEmpty {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await withCheckedContinuation { continuation in
                        self.uploadHistory(entries: batch.history, debounce: false, retryCount: retryCount, trackPending: false) { _ in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    private func retryPendingDeletes(retryCount: Int = 0) async {
        let deletes = await pendingCoordinator.fetchPendingDeletes()
        guard !deletes.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            if !deletes.annotationIds.isEmpty {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await withCheckedContinuation { continuation in
                        self.delete(ckRecordIds: deletes.annotationIds, target: .annotation, trackPending: false, retryCount: retryCount) { _ in
                            continuation.resume()
                        }
                    }
                }
            }
            if !deletes.resultIds.isEmpty {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await withCheckedContinuation { continuation in
                        self.delete(ckRecordIds: deletes.resultIds, target: .result, trackPending: false, retryCount: retryCount) { _ in
                            continuation.resume()
                        }
                    }
                }
            }
            if !deletes.historyIds.isEmpty {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await withCheckedContinuation { continuation in
                        self.delete(ckRecordIds: deletes.historyIds, target: .history, trackPending: false, retryCount: retryCount) { _ in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Launch & Zone Initialization

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
                self?.retryAllPendingOperations()
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
        Task.detached { [weak self] in
            guard let self else { return }
            await performInitialUploadCheckAsync()
        }
    }

    private func performInitialUploadCheckAsync() async {
        let isInitialUpload = !UserDefaults.standard.bool(forKey: "CloudKitSyncManager_InitialUploadDone")

        if let _ = AnnotationRepository.shared.db {
            try? AnnotationStore.shared.backfillCloudKitFieldsIfNeeded { [weak self] backfilled in
                if !isInitialUpload, !backfilled.isEmpty {
                    self?.upload(annotations: backfilled, debounce: false)
                }
            }
        }

        if let _ = ResultsHandler.shared.db {
            try? ResultsHandler.shared.backfillResultsCloudKitFieldsIfNeeded(uploadIfNeeded: !isInitialUpload)
        }

        await HistoryViewModel.shared.backfillCloudKitFieldsIfNeeded { [weak self] backfilled in
            if !isInitialUpload, !backfilled.isEmpty {
                self?.uploadHistory(entries: backfilled, debounce: false)
            }
        }

        if isInitialUpload {
            uploadAllLocalData { success in
                if success {
                    UserDefaults.standard.set(true, forKey: "CloudKitSyncManager_InitialUploadDone")
                }
            }
        }
    }

    private func uploadAllLocalData(completion: @escaping @Sendable (Bool) -> Void) {
        Task.detached { [weak self] in
            guard let self else {
                await MainActor.run { completion(false) }
                return
            }
            let success = await uploadAllLocalDataAsync()
            await MainActor.run {
                completion(success)
            }
        }
    }

    private func uploadAllLocalDataAsync() async -> Bool {
        let batchSize = 200
        var allSucceeded = true

        let allAnnotations = AnnotationStore.shared.loadAnnotations()
        for batch in allAnnotations.chunked(into: batchSize) {
            let res: Result<Void, any Error> = await withCheckedContinuation { continuation in
                self.upload(annotations: batch, debounce: false) { result in
                    continuation.resume(returning: result)
                }
            }
            if case .failure = res {
                allSucceeded = false
            }
        }

        let allFolders = ResultsHandler.shared.fetchAllSyncFolders()
        for batch in allFolders.chunked(into: batchSize) {
            let res: Result<Void, any Error> = await withCheckedContinuation { continuation in
                self.uploadResultsData(folders: batch, results: [], debounce: false) { result in
                    continuation.resume(returning: result)
                }
            }
            if case .failure = res {
                allSucceeded = false
            }
        }

        let allResults = ResultsHandler.shared.fetchAllSyncResults()
        for batch in allResults.chunked(into: batchSize) {
            let res: Result<Void, any Error> = await withCheckedContinuation { continuation in
                self.uploadResultsData(folders: [], results: batch, debounce: false) { result in
                    continuation.resume(returning: result)
                }
            }
            if case .failure = res {
                allSucceeded = false
            }
        }

        let allHistory = await HistoryViewModel.shared.getAllEntries()
        for batch in allHistory.chunked(into: batchSize) {
            let res: Result<Void, any Error> = await withCheckedContinuation { continuation in
                self.uploadHistory(entries: batch, debounce: false) { result in
                    continuation.resume(returning: result)
                }
            }
            if case .failure = res {
                allSucceeded = false
            }
        }

        return allSucceeded
    }

    // MARK: - Generic Upload Pipeline

    /// Memperbaiki race condition: `addPendingUploads` dijalankan dan di-await secara terurut
    /// dalam satu Task yang sama sebelum `debouncer.add` dipanggil.
    private func uploadGeneric<T: CloudKitSyncable & Sendable>(
        items: [T],
        debouncer: CloudKitUploadDebouncer<T>,
        target: SyncTarget,
        debounce: Bool = true,
        retryCount: Int = 0,
        trackPending: Bool = true,
        completion: SyncProgress = nil
    ) {
        guard AppConfig.useICloud else {
            completion?(.success(()))
            return
        }

        let pendingIds = items.compactMap(\.ckRecordId)
        let pairedItems = items.pairedWithRecordId

        Task.detached { [weak self] in
            guard let self else { return }

            if trackPending, !pendingIds.isEmpty {
                await pendingCoordinator.addPendingUploads(pendingIds, target: target)
            }

            await debouncer.add(
                items: pairedItems,
                completion: completion,
                debounce: debounce
            ) { [weak self] itemsToUpload, completions in
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
        completion: SyncProgress = nil
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
        completion: SyncProgress = nil
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
        completion: SyncProgress = nil
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
        pendingCompletions: [@Sendable (Result<Void, any Error>) -> Void]
    ) {
        guard !records.isEmpty else {
            Task { @MainActor in
                pendingCompletions.forEach { $0(.success(())) }
            }
            return
        }

        let batchSize = 300
        Task.detached { [weak self] in
            guard let self else { return }
            var lastError: (any Error)?

            await withTaskGroup(of: Result<Void, any Error>.self) { group in
                for batch in records.chunked(into: batchSize) {
                    let ids = batch.map(\.recordID.recordName)
                    group.addTask { [weak self] in
                        guard let self else { return .success(()) }
                        return await withCheckedContinuation { continuation in
                            self.core.upload(records: batch) { [weak self] result in
                                guard let self else {
                                    continuation.resume(returning: .success(()))
                                    return
                                }
                                self.handleUploadResult(
                                    result,
                                    pendingIds: ids,
                                    target: target,
                                    retryCount: retryCount,
                                    completion: { res in
                                        continuation.resume(returning: res)
                                    }
                                )
                            }
                        }
                    }
                }

                for await result in group {
                    if case let .failure(error) = result {
                        lastError = error
                    }
                }
            }

            let finalError = lastError
            await MainActor.run {
                if let error = finalError {
                    pendingCompletions.forEach { $0(.failure(error)) }
                } else {
                    pendingCompletions.forEach { $0(.success(())) }
                }
            }
        }
    }

    private func handleUploadResult(
        _ result: Result<Void, any Error>,
        pendingIds: [String],
        target: SyncTarget,
        retryCount: Int = 0,
        completion: SyncProgress
    ) {
        switch result {
        case .success:
            Task.detached { [weak self] in
                await self?.pendingCoordinator.removePendingSync(pendingIds, target: target)
            }
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

    // MARK: - Deletions

    func delete(
        ckRecordIds: [String],
        target: SyncTarget? = nil,
        trackPending: Bool = true,
        retryCount: Int = 0,
        completion: SyncProgress = nil
    ) {
        guard AppConfig.useICloud, !ckRecordIds.isEmpty else {
            completion?(.success(()))
            return
        }

        let recordIds = ckRecordIds.map { CKRecord.ID(recordName: $0, zoneID: core.zoneId) }
        let batchSize = 300

        Task.detached { [weak self] in
            guard let self else {
                completion?(.success(()))
                return
            }

            if trackPending, let target {
                await self.pendingCoordinator.addPendingDeletes(ckRecordIds, target: target)
            }

            let finalError = await self.performBatchDeletions(
                recordIds: recordIds,
                batchSize: batchSize,
                target: target,
                retryCount: retryCount
            )

            await MainActor.run {
                if let error = finalError {
                    completion?(.failure(error))
                } else {
                    completion?(.success(()))
                }
            }
        }
    }

    private func performBatchDeletions(
        recordIds: [CKRecord.ID],
        batchSize: Int,
        target: SyncTarget?,
        retryCount: Int
    ) async -> (any Error)? {
        var lastError: (any Error)?
        await withTaskGroup(of: Result<Void, any Error>.self) { group in
            for batch in recordIds.chunked(into: batchSize) {
                group.addTask { [weak self] in
                    guard let self else { return .success(()) }
                    return await self.executeDeleteBatch(batch, target: target, retryCount: retryCount)
                }
            }

            for await res in group {
                if case let .failure(err) = res {
                    lastError = err
                }
            }
        }
        return lastError
    }

    private func executeDeleteBatch(
        _ batch: [CKRecord.ID],
        target: SyncTarget?,
        retryCount: Int
    ) async -> Result<Void, any Error> {
        let batchStrIds = batch.map(\.recordName)
        return await withCheckedContinuation { continuation in
            core.delete(recordIds: batch) { [weak self] result in
                switch result {
                case .success:
                    if let target {
                        Task.detached { [weak self] in
                            await self?.pendingCoordinator.removePendingSync(batchStrIds, target: target)
                        }
                    }
                    continuation.resume(returning: .success(()))
                case let .failure(error):
                    self?.handleDeleteFailure(error, batchStrIds: batchStrIds, target: target, retryCount: retryCount)
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    private func handleDeleteFailure(_ error: any Error, batchStrIds: [String], target: SyncTarget?, retryCount: Int) {
        if let ckError = error as? CKError {
            if ckError.code == .partialFailure,
               let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: any Error]
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
                    Task.detached { [weak self] in
                        await self?.pendingCoordinator.removePendingSync(idsToRemove, target: target)
                    }
                }
            } else if ckError.code == .serverRecordChanged || ckError.code == .unknownItem {
                if let target {
                    Task.detached { [weak self] in
                        await self?.pendingCoordinator.removePendingSync(batchStrIds, target: target)
                    }
                }
            }
        }
        handleCloudKitError(error, operationType: .delete, retryCount: retryCount)
    }

    // MARK: - Fetch Changes Pipeline

    private func beginSyncing() -> Bool {
        isSyncingLock.withLock { _ in
            guard !core.isSyncing else { return false }
            core.setSyncing(true)
            return true
        }
    }

    func fetchChanges(retryCount: Int = 0) {
        Task.detached { [weak self] in
            await self?.fetchChangesAsync(retryCount: retryCount)
        }
    }

    func fetchChangesAsync(retryCount: Int = 0) async {
        guard AppConfig.useICloud else { return }
        guard beginSyncing() else { return }
        defer { core.setSyncing(false) }

        var currentToken = core.loadToken()
        var hasMore = true

        while hasMore {
            let collector = Mutex<(records: [CKRecord], deletedIDs: [CKRecord.ID])>((records: [], deletedIDs: []))

            do {
                let (finalToken, moreComing) = try await withCheckedThrowingContinuation { continuation in
                    core.fetchChanges(
                        previousToken: currentToken,
                        recordChanged: { record in
                            collector.withLock { $0.records.append(record) }
                        },
                        recordDeleted: { recordId in
                            collector.withLock { $0.deletedIDs.append(recordId) }
                        },
                        completion: { result in
                            continuation.resume(with: result)
                        }
                    )
                }

                let (records, deletes) = collector.withLock { ($0.records, $0.deletedIDs) }
                var applySuccess = true

                if !records.isEmpty || !deletes.isEmpty {
                    applySuccess = await applyChangesLocally(recordsToSave: records, recordIDsToDelete: deletes)
                }

                if let token = finalToken, applySuccess {
                    core.saveToken(token)
                    currentToken = token
                }

                hasMore = moreComing
            } catch {
                handleCloudKitError(error, operationType: .fetchChanges, retryCount: retryCount)
                break
            }
        }
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
    ) async -> Bool {
        let parsed = parseRecordsToSave(recordsToSave)
        let idsToDelete = recordIDsToDelete.map(\.recordName)
        var success = true

        if !parsed.annotations.isEmpty || !idsToDelete.isEmpty {
            let annSuccess = AnnotationStore.shared.applyCloudKitChanges(
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
            let histSuccess = await HistoryViewModel.shared.applyCloudKitChanges(
                entriesToSave: parsed.historyEntries,
                recordIdsToDelete: idsToDelete
            )
            success = success && histSuccess
        }

        return success
    }

    // MARK: - Conflict Resolution

    private enum CKOperationType {
        case fetchChanges, upload, delete, subscribe
    }

    private func resolveServerRecordConflict(
        ckError: CKError,
        target: SyncTarget,
        pendingRecordIds: [String] = [],
        completion: SyncProgress = nil
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

        if localLastModified >= serverLastModified || abs(localLastModified - serverLastModified) < 5 {
            for key in localRecord.allKeys() {
                serverRecord[key] = localRecord[key]
            }

            core.upload(records: [serverRecord]) { [weak self] result in
                if case .success = result {
                    Task.detached { [weak self] in
                        await self?.pendingCoordinator.removePendingSync([recordId], target: target)
                    }
                }
                completion?(result)
            }
        } else {
            Task.detached { [weak self] in
                defer { completion?(.success(())) }
                if await self?.applyChangesLocally(recordsToSave: [serverRecord], recordIDsToDelete: []) == true {
                    await self?.pendingCoordinator.removePendingSync([recordId], target: target)
                }
            }
        }
    }

    private func handleUploadFailure(
        _ error: any Error,
        pendingRecordIds: [String],
        target: SyncTarget,
        retryCount: Int = 0,
        completion: SyncProgress = nil
    ) {
        guard let ckError = error as? CKError else {
            completion?(.failure(error))
            return
        }

        switch ckError.code {
        case .serverRecordChanged:
            resolveServerRecordConflict(ckError: ckError, target: target, pendingRecordIds: pendingRecordIds, completion: completion)
        case .partialFailure:
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: any Error] {
                let context = PartialUploadContext(
                    partialErrors: partialErrors,
                    pendingRecordIds: pendingRecordIds,
                    target: target,
                    originalError: error,
                    retryCount: retryCount
                )
                handlePartialUploadErrors(context: context, completion: completion)
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

    private struct PartialUploadContext {
        let partialErrors: [CKRecord.ID: any Error]
        let pendingRecordIds: [String]
        let target: SyncTarget
        let originalError: any Error
        let retryCount: Int
    }

    private func handlePartialUploadErrors(
        context: PartialUploadContext,
        completion: SyncProgress
    ) {
        let failedIds = Set(context.partialErrors.keys.map(\.recordName))
        let successfulIds = context.pendingRecordIds.filter { !failedIds.contains($0) }
        if !successfulIds.isEmpty {
            Task.detached { [weak self] in
                await self?.pendingCoordinator.removePendingSync(successfulIds, target: context.target)
            }
        }

        let innerErrors = context.partialErrors.values.compactMap { $0 as? CKError }
        let conflicts = innerErrors.filter { $0.code == .serverRecordChanged }
        let rateLimitErrors = innerErrors.filter { $0.code == .requestRateLimited || $0.code == .serviceUnavailable || $0.code == .zoneBusy }

        if !conflicts.isEmpty {
            resolveMultipleServerRecordConflicts(conflicts: conflicts, target: context.target, completion: completion)
        } else {
            if let firstRateLimit = rateLimitErrors.first {
                handleCloudKitError(firstRateLimit, operationType: .upload, retryCount: context.retryCount)
            } else {
                handleCloudKitError(context.originalError, operationType: .upload, retryCount: context.retryCount)
            }
            completion?(.failure(context.originalError))
        }
    }

    private func resolveMultipleServerRecordConflicts(
        conflicts: [CKError],
        target: SyncTarget,
        completion: SyncProgress
    ) {
        Task.detached { [weak self] in
            guard let self else {
                completion?(.success(()))
                return
            }
            var lastError: (any Error)?

            await withTaskGroup(of: Result<Void, any Error>.self) { group in
                for conflict in conflicts {
                    group.addTask { [weak self] in
                        guard let self else { return .success(()) }
                        return await withCheckedContinuation { continuation in
                            self.resolveServerRecordConflict(ckError: conflict, target: target) { result in
                                continuation.resume(returning: result)
                            }
                        }
                    }
                }

                for await result in group {
                    if case let .failure(error) = result {
                        lastError = error
                    }
                }
            }

            completion?(lastError.map { .failure($0) } ?? .success(()))
        }
    }

    // MARK: - Rate Limit & General Error Handling

    private func scheduleRateLimitRetry(error: CKError, operationType: CKOperationType, retryCount: Int) -> Bool {
        switch error.code {
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            let baseDelay = error.retryAfterSeconds ?? 3.0
            let retryDelay = baseDelay * pow(2.0, Double(retryCount))
            if retryCount < 5 {
                Task.detached { [weak self] in
                    try? await Task.sleep(for: .seconds(retryDelay))
                    guard let self else { return }
                    switch operationType {
                    case .fetchChanges:
                        fetchChanges(retryCount: retryCount + 1)
                    case .delete, .upload:
                        retryAllPendingOperations(retryCount: retryCount + 1)
                    default:
                        break
                    }
                }
            }
            return true
        default:
            return false
        }
    }

    private func handlePartialFailureError(ckError: CKError, operationType: CKOperationType, retryCount: Int) -> Bool {
        guard let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: any Error] else { return false }
        for innerError in partialErrors.values {
            if let innerCKError = innerError as? CKError,
               scheduleRateLimitRetry(error: innerCKError, operationType: operationType, retryCount: retryCount)
            {
                return true
            }
        }
        return false
    }

    private func handleCloudKitError(_ error: any Error, operationType: CKOperationType, retryCount: Int = 0) {
        guard let ckError = error as? CKError else { return }

        if scheduleRateLimitRetry(error: ckError, operationType: operationType, retryCount: retryCount) {
            return
        }

        switch ckError.code {
        case .changeTokenExpired:
            resetChangeToken()
        case .partialFailure:
            _ = handlePartialFailureError(ckError: ckError, operationType: operationType, retryCount: retryCount)
        case .zoneNotFound:
            initializeOnLaunch()
        case .notAuthenticated:
            Task { @MainActor in
                ReusableFunc.showAlert(title: "iCloud Error", message: ckError.localizedDescription)
            }
        default:
            break
        }
    }

    func resetSyncingKey(syncing: Bool, completion: (@Sendable () -> Void)? = nil) {
        core.setSyncing(syncing, completion: completion)
    }

    private func checkUserIdentityChange() {
        core.container.fetchUserRecordID { [weak self] recordID, _ in
            guard let self, let currentID = recordID?.recordName else { return }
            let key = "CloudKitSyncManager_LastUserRecordID"
            let lastID = UserDefaults.standard.string(forKey: key)
            if let lastID, lastID != currentID {
                resetChangeToken()
            }
            UserDefaults.standard.set(currentID, forKey: key)
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
        AnnotationRepository.shared.db?.checkpoint()
        ResultsHandler.shared.db?.checkpoint()
        core.resetToken()
        fetchChanges()
    }
}
