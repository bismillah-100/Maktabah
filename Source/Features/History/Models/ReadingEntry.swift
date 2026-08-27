//
//  ReadingEntry.swift
//  Maktabah
//

import Foundation

struct ReadingEntry: Codable, Identifiable, Hashable {
    let bookId: Int
    var lastContentId: Int?
    var lastOpenedAt: Date?
    var favoritedAt: Date?
    var positionUpdatedAt: Date?
    var updatedAt: Date
    var isFavorite: Bool

    var ckRecordId: String?

    var id: Int {
        bookId
    }

    init(
        bookId: Int,
        lastContentId: Int? = nil,
        lastOpenedAt: Date? = nil,
        favoritedAt: Date? = nil,
        positionUpdatedAt: Date? = nil,
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        ckRecordId: String? = nil
    ) {
        self.bookId = bookId
        self.lastContentId = lastContentId
        self.lastOpenedAt = lastOpenedAt
        self.favoritedAt = favoritedAt
        self.positionUpdatedAt = positionUpdatedAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.ckRecordId = ckRecordId ?? String(bookId)
    }

    init(defaultForBookId bookId: Int) {
        self.init(
            bookId: bookId,
            lastContentId: nil,
            lastOpenedAt: nil,
            favoritedAt: nil,
            positionUpdatedAt: nil,
            updatedAt: Date(),
            isFavorite: false,
            ckRecordId: String(bookId)
        )
    }
}
