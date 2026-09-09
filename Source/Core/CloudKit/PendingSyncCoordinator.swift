//
//  PendingSyncCoordinator.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 09/09/26.
//

import Foundation

/// Actor-isolated coordinator that manages persistent sync pending queues across repositories.
actor PendingSyncCoordinator {
    static let shared = PendingSyncCoordinator()

    enum SyncTarget: Sendable {
        case annotation
        case result
        case history
    }

    struct PendingUploadBatch: Sendable {
        let annotations: [Annotation]
        let folders: [SyncFolder]
        let results: [SyncResult]
        let history: [ReadingEntry]

        var isEmpty: Bool {
            annotations.isEmpty && folders.isEmpty && results.isEmpty && history.isEmpty
        }
    }

    struct PendingDeleteBatch: Sendable {
        let annotationIds: [String]
        let resultIds: [String]
        let historyIds: [String]

        var isEmpty: Bool {
            annotationIds.isEmpty && resultIds.isEmpty && historyIds.isEmpty
        }
    }

    private let uploadKey = "upload"
    private let deleteKey = "delete"

    private init() {}

    func addPendingUploads(_ ids: [String], target: SyncTarget) {
        for id in ids {
            switch target {
            case .annotation:
                try? AnnotationRepository.shared.addPendingSync(ckRecordId: id, operation: uploadKey)
            case .result:
                try? ResultsHandler.shared.addPendingSync(ckRecordId: id, operation: uploadKey)
            case .history:
                try? HistoryDatabaseManager.shared.addPendingSync(ckRecordId: id, operation: uploadKey)
            }
        }
    }

    func addPendingDeletes(_ ids: [String], target: SyncTarget) {
        for id in ids {
            switch target {
            case .annotation:
                try? AnnotationRepository.shared.addPendingSync(ckRecordId: id, operation: deleteKey)
            case .result:
                try? ResultsHandler.shared.addPendingSync(ckRecordId: id, operation: deleteKey)
            case .history:
                try? HistoryDatabaseManager.shared.addPendingSync(ckRecordId: id, operation: deleteKey)
            }
        }
    }

    func removePendingSync(_ ids: [String], target: SyncTarget) {
        switch target {
        case .annotation:
            AnnotationRepository.shared.removePendingSync(ckRecordIds: ids)
        case .result:
            ResultsHandler.shared.removePendingSync(ckRecordIds: ids)
        case .history:
            HistoryDatabaseManager.shared.removePendingSync(ckRecordIds: ids)
        }
    }

    /// Fetches pending uploads, cleans up orphaned entries from the local queue, and returns valid items.
    func preparePendingUploads() -> PendingUploadBatch {
        let annPending = AnnotationRepository.shared.fetchPendingSync(operation: uploadKey)
        let resPending = ResultsHandler.shared.fetchPendingSync(operation: uploadKey)
        let histPending = HistoryDatabaseManager.shared.fetchPendingSync(operation: uploadKey)

        var toUploadAnn: [Annotation] = []
        var toUploadFolders: [SyncFolder] = []
        var toUploadResults: [SyncResult] = []
        var toUploadHist: [ReadingEntry] = []

        if !annPending.isEmpty {
            toUploadAnn = AnnotationRepository.shared.fetchAnnotations(byCkRecordIds: annPending)
            let foundIds = Set(toUploadAnn.compactMap(\.ckRecordId))
            let orphans = annPending.filter { !foundIds.contains($0) }
            if !orphans.isEmpty {
                AnnotationRepository.shared.removePendingSync(ckRecordIds: orphans)
            }
        }

        if !resPending.isEmpty {
            toUploadFolders = ResultsHandler.shared.fetchFolders(byCkRecordIds: resPending)
            toUploadResults = ResultsHandler.shared.fetchResults(byCkRecordIds: resPending)

            let foundFolderIds = Set(toUploadFolders.compactMap(\.ckRecordId))
            let foundResultIds = Set(toUploadResults.compactMap(\.ckRecordId))
            let foundIds = foundFolderIds.union(foundResultIds)
            let orphans = resPending.filter { !foundIds.contains($0) }
            if !orphans.isEmpty {
                ResultsHandler.shared.removePendingSync(ckRecordIds: orphans)
            }
        }

        if !histPending.isEmpty {
            toUploadHist = HistoryDatabaseManager.shared.fetchEntries(byCkRecordIds: histPending)
            let foundIds = Set(toUploadHist.compactMap(\.ckRecordId))
            let orphans = histPending.filter { !foundIds.contains($0) }
            if !orphans.isEmpty {
                HistoryDatabaseManager.shared.removePendingSync(ckRecordIds: orphans)
            }
        }

        return PendingUploadBatch(
            annotations: toUploadAnn,
            folders: toUploadFolders,
            results: toUploadResults,
            history: toUploadHist
        )
    }

    func fetchPendingDeletes() -> PendingDeleteBatch {
        let annPending = AnnotationRepository.shared.fetchPendingSync(operation: deleteKey)
        let resPending = ResultsHandler.shared.fetchPendingSync(operation: deleteKey)
        let histPending = HistoryDatabaseManager.shared.fetchPendingSync(operation: deleteKey)

        return PendingDeleteBatch(
            annotationIds: annPending,
            resultIds: resPending,
            historyIds: histPending
        )
    }
}
