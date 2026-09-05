# Maktabah Widget Concurrency & Synchronization Audit Report

This report outlines critical issues involving concurrency, memory constraints, network timeouts, and state conflicts between the Main App and Widget Extension. Precise file and line references are provided alongside production-ready code fixes.

## 1. Concurrent Write Clashing & File Coordination

**Risk Area:** Simultaneous writes from the Main App and Widget Extension to the same JSON file in the App Group container.

### Issue 1.1: Missing `NSFileCoordinator` for Safe Concurrent Reads/Writes
- **File & Line Reference:** `Source/Features/Widget/Common/WidgetSnapshotRecord.swift`, Lines ~30-41 (`loadLocal` and `saveLocal`).
- **Severity:** High
- **Failure Scenario:** If the Main App and the Widget independently finish a CloudKit fetch (or standard app operations trigger an update) at the exact same millisecond, they will concurrently overwrite the exact same file. Even with `.atomic` writes, one process will silently clobber the other. If one write is partially flushed to disk (less likely with atomic writes, but possible in edge cases), or if a read happens mid-write, data corruption or stale views can occur.
- **Suggested Fix:** Implement a dedicated, non-isolated Swift actor to encapsulate `NSFileCoordinator` logic, ensuring it never blocks the main thread. Transform `loadLocal()` and `saveLocal()` into `async` functions across the entire caller chain to avoid deadlocks (like those caused by `DispatchSemaphore`) and out-of-order execution.
- **Implementation Detail (Directory Safety):** Ensure that `appGroupURL` points to an isolated subdirectory (e.g., Application Support) within the App Group rather than the root, and ensure the directory is explicitly created using `FileManager.default.createDirectory` before the `FileCoordinator` executes its first write.

```swift
<<<<<<< SEARCH
    /// Membaca snapshot lokal dari App Group container
    static func loadLocal() -> Self? {
        guard let url = appGroupURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Menyimpan snapshot ke App Group container
    func saveLocal() {
        guard let url = Self.appGroupURL,
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
=======
    /// Actor untuk menangani sinkronisasi file I/O secara aman tanpa memblokir thread
    actor FileCoordinator {
        static let shared = FileCoordinator()

        func read(url: URL) -> Data? {
            var error: NSError?
            var fileData: Data?

            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { newURL in
                // Pada first-launch, berkas mungkin belum ada. `try?` aman mengembalikan nil.
                fileData = try? Data(contentsOf: newURL)
            }

            return fileData
        }

        func write(data: Data, to url: URL) {
            // Ensure directory exists
            let dirURL = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

            var error: NSError?
            let coordinator = NSFileCoordinator(filePresenter: nil)

            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { newURL in
                do {
                    try data.write(to: newURL)
                } catch {
                    print("Failed to write coordinated data: \(error)")
                }
            }
        }
    }

    /// Membaca snapshot lokal dari App Group container secara asinkron
    static func loadLocal() async -> Self? {
        guard let url = appGroupURL else { return nil }
        guard let data = await FileCoordinator.shared.read(url: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Menyimpan snapshot ke App Group container secara asinkron
    func saveLocal() async {
        guard let url = Self.appGroupURL,
              let data = try? JSONEncoder().encode(self) else { return }
        await FileCoordinator.shared.write(data: data, to: url)
    }
>>>>>>> REPLACE
```

*(Note: The protocol definition `public protocol WidgetSnapshotRecord` and callers like `saveIfChanged` and `resolve` must also be updated to support the `async` signature. See Section 2 for protocol updates.)*

## 2. State Drift & Version Conflict Resolution

**Risk Area:** Overwriting newer data with stale data if CloudKit fetches resolve out of order.

### Issue 2.1: Timestamp-only Conflict Resolution
- **File & Line Reference:** `Source/Features/Widget/Common/WidgetSnapshotRecord.swift`, Protocol Definition and `resolve` method.
- **Severity:** Medium
- **Failure Scenario:** Relying solely on `lastUpdated` (Date) is susceptible to identical millisecond timestamps, clock skew, and device time adjustments. If the Main App and Widget independently increment a local generation counter, they might both claim the same generation number (Generation Collision), negating its effectiveness. Furthermore, moving records across `Actor` boundaries requires `Sendable` conformance for Swift 6 strict concurrency compliance.
- **Suggested Fix:** Add `Sendable` to the protocol. Add a monotonic `generation` integer to the protocol. To prevent collisions between independent processes, supplement this with an origin tag or rely on the `CKRecord.recordChangeTag` assigned by the CloudKit server as the definitive version leader.
- **Implementation Detail (Default Values):** When applying these new properties to concrete structs like `HistorySnapshot` and `AnnotationSnapshot`, explicitly assign default values (`var generation: Int64 = 0`, `var recordChangeTag: String? = nil`) to prevent `DecodingError` exceptions when parsing existing local JSON files stored on users' devices.

