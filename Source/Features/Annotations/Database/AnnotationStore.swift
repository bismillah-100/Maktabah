//
//  AnnotationStore.swift
//  Maktabah
//

import Combine
import Foundation
import Synchronization

final class AnnotationStore: Sendable {
    static let shared = AnnotationStore()

    // MARK: - Event Publisher

    nonisolated(unsafe) let events = PassthroughSubject<AnnotationEvent, Never>()

    private func emit(_ event: AnnotationEvent) {
        events.send(event)
    }

    // MARK: - Dependencies

    let repository: AnnotationRepository

    // MARK: - State & Cache

    private struct CacheState: Sendable {
        var cacheById: [Int64: Annotation] = [:]
        var cacheByContent: [ContentKey: [Annotation]] = [:]
        var cacheByBook: [Int: [Annotation]] = [:]
        var cacheTagsByAnnotationId: [Int64: [String]] = [:]
        var cachedAllTagNames: [String]?

        mutating func updateSingleAnnotationCache(_ annotation: Annotation) {
            guard let id = annotation.id else { return }
            cacheById[id] = annotation
            cacheTagsByAnnotationId[id] = annotation.tags

            let key = ContentKey(bkId: annotation.bkId, contentId: annotation.contentId)
            if var arr = cacheByContent[key] {
                if let idx = arr.firstIndex(where: { $0.id == id }) {
                    arr[idx] = annotation
                } else {
                    let idx = arr.insertionIndex(for: annotation) { $0.range.location < $1.range.location }
                    arr.insert(annotation, at: idx)
                }
                cacheByContent[key] = arr
            }

            if var bookArr = cacheByBook[annotation.bkId] {
                if let idx = bookArr.firstIndex(where: { $0.id == id }) {
                    bookArr[idx] = annotation
                } else {
                    bookArr.append(annotation)
                }
                cacheByBook[annotation.bkId] = bookArr
            }
        }
    }

    private let cache = Mutex(CacheState())

    private init(repository: AnnotationRepository = .shared) {
        self.repository = repository
    }

    // MARK: - Setup & Lifecycle

    func setup(at folderURL: URL?) throws {
        let isNewDb = try repository.setupAnnotationsDatabase(at: folderURL)

        clearAllCaches()
        emit(.treeInvalidated)

        if isNewDb {
            CloudKitSyncManager.shared.resetChangeToken()
        }

        let backfilled = try repository.backfillCloudKitFieldsIfNeeded()
        if !backfilled.isEmpty {
            CloudKitSyncManager.shared.upload(annotations: backfilled, debounce: false)
        }
    }

    func connect() {
        repository.connect()
    }

    func disconnect() {
        repository.disconnect()
    }

    func clearAllCaches() {
        cache.withLock { state in
            state = CacheState()
        }
    }

    // MARK: - Loading Annotations

    func loadAnnotations(bkId: Int, contentId: Int) -> [Annotation] {
        let key = ContentKey(bkId: bkId, contentId: contentId)

        let cached = cache.withLock { $0.cacheByContent[key] }
        if let cached {
            return cached
        }

        let loaded = (try? repository.loadAnnotations(bkId: bkId, contentId: contentId)) ?? []

        cache.withLock { state in
            state.cacheByContent[key] = loaded
            for ann in loaded {
                if let id = ann.id {
                    state.cacheById[id] = ann
                    state.cacheTagsByAnnotationId[id] = ann.tags
                }
            }
        }

        return loaded
    }

    func loadAnnotations(bkId: Int) -> [Annotation] {
        let cached = cache.withLock { $0.cacheByBook[bkId] }
        if let cached {
            return cached
        }

        let loaded = (try? repository.loadAnnotations(bkId: bkId)) ?? []

        cache.withLock { state in
            state.cacheByBook[bkId] = loaded
            for ann in loaded {
                if let id = ann.id {
                    state.cacheById[id] = ann
                    state.cacheTagsByAnnotationId[id] = ann.tags
                }
            }
        }

        return loaded
    }

    func loadAnnotations() -> [Annotation] {
        let loaded = (try? repository.loadAllAnnotations()) ?? []

        cache.withLock { state in
            state = CacheState()

            for ann in loaded {
                if let id = ann.id {
                    state.cacheById[id] = ann
                    state.cacheTagsByAnnotationId[id] = ann.tags
                }
                let contentKey = ContentKey(bkId: ann.bkId, contentId: ann.contentId)
                state.cacheByContent[contentKey, default: []].append(ann)
                state.cacheByBook[ann.bkId, default: []].append(ann)
            }
        }

        return loaded
    }

