//
//  WidgetSnapshotRecord.swift
//  Maktabah
//
//  Created by Ghoys on 05/09/2026.
//

import Foundation
import OSLog
#if os(macOS)
import Security
#endif

private enum AppGroupEntitlementResolver {
    static let entitledGroups: [String] = {
        #if os(macOS)
        var code: SecCode?
        var staticCode: SecStaticCode?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code {
            SecCodeCopyStaticCode(code, [], &staticCode)
        }
        if staticCode == nil {
            SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode)
        }
        guard let staticCode else { return [] }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let entitlements = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else {
            return []
        }
        return groups
        #else
        return []
        #endif
    }()
}

/// Pengelola sinkronisasi file I/O secara aman tanpa memblokir cooperative thread pool Swift Concurrency.
public final class FileCoordinator: Sendable {
    public static let shared = FileCoordinator()
    private let ioQueue = DispatchQueue(label: "com.maktabah.widget.filecoordinator", qos: .utility)

    private init() {}

    public func read(url: URL) async -> Data? {
        await withCheckedContinuation { continuation in
            ioQueue.async {
                continuation.resume(returning: self.performRead(url: url))
            }
        }
    }

    /// Membaca berkas secara sinkron
    public func readSync(url: URL) -> Data? {
        ioQueue.sync {
            self.performRead(url: url)
        }
    }

    private func performRead(url: URL) -> Data? {
        var error: NSError?
        var fileData: Data?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { newURL in
            // Pada first-launch, berkas mungkin belum ada. `try?` aman mengembalikan nil.
            fileData = try? Data(contentsOf: newURL)
        }

        if fileData == nil {
            // Fallback pembacaan langsung jika NSFileCoordinator gagal atau koordinasi diblokir
            fileData = try? Data(contentsOf: url)
        }

        return fileData
    }

    public func write(data: Data, to url: URL) async {
        await withCheckedContinuation { continuation in
            ioQueue.async {
                self.performWrite(data: data, to: url)
                continuation.resume()
            }
        }
    }

    /// Menulis berkas secara sinkron. Digunakan saat terminasi aplikasi untuk memastikan file tertulis sebelum proses dimatikan.
    public func writeSync(data: Data, to url: URL) {
        ioQueue.sync {
            self.performWrite(data: data, to: url)
        }
    }