```swift
<<<<<<< SEARCH
public protocol WidgetSnapshotRecord: Codable {
    associatedtype Item: Codable, Equatable

    static var fileName: String { get }
    static var ckRecordName: String { get }
    static var ckRecordType: String { get }

    var items: [Item] { get }
    var lastUpdated: Date { get set }
}
=======
public protocol WidgetSnapshotRecord: Codable, Sendable {
    associatedtype Item: Codable, Equatable, Sendable

    static var fileName: String { get }
    static var ckRecordName: String { get }
    static var ckRecordType: String { get }

    var items: [Item] { get }
    var lastUpdated: Date { get set }
    var generation: Int64 { get set }
    var recordChangeTag: String? { get set } // Definitif versi dari CloudKit
}
>>>>>>> REPLACE
```

Update `resolve` logic (assuming async signatures are applied from Section 1):
```swift
<<<<<<< SEARCH
        if remote.items != local.items {
            remote.saveLocal()
            return (remote, true)
        }
        if remote.lastUpdated > local.lastUpdated {
            remote.saveLocal()
            return (remote, false)
        }
        return (local, false)
=======
        // Implementasi resolve yang lebih tangguh berdasarkan generation/lastUpdated
        let isRemoteNewer: Bool
        if remote.generation != local.generation {
            isRemoteNewer = remote.generation > local.generation
        } else {
            isRemoteNewer = remote.lastUpdated > local.lastUpdated
        }

        if isRemoteNewer {
            let itemsChanged = remote.items != local.items
            await remote.saveLocal()
            return (remote, itemsChanged)
        } else {
            return (local, false)
        }
>>>>>>> REPLACE
```

## 3. Widget Memory Limits & Jetsam Termination

**Risk Area:** Exceeding Widget memory limits (~30MB) during CloudKit fetches.

### Issue 3.1: Loading entire payloads instead of distinct keys/limits
- **File & Line Reference:** `Source/Features/Widget/Common/CloudKitFetcher.swift`, `fetchActive` method.
- **Severity:** Medium
- **Failure Scenario:** Using `ckDatabase.fetch(withRecordID:)` retrieves the entire `CKRecord`. If the `payload` data grows substantially (e.g., extensive JSON contents), allocating this large `NSData` object inside the Widget's tight memory space can trigger a Jetsam termination.
- **Suggested Fix:** Ensure the backend payload is explicitly size-capped (e.g., maximum 6 items as mentioned), and use a `CKFetchRecordsOperation` configured with `desiredKeys` (e.g., `operation.desiredKeys = ["payload"]`) to only pull the necessary data, preventing the accidental fetching of massive metadata or unneeded fields. (Implemented in Section 4).

## 4. Widget Timeline Timeout & Network Failure Recovery

**Risk Area:** Network timeouts causing `getTimeline` to stall past the system-allowed window.

### Issue 4.1: No Timeout Configuration or Deterministic Race
- **File & Line Reference:** `Source/Features/Widget/Annotations/AnnotationProvider.swift` and `HistoryProvider.swift` -> `CloudKitFetcher.shared.fetchActive`.
- **Severity:** Critical
- **Failure Scenario:** If the device has poor connectivity or the CloudKit server is slow, the standard `fetch(withRecordID:)` can hang indefinitely. WidgetKit expects the completion handler in `getTimeline` to be called promptly. Furthermore, simply wrapping a checked continuation inside `withTaskGroup` without a cancellation handler causes a timeout leak: the CloudKit operation continues running in the background, keeping the task group suspended and preventing the function from returning, which still triggers the system timeout.
- **Suggested Fix:** Rewrite `CloudKitFetcher.fetchActive` to use Swift Concurrency `async/await` with a deterministic timeout race using `TaskGroup` and a `withTaskCancellationHandler` on the `CKFetchRecordsOperation` to explicitly cancel the network request.
- **Implementation Detail (WidgetKit API Migration):** Because the snapshot fetching chain is now heavily based on `async`/`await`, it is highly recommended to migrate the `TimelineProvider` to use the modern async API (`func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry>`) available on iOS 17+/macOS 14+ to prevent wrapping `await` calls in detached Tasks. If backward compatibility dictates sticking to the old completion block handler, ensure the completion block is guaranteed to be called precisely on all error paths.
- **Important Note on Continuation Safety:** The `onCancel` block must *only* call `operation.cancel()`. Do not call `continuation.resume` inside `onCancel`. `operation.cancel()` will natively trigger the `fetchRecordsResultBlock` with a `CKError.operationCancelled`, allowing the single `continuation.resume` inside the result block to handle the cancellation cleanly without crashing due to multiple resumes.