    func loadAnnotationById(_ id: Int64) -> Annotation? {
        let cached = cache.withLock { $0.cacheById[id] }
        if let cached {
            return cached
        }

        guard let loaded = try? repository.loadAnnotationById(id) else {
            return nil
        }

        cache.withLock { state in
            state.cacheById[id] = loaded
            state.cacheTagsByAnnotationId[id] = loaded.tags
        }

        return loaded
    }

    // MARK: - Mutation Operations

    @discardableResult
    func addAnnotation(_ annotation: Annotation) throws -> Int64 {
        let (rowId, saved) = try repository.addAnnotation(annotation)

        updateCacheAfterAdd(saved)
        pushRecentColor(saved)

        CloudKitSyncManager.shared.upload(annotations: [saved], trackPending: false)
        emit(.added(saved))

        return rowId
    }

    func updateAnnotation(_ annotation: Annotation) throws {
        let updated = try repository.updateAnnotationRow(annotation)

        updateCacheAfterUpdate(updated)
        pushRecentColor(updated)

        CloudKitSyncManager.shared.upload(annotations: [updated], trackPending: false)
        emit(.updated(updated))
    }

    func deleteAnnotation(id: Int64) throws {
        let deleted = try repository.deleteAnnotationRow(id: id)

        updateCacheAfterDelete(id: id, annotation: deleted)

        if let ckId = deleted?.ckRecordId {
            CloudKitSyncManager.shared.delete(ckRecordIds: [ckId], target: .annotation, trackPending: false)
        }

        emit(.deleted(id: id, annotation: deleted))
    }

    @discardableResult
    func updateAnnotationsBookId(oldId: Int, newId: Int) throws -> [Annotation] {
        let updated = try repository.updateAnnotationsBookId(oldId: oldId, newId: newId)

        clearAllCaches()

        if !updated.isEmpty {
            CloudKitSyncManager.shared.upload(annotations: updated, trackPending: false)
        }

        emit(.treeInvalidated)
        return updated
    }

    // MARK: - Tags

    func allTagNames() -> [String] {
        let cached = cache.withLock { $0.cachedAllTagNames }
        if let cached {
            return cached
        }

        let loaded = (try? repository.fetchAllTagNames()) ?? []

        cache.withLock { state in
            state.cachedAllTagNames = loaded
        }

        return loaded
    }

    func addTag(_ tag: String, toAnnotationIDs: [Int64]) throws {
        let updated = try repository.addTag(tag, toAnnotationIDs: toAnnotationIDs)
        applyBatchTagUpdates(updated)
    }

    func removeTag(_ tag: String, fromAnnotationIDs: [Int64]) throws {
        let updated = try repository.removeTag(tag, fromAnnotationIDs: fromAnnotationIDs)
        applyBatchTagUpdates(updated)
    }

    func renameTag(from oldName: String, to newName: String) throws {
        let updated = try repository.renameTag(from: oldName, to: newName)
        applyBatchTagUpdates(updated)
    }

    func deleteTag(named tagName: String) throws {
        let (_, updated) = try repository.deleteTag(named: tagName)
        applyBatchTagUpdates(updated)
    }

    private func applyBatchTagUpdates(_ annotations: [Annotation]) {
        guard !annotations.isEmpty else { return }

        cache.withLock { state in
            state.cachedAllTagNames = nil
            for annotation in annotations {
                state.updateSingleAnnotationCache(annotation)
            }
        }

        CloudKitSyncManager.shared.upload(annotations: annotations, trackPending: false)
        emit(.batchUpdated(annotations))
    }

    // MARK: - CloudKit Sync

