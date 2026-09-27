//
//  SearchResultItem.swift
//  Maktabah
//

import Foundation

struct SearchHit: Sendable, Identifiable, Hashable {
    let archive: String
    let tableName: String
    let rowId: Int
    let page: Int
    let part: Int

    var id: String { "\(archive)_\(tableName)_\(rowId)" }
}

struct SearchResultItem: Codable, CopyableResult, Hashable, Sendable, Identifiable {
    let archive: String
    let tableName: String
    let bookId: Int
    let bookTitle: String
    let page: Int
    let part: Int
    private nonisolated(unsafe) let rawAttributedText: NSAttributedString?

    var attributedText: NSAttributedString {
        rawAttributedText ?? NSAttributedString(string: "")
    }

    var hasResolvedSnippet: Bool {
        rawAttributedText != nil
    }

    var id: String { "\(archive)_\(tableName)_\(bookId)" }
    var uniqueId: String { id }

    enum CodingKeys: String, CodingKey {
        case archive
        case tableName
        case bookId
        case bookTitle
        case page
        case part
        case attributedText
    }

    init(
        archive: String,
        tableName: String,
        bookId: Int,
        bookTitle: String,
        page: Int,
        part: Int,
        attributedText: NSAttributedString? = nil
    ) {
        self.archive = archive
        self.tableName = tableName
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.page = page
        self.part = part
        rawAttributedText = attributedText
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(archive, forKey: .archive)
        try container.encode(tableName, forKey: .tableName)
        try container.encode(bookId, forKey: .bookId)
        try container.encode(bookTitle, forKey: .bookTitle)
        try container.encode(page, forKey: .page)
        try container.encode(part, forKey: .part)
        if let rawAttributedText {
            try container.encode(rawAttributedText.archivedData(), forKey: .attributedText)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        archive = try container.decode(String.self, forKey: .archive)
        tableName = try container.decode(String.self, forKey: .tableName)
        bookId = try container.decode(Int.self, forKey: .bookId)
        bookTitle = try container.decode(String.self, forKey: .bookTitle)
        page = try container.decode(Int.self, forKey: .page)
        part = try container.decode(Int.self, forKey: .part)

        if let data = try container.decodeIfPresent(Data.self, forKey: .attributedText) {
            rawAttributedText = NSAttributedString.unarchiveSecure(from: data)
        } else {
            rawAttributedText = nil
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(archive)
        hasher.combine(tableName)
        hasher.combine(bookId)
    }

    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.archive == rhs.archive &&
            lhs.tableName == rhs.tableName &&
            lhs.bookId == rhs.bookId
    }
}
