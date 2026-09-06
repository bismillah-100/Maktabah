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
    public let bookTitle: String
    public let content: String
    public let colorHex: String
    public let type: Int
    public let date: Date

    public init(
        id: String,
        bookId: Int,
        bookTitle: String,
        content: String,
        colorHex: String,
        type: Int,
        date: Date
    ) {
        self.id = id
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.content = content
        self.colorHex = colorHex
        self.type = type
        self.date = date
    }
}

public enum AnnotationSnapshotDescriptor: WidgetSnapshotDescriptor {
    public typealias Item = AnnotationSnapshotItem
    public static let fileName = "WidgetAnnotationSnapshot.json"
    public static let ckRecordName = "SharedAnnotationSnapshot"
    public static let ckRecordType = "AnnotationSnapshot"
}

public typealias AnnotationSnapshot = WidgetSnapshot<AnnotationSnapshotDescriptor>
