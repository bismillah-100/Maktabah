//
//  WidgetUpdateCoordinator.swift
//  Maktabah
//
//  Created by Ghoys on 30/08/2026.
//

import CloudKit
import Foundation
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
    private let lock = NSLock()

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
        NotificationCenter.default.addObserver(
            forName: .annotationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.markAnnotationDirty()
        }

        NotificationCenter.default.addObserver(
            forName: .annotationTreeDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.markAnnotationDirty()
        }

        NotificationCenter.default.addObserver(
            forName: .historyDidChange,
            object: nil,
            queue: .main
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

    func flushPendingUpdates(forceCloudKit: Bool = false) async {
        // Read dan langsung reset flag secara atomik
        let (historyNeeded, annotationNeeded) = lock.withLock { () -> (Bool, Bool) in
            let result = (isHistoryDirty, isAnnotationDirty)
            isHistoryDirty = false
            isAnnotationDirty = false
            return result
        }

        guard historyNeeded || annotationNeeded else { return }

        if historyNeeded {
            await flushHistory(bypassThrottle: forceCloudKit)
        }

        if annotationNeeded {
            await flushAnnotations(bypassThrottle: forceCloudKit)
        }
    }

    private func flushHistory(bypassThrottle: Bool) async{
        var snapshot = compileHistorySnapshot()
        let currentLocal = await HistorySnapshot.loadLocal()
        if let currentLocal {
            snapshot.generation = currentLocal.generation + 1
        } else {
            snapshot.generation = 1
        }

        let didChange = await snapshot.saveIfChanged(comparingWith: currentLocal)

        if didChange {
            WidgetCenter.shared.reloadTimelines(ofKind: historyKind)
        }

        let lastUpload = defaults.object(forKey: lastHistoryUploadKey) as? Date ?? .distantPast
        let timeSinceLastUpload = Date().timeIntervalSince(lastUpload)

        if didChange, bypassThrottle || timeSinceLastUpload >= uploadThrottleInterval {
            await uploadSnapshotToCloudKit(snapshot, taskName: "HistorySnapshotUpload")
            defaults.set(Date(), forKey: lastHistoryUploadKey)
        }
    }

    private func flushAnnotations(bypassThrottle: Bool) async {
        var snapshot = compileAnnotationSnapshot()
        let currentLocal = await AnnotationSnapshot.loadLocal()
        if let currentLocal {
            snapshot.generation = currentLocal.generation + 1
        } else {
            snapshot.generation = 1
        }

        let didChange = await snapshot.saveIfChanged(comparingWith: currentLocal)

        if didChange {
            WidgetCenter.shared.reloadTimelines(ofKind: annotationKind)
        }

        let lastUpload = defaults.object(forKey: lastAnnotationUploadKey) as? Date ?? .distantPast
        let timeSinceLastUpload = Date().timeIntervalSince(lastUpload)

        if didChange, bypassThrottle || timeSinceLastUpload >= uploadThrottleInterval {
            await uploadSnapshotToCloudKit(snapshot, taskName: "WidgetAnnotationSnapshotUpload")
            defaults.set(Date(), forKey: lastAnnotationUploadKey)
        }
    }

    // MARK: - Snapshot Compilation

    private func compileHistorySnapshot() -> HistorySnapshot {
        let (entries, historyOrder) = HistoryDatabaseManager.shared.loadFromDatabase()
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
                .filter { !existingIds.contains($0.bookId) }
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
        let allAnnotations = Array(AnnotationManager.shared.loadAnnotations().sorted {
            $0.createdAt > $1.createdAt
        }.prefix(6))

        // Batch query judul buku sekaligus
        let bookIds = allAnnotations.map(\.bkId)
        let books = LibraryDataManager.shared.getBook(bookIds)
        let bookTitleMap = Dictionary(books.map { ($0.id, $0.book) }, uniquingKeysWith: { first, _ in first })

        let annotationItems = allAnnotations.map { annotation -> AnnotationSnapshot.Item in
            let title = bookTitleMap[annotation.bkId] ?? "Book ID: \(annotation.bkId)"
            let date = Date(timeIntervalSince1970: TimeInterval(annotation.createdAt))
            return AnnotationSnapshot.Item(
                id: String(annotation.id ?? 0),
                bookId: annotation.bkId,
                bookTitle: title,
                content: annotation.context,
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

    private func saveRecordToCloudKit(record: CKRecord, payloadData: Data, taskName: String) async {
        #if canImport(UIKit)
        let bgTaskID = await Task { @MainActor in
            var identifier: UIBackgroundTaskIdentifier = .invalid
            identifier = UIApplication.shared.beginBackgroundTask(withName: taskName) {
                if identifier != .invalid {
                    UIApplication.shared.endBackgroundTask(identifier)
                }
            }
            return identifier
        }.value
        #endif

        defer {
            #if canImport(UIKit)
            Task { @MainActor in
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
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
            #if DEBUG
            print("WidgetUpdateCoordinator: Uploaded \(taskName) to CloudKit")
            #endif
        } catch let error as CKError where error.code == .serverRecordChanged {
            if let serverRecord = error.serverRecord {
                serverRecord["payload"] = payloadData as NSData
                // Retry recursively
                await self.saveRecordToCloudKit(
                    record: serverRecord,
                    payloadData: payloadData,
                    taskName: taskName
                )
            }
        } catch {
            #if DEBUG
            print("WidgetUpdateCoordinator: CloudKit upload error for \(taskName) - \(error)")
            #endif
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
