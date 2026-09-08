//
//  AnnotationStore.swift
//  Maktabah
//

import Combine
import Foundation

final class AnnotationStore: @unchecked Sendable {
    static let shared = AnnotationStore()

    // MARK: - Event Publisher

    let events = PassthroughSubject<AnnotationEvent, Never>()
    private let eventLock = NSLock()

    private func emit(_ event: AnnotationEvent) {
        eventLock.lock()
        events.send(event)
        eventLock.unlock()
    }

    // MARK: - Dependencies

    let repository: AnnotationRepository

    // MARK: - Queues & Caches

    private let cacheQueue = DispatchQueue(label: "com.maktab.annotationStore.cacheQueue", qos: .userInitiated)

    private var cacheById: [Int64: Annotation] = [:]
    private var cacheByContent: [ContentKey: [Annotation]] = [:]
    private var cacheByBook: [Int: [Annotation]] = [:]
    private var cacheTagsByAnnotationId: [Int64: [String]] = [:]
    private var cachedAllTagNames: [String]?

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
        cacheQueue.sync {
            cacheById.removeAll()
            cacheByContent.removeAll()
            cacheByBook.removeAll()
            cacheTagsByAnnotationId.removeAll()
            cachedAllTagNames = nil
        }
    }

    // MARK: - Loading Annotations

    func loadAnnotations(bkId: Int, contentId: Int) -> [Annotation] {
        let key = ContentKey(bkId: bkId, contentId: contentId)

        let cached = cacheQueue.sync {
            cacheByContent[key]
        }
        if let cached {
            return cached
        }

        let loaded = (try? repository.loadAnnotations(bkId: bkId, contentId: contentId)) ?? []

        cacheQueue.sync {
            cacheByContent[key] = loaded
            for ann in loaded {
                if let id = ann.id {
                    cacheById[id] = ann
                    cacheTagsByAnnotationId[id] = ann.tags
                }
            }
        }

        return loaded
    }

    func loadAnnotations(bkId: Int) -> [Annotation] {
        let cached = cacheQueue.sync {
            cacheByBook[bkId]
        }
        if let cached {
            return cached
        }

        let loaded = (try? repository.loadAnnotations(bkId: bkId)) ?? []

        cacheQueue.sync {
            cacheByBook[bkId] = loaded
            for ann in loaded {
                if let id = ann.id {
                    cacheById[id] = ann
                    cacheTagsByAnnotationId[id] = ann.tags
                }
            }
        }

        return loaded
    }

    func loadAnnotations() -> [Annotation] {
        let loaded = (try? repository.loadAllAnnotations()) ?? []

        cacheQueue.sync {
            cacheById.removeAll()
            cacheByContent.removeAll()
            cacheByBook.removeAll()
            cacheTagsByAnnotationId.removeAll()

            for ann in loaded {
                if let id = ann.id {
                    cacheById[id] = ann
                    cacheTagsByAnnotationId[id] = ann.tags
                }
                let contentKey = ContentKey(bkId: ann.bkId, contentId: ann.contentId)
                cacheByContent[contentKey, default: []].append(ann)
                cacheByBook[ann.bkId, default: []].append(ann)
            }
        }

        return loaded
    }

    func loadAnnotationById(_ id: Int64) -> Annotation? {
        let cached = cacheQueue.sync {
            cacheById[id]
        }
        if let cached {
            return cached
        }

        guard let loaded = try? repository.loadAnnotationById(id) else {
            return nil
        }

        cacheQueue.sync {
            cacheById[id] = loaded
            cacheTagsByAnnotationId[id] = loaded.tags
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
        let cached = cacheQueue.sync {
            cachedAllTagNames
        }
        if let cached {
            return cached
        }

        let loaded = (try? repository.fetchAllTagNames()) ?? []

        cacheQueue.sync {
            cachedAllTagNames = loaded
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

        cacheQueue.sync {
            cachedAllTagNames = nil
            for annotation in annotations {
                updateSingleAnnotationCache(annotation)
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
        cacheQueue.sync {
            cachedAllTagNames = nil
            updateSingleAnnotationCache(annotation)
        }
    }

    private func updateCacheAfterUpdate(_ annotation: Annotation) {
        cacheQueue.sync {
            cachedAllTagNames = nil
            updateSingleAnnotationCache(annotation)
        }
    }

    private func updateCacheAfterDelete(id: Int64, annotation: Annotation?) {
        cacheQueue.sync {
            cachedAllTagNames = nil
            cacheById.removeValue(forKey: id)
            cacheTagsByAnnotationId.removeValue(forKey: id)
            if let bkId = annotation?.bkId {
                cacheByBook[bkId] = cacheByBook[bkId]?.filter { $0.id != id }
            }
            for (key, anns) in cacheByContent {
                if let idx = anns.firstIndex(where: { $0.id == id }) {
                    var copy = anns
                    copy.remove(at: idx)
                    cacheByContent[key] = copy
                }
            }
        }
    }

    private func updateSingleAnnotationCache(_ annotation: Annotation) {
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

    private func applyIncrementalCloudKitCache(
        added: [Annotation],
        updated: [Annotation],
        deleted: [Annotation]
    ) {
        let allChanged = added + updated + deleted
        let affectedContentKeys = Set(allChanged.map { ContentKey(bkId: $0.bkId, contentId: $0.contentId) })
        let affectedBookIds = Set(allChanged.map(\.bkId))

        cacheQueue.sync {
            cachedAllTagNames = nil

            for ann in deleted {
                guard let id = ann.id else { continue }
                cacheById.removeValue(forKey: id)
                cacheTagsByAnnotationId.removeValue(forKey: id)
            }

            for ann in added + updated {
                guard let id = ann.id else { continue }
                cacheById[id] = ann
                cacheTagsByAnnotationId[id] = ann.tags
            }

            for key in affectedContentKeys {
                cacheByContent.removeValue(forKey: key)
            }
            for bkId in affectedBookIds {
                cacheByBook.removeValue(forKey: bkId)
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
