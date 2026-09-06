//
//  AnnotationSnapshot.swift
//  Maktabah
//
//  Created by Ghoys on 05/09/2026.
//

import Foundation

/// Model data snapshot independen untuk Widget Anotasi.
public struct AnnotationSnapshot: WidgetSnapshotRecord {
    public static let fileName = "WidgetAnnotationSnapshot.json"
    public static let ckRecordName = "SharedAnnotationSnapshot"
    public static let ckRecordType = "AnnotationSnapshot"

    public struct Item: Codable, Identifiable, Equatable, Sendable {
        public let id: String
        public let bookId: Int
        public let bookTitle: String
        public let content: String
        public let colorHex: String
        public let type: Int
        public let date: Date
    }

    public var items: [Item]
    public var lastUpdated: Date = Date()
    public var generation: Int64 = 0
    public var recordChangeTag: String?

    public init(items: [Item]) {
        self.items = items
    }
}
