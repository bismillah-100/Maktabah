//
//  WidgetUpdateCoordinator.swift
//  Maktabah
//
//  Created by Ghoys on 30/08/2026.
//

import CloudKit
import Combine
import Foundation
import OSLog
import WidgetKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class WidgetUpdateCoordinator: @unchecked Sendable {
    static let shared = WidgetUpdateCoordinator()

    private var isHistoryDirty = false
    private var isAnnotationDirty = false
    private var isFlushingHistoryLocally = false
    private var isFlushingAnnotationLocally = false
    private let lock = NSLock()
    private var cancellables = Set<AnyCancellable>()

    private let ckDatabase = CKContainer(
        identifier: "iCloud.Maktabah"
    ).privateCloudDatabase

    private let lastHistoryUploadKey = "HistorySnapshot_LastUploadTime"
    private let lastAnnotationUploadKey = "WidgetAnnotationSnapshot_LastUploadTime"
    private let uploadThrottleInterval: TimeInterval = 30 * 60 // 30 minutes

    private let annotationKind = "AnnotationWidget"
    private let historyKind = "HistoryWidget"
    private let sharedAnnotationSnapshot = "SharedAnnotationSnapshot"
    private let sharedHistorySnapshot = "SharedHistorySnapshot"

    private let defaults = UserDefaults.standard

    private init() {
        setupObservers()
        setupCloudKitSubscription()
    }

    private func setupObservers() {
        AnnotationStore.shared.events
            .sink { [weak self] _ in
                self?.markAnnotationDirty()
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: .historyDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.markHistoryDirty()
        }
    }

    // MARK: - Core Logic

    func markHistoryDirty() {
        lock.withLock {
            isHistoryDirty = true
        }
    }

    func markAnnotationDirty() {
        lock.withLock {
            isAnnotationDirty = true
        }
    }

    func flushPendingUpdatesTask(forceCloudKit: Bool = false) {
        Task {
            await flushPendingUpdates(forceCloudKit: forceCloudKit)
        }
    }

    /// Menjalankan flush secara sinkron untuk memastikan berkas snapshot tertulis ke disk
    /// sebelum proses aplikasi dimatikan oleh sistem operasi (misal pada `applicationWillTerminate`).
    @MainActor
    func flushPendingUpdatesSync() {
        let (historyNeeded, annotationNeeded) = lock.withLock { () -> (Bool, Bool) in
            let result = (
                isHistoryDirty || isFlushingHistoryLocally,
                isAnnotationDirty || isFlushingAnnotationLocally
            )
            isHistoryDirty = false
            isAnnotationDirty = false
            isFlushingHistoryLocally = false
            isFlushingAnnotationLocally = false
            return result
        }

        guard historyNeeded || annotationNeeded else { return }

        if historyNeeded {
            let compiled = compileHistorySnapshotOnMain()
            _ = saveHistorySnapshotLocallySync(compiled: compiled)
        }

        if annotationNeeded {
            _ = saveAnnotationSnapshotLocallySync()
        }
    }

    func flushPendingUpdates(forceCloudKit: Bool = false) async {
        // Read dan langsung reset flag secara atomik sambil menandai flush lokal berjalan
        let (historyNeeded, annotationNeeded) = lock.withLock { () -> (Bool, Bool) in
            let h = isHistoryDirty
            let a = isAnnotationDirty
            if h {
                isHistoryDirty = false
                isFlushingHistoryLocally = true
            }
            if a {
                isAnnotationDirty = false
                isFlushingAnnotationLocally = true
            }
            return (h, a)
        }

        guard historyNeeded || annotationNeeded else { return }

        if historyNeeded {
            await flushHistory(bypassThrottle: forceCloudKit)
        }

        if annotationNeeded {
            await flushAnnotations(bypassThrottle: forceCloudKit)
        }
    }

    private func flushHistory(bypassThrottle: Bool) async {
        let compiled = await compileHistorySnapshotOnMain()
        let (snapshot, didChange) = saveHistorySnapshotLocallySync(compiled: compiled)
        lock.withLock {
            isFlushingHistoryLocally = false
        }

        let lastUpload = defaults.object(forKey: lastHistoryUploadKey) as? Date ?? .distantPast
        let timeSinceLastUpload = Date().timeIntervalSince(lastUpload)

        if didChange, bypassThrottle || timeSinceLastUpload >= uploadThrottleInterval {
            await uploadSnapshotToCloudKit(snapshot, taskName: "HistorySnapshotUpload")
            defaults.set(Date(), forKey: lastHistoryUploadKey)
        }
    }

    private func flushAnnotations(bypassThrottle: Bool) async {
        let (snapshot, didChange) = saveAnnotationSnapshotLocallySync()
        lock.withLock {
            isFlushingAnnotationLocally = false
        }

        let lastUpload = defaults.object(forKey: lastAnnotationUploadKey) as? Date ?? .distantPast
        let timeSinceLastUpload = Date().timeIntervalSince(lastUpload)

        if didChange, bypassThrottle || timeSinceLastUpload >= uploadThrottleInterval {
            await uploadSnapshotToCloudKit(snapshot, taskName: "WidgetAnnotationSnapshotUpload")
            defaults.set(Date(), forKey: lastAnnotationUploadKey)
        }
    }

    @discardableResult
    private func saveHistorySnapshotLocallySync(
        compiled: (snapshot: HistorySnapshot, allowEmptyOverwrite: Bool)
    ) -> (snapshot: HistorySnapshot, didChange: Bool) {
        var nextSnapshot = compiled.snapshot
        let currentLocal = HistorySnapshot.loadLocalSync()

        if nextSnapshot.items.isEmpty, !compiled.allowEmptyOverwrite,
           let currentLocal, !currentLocal.items.isEmpty
        {
            return (currentLocal, false)
        }

        let epochMs = Int64(Date().timeIntervalSince1970 * 1000)
        nextSnapshot.generation = max(currentLocal?.generation ?? 0, epochMs) + 1
        let didChange = nextSnapshot.saveIfChangedSync(comparingWith: currentLocal)
        if didChange {
            WidgetCenter.shared.reloadTimelines(ofKind: historyKind)
        }
        return (nextSnapshot, didChange)
    }

    @discardableResult
    private func saveAnnotationSnapshotLocallySync() -> (snapshot: AnnotationSnapshot, didChange: Bool) {
        var snapshot = compileAnnotationSnapshot()
        let currentLocal = AnnotationSnapshot.loadLocalSync()
        let epochMs = Int64(Date().timeIntervalSince1970 * 1000)
        snapshot.generation = max(currentLocal?.generation ?? 0, epochMs) + 1
        let didChange = snapshot.saveIfChangedSync(comparingWith: currentLocal)
        if didChange {
            WidgetCenter.shared.reloadTimelines(ofKind: annotationKind)
        }
        return (snapshot, didChange)
    }

    // MARK: - Snapshot Compilation

    @MainActor
    private func compileHistorySnapshotOnMain() -> (snapshot: HistorySnapshot, allowEmptyOverwrite: Bool) {
        let vm = HistoryViewModel.shared
        vm.flushPendingSaveSync()
        HistoryDatabaseManager.shared.syncWriteQueue()

        let inMemoryEntries = Array(vm.entriesByBookId.values)
        let inMemoryOrder = vm.historyOrder
        let allowEmpty = vm.hasExplicitlyClearedHistory

        let entries: [ReadingEntry]
        let historyOrder: [Int]

        if !inMemoryEntries.isEmpty || !inMemoryOrder.isEmpty || allowEmpty {
            entries = inMemoryEntries
            historyOrder = inMemoryOrder
        } else {
            let dbData = HistoryDatabaseManager.shared.loadFromDatabase()
            entries = dbData.entries
            historyOrder = dbData.historyOrder
        }

        if entries.isEmpty, historyOrder.isEmpty, !allowEmpty,
           let existingLocal = HistorySnapshot.loadLocalSync(), !existingLocal.items.isEmpty
        {
            return (existingLocal, false)
        }

        if allowEmpty, historyOrder.isEmpty {
            return (HistorySnapshot(items: []), true)
        }

        return (buildHistorySnapshot(entries: entries, historyOrder: historyOrder), allowEmpty)
    }

    private func buildHistorySnapshot(entries: [ReadingEntry], historyOrder: [Int]) -> HistorySnapshot {
        let entryMap = Dictionary(entries.map { ($0.bookId, $0) }, uniquingKeysWith: { first, _ in first })

        var orderedEntries: [ReadingEntry] = []
        for bookId in historyOrder {
            if let entry = entryMap[bookId] {
                orderedEntries.append(entry)
            }
        }

        if orderedEntries.count < 6 {
            let existingIds = Set(orderedEntries.map(\.bookId))
            let remaining = entries
                .filter { $0.lastOpenedAt != nil && !existingIds.contains($0.bookId) }
                .sorted {
                    let d1 = $0.lastOpenedAt ?? $0.positionUpdatedAt ?? $0.updatedAt
                    let d2 = $1.lastOpenedAt ?? $1.positionUpdatedAt ?? $1.updatedAt
                    return d1 > d2
                }
            orderedEntries.append(contentsOf: remaining)
        }

        let recents = Array(orderedEntries.prefix(6))

        // Batch query judul buku sekaligus
        let bookIds = recents.map(\.bookId)
        let books = LibraryDataManager.shared.getBook(bookIds)
        let bookTitleMap = Dictionary(books.map { ($0.id, $0.book) },
                                      uniquingKeysWith: { first, _ in first })

        let historyItems = recents.map { entry -> HistorySnapshot.Item in
            let title = bookTitleMap[entry.bookId] ?? "Book ID: \(entry.bookId)"
            let date = entry.lastOpenedAt ?? entry.positionUpdatedAt ?? entry.updatedAt
            return HistorySnapshot.Item(
                id: String(entry.id),
                bookId: entry.bookId,
                bookTitle: title,
                contentId: entry.lastContentId,
                date: date
            )
        }

        return HistorySnapshot(items: historyItems)
    }

    private func compileAnnotationSnapshot() -> AnnotationSnapshot {
        let allAnnotations = Array(AnnotationStore.shared.loadAnnotations().sorted {
            $0.createdAt > $1.createdAt
        }.prefix(6))

        // Batch query judul buku sekaligus
        let bookIds = allAnnotations.map(\.bkId)
        let books = LibraryDataManager.shared.getBook(bookIds)
        let bookTitleMap = Dictionary(books.map { ($0.id, $0.book) }, uniquingKeysWith: { first, _ in first })

        let annotationItems = allAnnotations.map { annotation -> AnnotationSnapshot.Item in
            let title = bookTitleMap[annotation.bkId] ?? "Book ID: \(annotation.bkId)"
            let date = Date(timeIntervalSince1970: TimeInterval(annotation.createdAt))
            let maxContextLength = 300
            let rawContext = annotation.context
            let truncatedContext = rawContext.count > maxContextLength
                ? String(rawContext.prefix(maxContextLength)) + "..."
                : rawContext

            return AnnotationSnapshot.Item(
                id: String(annotation.id ?? 0),
                bookId: annotation.bkId,
                contentId: annotation.contentId,
                bookTitle: title,
                content: truncatedContext,
                colorHex: annotation.colorHex,
                type: annotation.type.rawValue,
                date: date
            )
        }

        return AnnotationSnapshot(items: annotationItems)
    }

    // MARK: - CloudKit Upload

    private func uploadSnapshotToCloudKit<T: WidgetSnapshotRecord>(_ snapshot: T, taskName: String) async {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let recordId = CKRecord.ID(recordName: T.ckRecordName, zoneID: CloudKitCoreManager.shared.zoneId)
        let record = CKRecord(recordType: T.ckRecordType, recordID: recordId)
        record["payload"] = data as NSData
        await saveRecordToCloudKit(record: record, payloadData: data, taskName: taskName)
    }

    #if canImport(UIKit)
    private final class TaskBox: @unchecked Sendable {
        var id: UIBackgroundTaskIdentifier = .invalid
    }
    #endif

    @MainActor
    private func saveRecordToCloudKit(record: CKRecord, payloadData: Data, taskName: String) async {
        #if canImport(UIKit)
        let box = TaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: taskName) {
            let expiredId = box.id
            if expiredId != .invalid {
                UIApplication.shared.endBackgroundTask(expiredId)
            }
        }
        let bgTaskID = box.id
        #endif

        defer {
            #if canImport(UIKit)
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
            #endif
        }

        do {
            _ = try await ckDatabase.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            Logger.widget.debug("WidgetUpdateCoordinator: Uploaded \(taskName, privacy: .public) to CloudKit")
        } catch let error as CKError where error.code == .serverRecordChanged {
            if let serverRecord = error.serverRecord {
                serverRecord["payload"] = payloadData as NSData
                // Retry recursively
                await saveRecordToCloudKit(
                    record: serverRecord,
                    payloadData: payloadData,
                    taskName: taskName
                )
            }
        } catch {
            Logger.widget.error("WidgetUpdateCoordinator: CloudKit upload error for \(taskName, privacy: .public) - \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Silent Push Support

    private let subscriptionID = "WidgetSnapshot_SilentPush"

    private func setupCloudKitSubscription() {
        let key = "hasSubscribedToWidgetSnapshot"
        let isSubscribed = defaults.bool(forKey: key)
        guard !isSubscribed else { return }

        let subscription = CKRecordZoneSubscription(
            zoneID: CloudKitCoreManager.shared.zoneId,
            subscriptionID: subscriptionID
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        ckDatabase.save(subscription) { [weak self] _, error in
            if error == nil {
                self?.defaults.set(true, forKey: key)
            }
        }
    }

    /// Called by AppDelegate/SceneDelegate when receiving a silent push
    @discardableResult
    func handleSilentPush() async -> Bool {
        let zoneId = CloudKitCoreManager.shared.zoneId
        let historyId = CKRecord.ID(recordName: sharedHistorySnapshot, zoneID: zoneId)
        let annotationId = CKRecord.ID(recordName: sharedAnnotationSnapshot, zoneID: zoneId)

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    let result = try await self.ckDatabase.records(
                        for: [historyId, annotationId],
                        desiredKeys: ["payload"]
                    )

                    var didUpdateAny = false

                    if let historyRes = result[historyId],
                       case let .success(historyRecord) = historyRes,
                       let data = historyRecord["payload"] as? Data,
                       var remoteHistory = try? JSONDecoder().decode(HistorySnapshot.self, from: data)
                    {
                        remoteHistory.recordChangeTag = historyRecord.recordChangeTag
                        let (_, didChange) = await HistorySnapshot.resolve(remote: remoteHistory)
                        if didChange {
                            WidgetCenter.shared.reloadTimelines(ofKind: self.historyKind)
                            didUpdateAny = true
                        }
                    }

                    if let annotationRes = result[annotationId],
                       case let .success(annotationRecord) = annotationRes,
                       let data = annotationRecord["payload"] as? Data,
                       var remoteAnnotation = try? JSONDecoder().decode(AnnotationSnapshot.self, from: data)
                    {
                        remoteAnnotation.recordChangeTag = annotationRecord.recordChangeTag
                        let (_, didChange) = await AnnotationSnapshot.resolve(remote: remoteAnnotation)
                        if didChange {
                            WidgetCenter.shared.reloadTimelines(ofKind: self.annotationKind)
                            didUpdateAny = true
                        }
                    }

                    return didUpdateAny
                } catch {
                    return false
                }
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(25))
                return false
            }

            let firstResult = await group.next() ?? false
            group.cancelAll()
            return firstResult
        }
    }
}
