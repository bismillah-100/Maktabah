//
//  WidgetSnapshotRecord.swift
//  Maktabah
//
//  Created by Ghoys on 05/09/2026.
//

import Foundation

/// Actor untuk menangani sinkronisasi file I/O secara aman tanpa memblokir thread
public actor FileCoordinator {
    public static let shared = FileCoordinator()

    public func read(url: URL) -> Data? {
        var error: NSError?
        var fileData: Data?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { newURL in
            // Pada first-launch, berkas mungkin belum ada. `try?` aman mengembalikan nil.
            fileData = try? Data(contentsOf: newURL)
        }

        return fileData
    }

    public func write(data: Data, to url: URL) {
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

/// Protocol umum untuk record snapshot widget.
public protocol WidgetSnapshotRecord: Codable, Sendable {
    associatedtype Item: Codable, Equatable, Sendable

    static var fileName: String { get }
    static var ckRecordName: String { get }
    static var ckRecordType: String { get }

    var items: [Item] { get set }
    var lastUpdated: Date { get set }
    var generation: Int64 { get set }
    var recordChangeTag: String? { get set }

    init(items: [Item])
}

public extension WidgetSnapshotRecord {
    init(items: [Item], lastUpdated: Date = Date(), generation: Int64 = 0, recordChangeTag: String? = nil) {
        self.init(items: items)
        self.lastUpdated = lastUpdated
        self.generation = generation
        self.recordChangeTag = recordChangeTag
    }
}

public extension WidgetSnapshotRecord {
    /// Lokasi file JSON di App Group
    static var appGroupURL: URL? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.Drn.maktabah"
        ) else { return nil }

        // Use Application Support directory for isolation
        let appSupportURL = groupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupportURL.appendingPathComponent(fileName)
    }

    /// Membaca snapshot lokal dari App Group container
    static func loadLocal() async -> Self? {
        guard let url = appGroupURL else { return nil }
        guard let data = await FileCoordinator.shared.read(url: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Menyimpan snapshot ke App Group container
    func saveLocal() async {
        guard let url = Self.appGroupURL,
              let data = try? JSONEncoder().encode(self) else { return }
        await FileCoordinator.shared.write(data: data, to: url)
    }

    /// Bandingkan data lokal dan baru berdasarkan items. Simpan dan kembalikan true HANYA jika items berbeda.
    @discardableResult
    func saveIfChanged(comparingWith current: Self? = nil) async -> Bool {
        let currentLocal = await (current != nil ? current : Self.loadLocal())

        guard let currentLocal else {
            await saveLocal()
            return true
        }
        if items != currentLocal.items {
            await saveLocal()
            return true
        }
        return false
    }

    /// Membandingkan remote dan lokal, memperbarui file lokal HANYA jika remote lebih baru dan isinya berubah
    @discardableResult
    static func resolve(
        remote: Self?,
        local: Self? = nil
    ) async -> (snapshot: Self?, didChange: Bool) {
        let currentLocal = await (local != nil ? local : Self.loadLocal())

        guard let remote else { return (currentLocal, false) }
        guard let currentLocal else {
            await remote.saveLocal()
            return (remote, true)
        }

        let isRemoteNewer: Bool = if remote.generation != currentLocal.generation {
            remote.generation > currentLocal.generation
        } else {
            remote.lastUpdated > currentLocal.lastUpdated
        }

        if isRemoteNewer {
            let itemsChanged = remote.items != currentLocal.items
            await remote.saveLocal()
            return (remote, itemsChanged)
        } else {
            return (currentLocal, false)
        }
    }
}
