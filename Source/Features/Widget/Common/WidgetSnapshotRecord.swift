//
//  WidgetSnapshotRecord.swift
//  Maktabah
//
//  Created by Ghoys on 05/09/2026.
//

import Foundation

/// Protocol umum untuk record snapshot widget.
public protocol WidgetSnapshotRecord: Codable {
    associatedtype Item: Codable, Equatable

    static var fileName: String { get }
    static var ckRecordName: String { get }
    static var ckRecordType: String { get }

    var items: [Item] { get }
    var lastUpdated: Date { get set }
}

public extension WidgetSnapshotRecord {
    /// Lokasi file JSON di App Group
    static var appGroupURL: URL? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.Drn.maktabah"
        ) else { return nil }

        return groupURL.appendingPathComponent(fileName)
    }

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

    /// Bandingkan data lokal dan baru berdasarkan items. Simpan dan kembalikan true HANYA jika items berbeda.
    @discardableResult
    func saveIfChanged(comparingWith current: Self? = Self.loadLocal()) -> Bool {
        guard let current else {
            saveLocal()
            return true
        }
        if items != current.items {
            saveLocal()
            return true
        }
        return false
    }

    /// Membandingkan remote dan lokal, memperbarui file lokal HANYA jika remote lebih baru dan isinya berubah
    @discardableResult
    static func resolve(
        remote: Self?,
        local: Self? = Self.loadLocal()
    ) -> (snapshot: Self?, didChange: Bool) {
        guard let remote else { return (local, false) }
        guard let local else {
            remote.saveLocal()
            return (remote, true)
        }
        if remote.items != local.items {
            remote.saveLocal()
            return (remote, true)
        }
        if remote.lastUpdated > local.lastUpdated {
            remote.saveLocal()
            return (remote, false)
        }
        return (local, false)
    }
}
