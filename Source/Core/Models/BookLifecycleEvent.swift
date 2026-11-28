//
//  BookLifecycleEvent.swift
//  Maktabah
//

import Foundation

enum BookLifecycleEvent: Sendable, Equatable {
    case integrated(bookIds: Set<Int>, archiveIds: Set<Int>)
    case updated(bookIds: Set<Int>, oldArchiveIds: Set<Int>, newArchiveIds: Set<Int>)
    case deleted(bookIds: Set<Int>, archiveIds: Set<Int>, removedFromCatalog: Set<Int>)
    case idChanged(oldId: Int, newId: Int, oldArchiveId: Int?, newArchiveId: Int?)
    case libraryFolderChanged
    case bundledDataCleaned
}

extension Notification {
    var bookLifecycleEvent: BookLifecycleEvent? {
        object as? BookLifecycleEvent
    }
}

enum BookTableName {
    static func numericIdString(from raw: String) -> String {
        raw.hasPrefix("b") ? String(raw.dropFirst()) : raw
    }

    static func bookId(from raw: String) -> Int? {
        Int(numericIdString(from: raw))
    }

    static func prefixedTableName(from raw: String) -> String {
        "b\(numericIdString(from: raw))"
    }
}