```swift
<<<<<<< SEARCH
    /// Mengambil snapshot aktif secara generik dari CloudKit atau fallback ke lokal
    func fetchActive<T: WidgetSnapshotRecord>(completion: @escaping (T?) -> Void) {
        let localSnapshot = T.loadLocal()
        let recordId = CKRecord.ID(recordName: T.ckRecordName, zoneID: customZoneID)

        ckDatabase.fetch(withRecordID: recordId) { record, error in
            #if DEBUG
            if let error {
                print("CloudKitFetcher [\(T.self)] fetch error: \(error.localizedDescription)")
            } else if record != nil {
                print("CloudKitFetcher [\(T.self)] successfully fetched from CloudKit")
            }
            #endif

            guard let record,
                  let payload = record["payload"] as? Data,
                  let remoteSnapshot = try? JSONDecoder().decode(T.self, from: payload)
            else {
                completion(localSnapshot)
                return
            }

            let (resolved, _) = T.resolve(remote: remoteSnapshot, local: localSnapshot)
            completion(resolved)
        }
    }
=======
    /// Mengambil snapshot aktif secara generik dari CloudKit atau fallback ke lokal
    func fetchActive<T: WidgetSnapshotRecord>(completion: @escaping (T?) -> Void) {
        Task {
            let remoteSnapshot = await fetchRemoteWithTimeout(type: T.self)

            guard let remoteSnapshot = remoteSnapshot else {
                let localSnapshot = await T.loadLocal()
                completion(localSnapshot)
                return
            }

            // Assume T.resolve is updated to an async context
            let (resolved, _) = await T.resolve(remote: remoteSnapshot)
            completion(resolved)
        }
    }

    private func fetchRemoteWithTimeout<T: WidgetSnapshotRecord>(type: T.Type) async -> T? {
        let recordId = CKRecord.ID(recordName: T.ckRecordName, zoneID: customZoneID)

        return await withTaskGroup(of: T?.self) { group in
            // Task 1: CloudKit Fetch dengan pembatalan eksplisit
            group.addTask {
                let operation = CKFetchRecordsOperation(recordIDs: [recordId])
                operation.desiredKeys = ["payload"]

                let config = CKOperation.Configuration()
                config.timeoutIntervalForRequest = 8.0
                operation.configuration = config

                return await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        var fetchedData: Data?

                        operation.perRecordResultBlock = { _, result in
                            if case let .success(record) = result {
                                fetchedData = record["payload"] as? Data
                            }
                        }

                        operation.fetchRecordsResultBlock = { [weak operation] _ in
                            if operation?.isCancelled == true {
                                continuation.resume(returning: nil)
                                return
                            }
                            if let data = fetchedData, let decoded = try? JSONDecoder().decode(T.self, from: data) {
                                continuation.resume(returning: decoded)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }

                        self.ckDatabase.add(operation)
                    }
                } onCancel: {
                    operation.cancel() // Batalkan CloudKit seketika jika Task 2 menang. Dilarang memanggil resume di sini!
                }
            }

            // Task 2: Batas Waktu 6 Detik
            group.addTask {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                return nil
            }

            // Ambil pemenang pertama
            let firstResult = await group.next() ?? nil
            group.cancelAll()
            return firstResult
        }
    }
>>>>>>> REPLACE
```

## 5. Entitlements & CloudKit Container Setup

**Risk Area:** Misconfigured capabilities preventing App Group sharing or CloudKit access.

### Issue 5.1: Validation of Entitlements
- **File Reference:** `Source/Features/Widget/MaktabahWidget.entitlements` and `Source/Maktabah.entitlements`.
- **Severity:** Low (Verification Only)
- **Status:**
  - The `group.com.Drn.maktabah` App Group is correctly present in both the Main App and the Widget entitlements.
  - The CloudKit Container `iCloud.Maktabah` is correctly defined in both.
- **Action Required:** None needed currently based on the provided entitlement files, assuming they are appropriately linked to the target in `project.pbxproj`.
