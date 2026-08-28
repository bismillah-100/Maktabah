//
//  HistorySnapshot.swift
//  Maktabah
//
//  Created by Ghoys on 05/09/2026.
//

import Foundation

/// Model data snapshot independen untuk Widget Riwayat Bacaan.
public struct HistorySnapshot: WidgetSnapshotRecord {
    public static let fileName = "WidgetHistorySnapshot.json"
    public static let ckRecordName = "SharedHistorySnapshot"
    public static let ckRecordType = "HistorySnapshot"

    public struct Item: Codable, Identifiable, Equatable {
        public let id: String
        public let bookId: Int
        public let bookTitle: String
        public let contentId: Int?
        public let date: Date
    }

    public var items: [Item]
    public var lastUpdated: Date

    public init(items: [Item], lastUpdated: Date = Date()) {
        self.items = items
        self.lastUpdated = lastUpdated
    }
}