    @discardableResult
    func applyCloudKitChanges(annotationsToSave: [Annotation], recordIdsToDelete: [String]) -> Bool {
        var deletedAnnotations: [Annotation] = []
        var addedAnnotations: [Annotation] = []
        var updatedAnnotations: [Annotation] = []

        do {
            try repository.transaction {
                deletedAnnotations = try self.repository.applyCloudKitDeletions(recordIdsToDelete: recordIdsToDelete)
                let saves = try self.repository.applyCloudKitSaves(annotationsToSave: annotationsToSave)
                addedAnnotations = saves.added
                updatedAnnotations = saves.updated
                try self.repository.deleteUnusedTags()
            }

            let totalChanges = addedAnnotations.count + updatedAnnotations.count + deletedAnnotations.count

            if totalChanges > 0, totalChanges < 100 {
                applyIncrementalCloudKitCache(
                    added: addedAnnotations,
                    updated: updatedAnnotations,
                    deleted: deletedAnnotations
                )

                for ann in deletedAnnotations {
                    if let id = ann.id {
                        emit(.deleted(id: id, annotation: ann))
                    }
                }
                for ann in addedAnnotations {
                    emit(.added(ann))
                }
                for ann in updatedAnnotations {
                    emit(.updated(ann))
                }
            } else if totalChanges >= 100 {
                clearAllCaches()
                emit(.treeInvalidated)
            }
        } catch {
            print("AnnotationStore: Failed to apply CloudKit changes - \(error)")
            return false
        }

        return true
    }

    func nukeDatabase() {
        do {
            try repository.nukeDatabase()
            clearAllCaches()
            emit(.treeInvalidated)
            #if DEBUG
            print("AnnotationStore: Local database purged.")
            #endif
        } catch {
            print("AnnotationStore: Failed to purge database - \(error)")
        }
    }

    func backfillCloudKitFieldsIfNeeded(completion: (([Annotation]) -> Void)? = nil) throws {
        let backfilled = try repository.backfillCloudKitFieldsIfNeeded()
        completion?(backfilled)
    }

    // MARK: - Import Operations

    @discardableResult
    func importAnnotations(_ annotations: [Annotation], overwrite: Bool = true) throws -> Int {
        guard !annotations.isEmpty else { return 0 }

        let (count, modified) = try repository.importAnnotations(annotations, overwrite: overwrite)

        if count > 0 {
            clearAllCaches()
            emit(.treeInvalidated)
            CloudKitSyncManager.shared.upload(annotations: modified, debounce: true)
        }

        return count
    }

    // MARK: - Cache Helpers

    private func updateCacheAfterAdd(_ annotation: Annotation) {
        cache.withLock { state in
            state.cachedAllTagNames = nil
            state.updateSingleAnnotationCache(annotation)
        }
    }

    private func updateCacheAfterUpdate(_ annotation: Annotation) {
        cache.withLock { state in
            state.cachedAllTagNames = nil
            state.updateSingleAnnotationCache(annotation)
        }
    }

    private func updateCacheAfterDelete(id: Int64, annotation: Annotation?) {
        cache.withLock { state in
            state.cachedAllTagNames = nil
            state.cacheById.removeValue(forKey: id)
            state.cacheTagsByAnnotationId.removeValue(forKey: id)
            if let bkId = annotation?.bkId {
                state.cacheByBook[bkId] = state.cacheByBook[bkId]?.filter { $0.id != id }
            }
            for (key, anns) in state.cacheByContent {
                if let idx = anns.firstIndex(where: { $0.id == id }) {
                    var copy = anns
                    copy.remove(at: idx)
                    state.cacheByContent[key] = copy
                }
            }
        }
    }

    private func applyIncrementalCloudKitCache(
        added: [Annotation],
        updated: [Annotation],
        deleted: [Annotation]
    ) {
        let allChanged = added + updated + deleted
        let affectedContentKeys = Set(allChanged.map { ContentKey(bkId: $0.bkId, contentId: $0.contentId) })
        let affectedBookIds = Set(allChanged.map(\.bkId))

        cache.withLock { state in
            state.cachedAllTagNames = nil

            for ann in deleted {
                guard let id = ann.id else { continue }
                state.cacheById.removeValue(forKey: id)
                state.cacheTagsByAnnotationId.removeValue(forKey: id)
            }

            for ann in added + updated {
                guard let id = ann.id else { continue }
                state.cacheById[id] = ann
                state.cacheTagsByAnnotationId[id] = ann.tags
            }

            for key in affectedContentKeys {
                state.cacheByContent.removeValue(forKey: key)
            }
            for bkId in affectedBookIds {
                state.cacheByBook.removeValue(forKey: bkId)
            }
        }
    }

    func pushRecentColor(_ annotation: Annotation) {
        if annotation.type == .highlight,
           let color = PlatformColor(hex: annotation.colorHex)
        {
            if Thread.isMainThread {
                TextViewState.shared.pushRecentHighlightColor(color)
            } else {
                DispatchQueue.main.async {
                    TextViewState.shared.pushRecentHighlightColor(color)
                }
            }
        }
    }
}