    private func performWrite(data: Data, to url: URL) {
        // Ensure directory exists
        let dirURL = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        var error: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { newURL in
            do {
                try data.write(to: newURL, options: .atomic)
            } catch {
                Logger.widget.error("Failed to write coordinated data: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let error {
            Logger.widget.error("Failed to coordinate write at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? data.write(to: url, options: .atomic)
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

/// Descriptor yang mendefinisikan metadata unik untuk jenis snapshot tertentu.
public protocol WidgetSnapshotDescriptor: Sendable {
    associatedtype Item: Codable, Equatable, Sendable

    static var fileName: String { get }
    static var ckRecordName: String { get }
    static var ckRecordType: String { get }
}

/// Struktur snapshot widget generik untuk menghindari duplikasi deklarasi stored property.
public struct WidgetSnapshot<Descriptor: WidgetSnapshotDescriptor>: WidgetSnapshotRecord {
    public typealias Item = Descriptor.Item

    public static var fileName: String {
        Descriptor.fileName
    }

    public static var ckRecordName: String {
        Descriptor.ckRecordName
    }

    public static var ckRecordType: String {
        Descriptor.ckRecordType
    }

    public var items: [Item]
    public var lastUpdated: Date = .init()
    public var generation: Int64 = 0
    public var recordChangeTag: String?

    public init(items: [Item]) {
        self.items = items
    }
}

public extension WidgetSnapshotRecord {
    /// Identifier App Group sesuai platform (macOS membutuhkan Team ID prefix)
    static var appGroupIdentifier: String {
        #if os(macOS)
        if let entitled = AppGroupEntitlementResolver.entitledGroups.first {
            return entitled
        }
        #endif
        #if DIRECT_DISTRIBUTION
        return "Q37L5CJ4ZG.group.com.Drn.maktabah"
        #else
        return "group.com.Drn.maktabah"
        #endif
    }

    /// Daftar kandidat identifier App Group untuk toleransi Direct vs App Store builds
    private static var candidateAppGroupIdentifiers: [String] {
        #if os(macOS)
        let entitledGroups = AppGroupEntitlementResolver.entitledGroups
        if !entitledGroups.isEmpty {
            return entitledGroups
        }
        #endif
        #if DIRECT_DISTRIBUTION
        return [
            "Q37L5CJ4ZG.group.com.Drn.maktabah",
            "group.com.Drn.maktabah",
        ]
        #else
        return [
            "group.com.Drn.maktabah",
            "Q37L5CJ4ZG.group.com.Drn.maktabah",
        ]
        #endif
    }

    /// Lokasi file JSON di App Group dengan resolusi toleran terhadap prefix
    static var appGroupURL: URL? {
        var firstValidURL: URL?
        #if DEBUG
        let targetFileName = "debug_\(fileName)"
        #else
        let targetFileName = fileName
        #endif

        for identifier in candidateAppGroupIdentifiers {
            if let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            ) {
                // Use Application Support directory for isolation
                let appSupportURL = groupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
                let fileURL = appSupportURL.appendingPathComponent(targetFileName)
                if FileManager.default.isReadableFile(atPath: fileURL.path) {
                    return fileURL
                }
                if firstValidURL == nil {
                    firstValidURL = fileURL
                }
            }
        }

        return firstValidURL
    }

    /// Membaca snapshot lokal dari App Group container
    static func loadLocal() async -> Self? {
        guard let url = appGroupURL else { return nil }
        guard let data = await FileCoordinator.shared.read(url: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Membaca snapshot lokal dari App Group container secara sinkron
    static func loadLocalSync() -> Self? {
        guard let url = appGroupURL else { return nil }
        guard let data = FileCoordinator.shared.readSync(url: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Menyimpan snapshot ke App Group container
    func saveLocal() async {
        guard let url = Self.appGroupURL,
              let data = try? JSONEncoder().encode(self) else { return }
        await FileCoordinator.shared.write(data: data, to: url)
    }

    /// Menyimpan snapshot ke App Group container secara sinkron
    func saveLocalSync() {
        guard let url = Self.appGroupURL,
              let data = try? JSONEncoder().encode(self) else { return }
        FileCoordinator.shared.writeSync(data: data, to: url)
    }

    /// Bandingkan data lokal dan baru berdasarkan items secara sinkron.
    @discardableResult
    func saveIfChangedSync(comparingWith current: Self? = nil) -> Bool {
        let currentLocal = current ?? Self.loadLocalSync()

        guard let currentLocal else {
            saveLocalSync()
            return true
        }
        if items != currentLocal.items {
            saveLocalSync()
            return true
        }
        return false
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
        local: Self? = nil,
        persistToLocal: Bool = true
    ) async -> (snapshot: Self?, didChange: Bool) {
        let currentLocal = await (local != nil ? local : Self.loadLocal())

        guard let remote else { return (currentLocal, false) }
        guard let currentLocal else {
            if persistToLocal, !remote.items.isEmpty {
                await remote.saveLocal()
            }
            return (remote, !remote.items.isEmpty)
        }

        let isRemoteNewer: Bool = if remote.generation != currentLocal.generation {
            remote.generation > currentLocal.generation
        } else {
            remote.lastUpdated > currentLocal.lastUpdated
        }

        if isRemoteNewer {
            // Guard: Jangan izinkan remote kosong menimpa snapshot lokal yang memiliki item aktif
            if remote.items.isEmpty, !currentLocal.items.isEmpty {
                return (currentLocal, false)
            }
            let itemsChanged = remote.items != currentLocal.items
            if persistToLocal {
                await remote.saveLocal()
            }
            return (remote, itemsChanged)
        } else {
            return (currentLocal, false)
        }
    }
}
