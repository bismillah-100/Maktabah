//
//  HistorySnapshot.swift
//  Maktabah
//
//  Created by Ghoys on 05/09/2026.
//

import Foundation

/// Model data snapshot independen untuk Widget Riwayat Bacaan.
public struct HistorySnapshotItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let bookId: Int
    public let bookTitle: String
    public let contentId: Int?
    public let date: Date

    public init(
        id: String,
        bookId: Int,
        bookTitle: String,
        contentId: Int?,
        date: Date
    ) {
        self.id = id
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.contentId = contentId
        self.date = date
    }
}

public enum HistorySnapshotDescriptor: WidgetSnapshotDescriptor {
    public typealias Item = HistorySnapshotItem
    public static let fileName = "WidgetHistorySnapshot.json"
    public static let ckRecordName = "SharedHistorySnapshot"
    public static let ckRecordType = "HistorySnapshot"
}

public typealias HistorySnapshot = WidgetSnapshot<HistorySnapshotDescriptor>
