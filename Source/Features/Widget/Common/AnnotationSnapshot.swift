//
//  AnnotationSnapshot.swift
//  Maktabah
//
//  Created by Ghoys on 05/09/2026.
//

import Foundation

/// Model data snapshot independen untuk Widget Anotasi.
public struct AnnotationSnapshotItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let bookId: Int
    public let contentId: Int
    public let bookTitle: String
    public let content: String
    public let colorHex: String
    public let type: Int
    public let date: Date

    public init(
        id: String,
        bookId: Int,
        contentId: Int = 1,
        bookTitle: String,
        content: String,
        colorHex: String,
        type: Int,
        date: Date
    ) {
        self.id = id
        self.bookId = bookId
        self.contentId = contentId
        self.bookTitle = bookTitle
        self.content = content
        self.colorHex = colorHex
        self.type = type
        self.date = date
    }

    enum CodingKeys: String, CodingKey {
        case id, bookId, contentId, bookTitle, content, colorHex, type, date
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.bookId = try container.decode(Int.self, forKey: .bookId)
        self.contentId = try container.decodeIfPresent(Int.self, forKey: .contentId) ?? 1
        self.bookTitle = try container.decode(String.self, forKey: .bookTitle)
        self.content = try container.decode(String.self, forKey: .content)
        self.colorHex = try container.decode(String.self, forKey: .colorHex)
        self.type = try container.decode(Int.self, forKey: .type)
        self.date = try container.decode(Date.self, forKey: .date)
    }
}

public enum AnnotationSnapshotDescriptor: WidgetSnapshotDescriptor {
    public typealias Item = AnnotationSnapshotItem
    public static let fileName = "WidgetAnnotationSnapshot.json"
    public static let ckRecordName = "SharedAnnotationSnapshot"
    public static let ckRecordType = "AnnotationSnapshot"
}

public typealias AnnotationSnapshot = WidgetSnapshot<AnnotationSnapshotDescriptor>
