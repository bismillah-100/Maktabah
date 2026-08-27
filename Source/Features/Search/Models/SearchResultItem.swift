//
//  SearchResultItem.swift
//  Maktabah
//

import Foundation

struct SearchResultItem: Codable, CopyableResult, Hashable {
    let archive: String
    let tableName: String
    let bookId: Int
    let bookTitle: String
    let page: Int
    let part: Int
    let attributedText: NSAttributedString

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
        attributedText: NSAttributedString
    ) {
        self.archive = archive
        self.tableName = tableName
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.page = page
        self.part = part
        self.attributedText = attributedText
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(archive, forKey: .archive)
        try container.encode(tableName, forKey: .tableName)
        try container.encode(bookId, forKey: .bookId)
        try container.encode(bookTitle, forKey: .bookTitle)
        try container.encode(page, forKey: .page)
        try container.encode(part, forKey: .part)
        try container.encode(attributedText.archivedData(), forKey: .attributedText)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        archive = try container.decode(String.self, forKey: .archive)
        tableName = try container.decode(String.self, forKey: .tableName)
        bookId = try container.decode(Int.self, forKey: .bookId)
        bookTitle = try container.decode(String.self, forKey: .bookTitle)
        page = try container.decode(Int.self, forKey: .page)
        part = try container.decode(Int.self, forKey: .part)

        let data = try container.decode(Data.self, forKey: .attributedText)
        attributedText = NSAttributedString.unarchiveSecure(from: data) ?? NSAttributedString(string: "")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bookId)
    }
}
