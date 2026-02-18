//
//  DataModel.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

import Foundation
import SQLite

// MARK: - TOC dengan Children (untuk NSOutlineView)

class TOCNode {
    let bab: String
    let level: Int
    let sub: Int
    let id: Int
    var children: [TOCNode] = []

    var endID: Int = .max

    init(from toc: TOC) {
        self.bab = toc.bab.convertToArabicDigits()
        self.level = toc.level
        self.sub = toc.sub
        self.id = toc.id
    }
}

struct TOC {
    let bab: String   // Memetakan ke kolom 'tit'
    let level: Int    // Memetakan ke kolom 'lvl'
    let sub: Int
    let id: Int
}

class BooksData: Codable {
    let id: Int
    let book: String
    let archive: Int
    let muallif: Int
    var tafseerNam: String?
    var bithoqoh: String {
        didSet {
            bithoqoh = bithoqoh.convertToArabicDigits()
        }
    }
    var info: String {
        didSet {
            info = info.convertToArabicDigits()
        }
    }
    var isChecked: Bool = true

    init(id: Int, book: String, archive: Int, muallif: Int, bithoqoh: String = "", info: String = "") {
        self.id = id
        self.book = StringInterner.shared.intern(book)
        self.archive = archive
        self.muallif = muallif
        self.bithoqoh = bithoqoh
        self.info = info
    }
}

class CategoryData: NSCopying {
    let id: Int
    let name: String
    let level: Int
    let order: Int
    var isChecked: Bool = true
    var children: [Any] = [] // Bisa berisi CategoryData atau BooksData

    init(id: Int, name: String, level: Int, order: Int) {
        self.id = id
        self.name = StringInterner.shared.intern(name)
        self.level = level
        self.order = order
    }

    func copy(with zone: NSZone? = nil) -> Any {
        return CategoryData(
            id: self.id,
            name: StringInterner.shared.intern(name),
            level: self.level,
            order: self.order
        )
    }
}

class BookContent {
    let id: Int
    var nash: String
    let page: Int
    let part: Int

    var surah: Int?
    var aya: Int?

    init(id: Int, nash: String, page: Int = 1, part: Int = 1) {
        self.id = id
        self.nash = nash.convertToArabicDigits()
        self.page = page
        self.part = part
    }
}

struct SearchResultItem: Codable {
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

        let data = try NSKeyedArchiver.archivedData(
            withRootObject: attributedText,
            requiringSecureCoding: false
        )
        try container.encode(data, forKey: .attributedText)
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

        attributedText = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSAttributedString.self,
            from: data
        ) ?? NSAttributedString(string: "")
    }
}

struct SavedResultsItem {
    let archive: String
    let tableName: String
    let query: String
    let bookId: Int
    let bookTitle: String
}

struct Muallif: Decodable {

    /// Nama pengarang (auth)
    let nama: String

    /// Informasi tambahan/biografi singkat pengarang (inf)
    let info: String // Opsional, mungkin kosong di DB

    /// Bahasa pengarang atau informasi bahasa (Lng)
    let namaLengkap: String // Opsional, tergantung penggunaannya

    // Properti tambahan yang sering ada di Syamilah (tapi tidak di kueri Anda)
    // let tahunWafatHijriah: Int? // (higriAD)
    // let tahunWafatMasehi: Int? // (AD)

    // MARK: - CodingKeys (Jika nama properti Swift berbeda dari nama Kolom SQL)
    private enum CodingKeys: String, CodingKey {
        case nama = "auth"
        case info = "inf"
        case namaLengkap = "Lng"
    }

    init(nama: String, info: String, namaLengkap: String) {
        self.nama = nama
        self.info = info
            .replacingOccurrences(of: "\\n", with: "\n")
            .convertToArabicDigits()
        self.namaLengkap = namaLengkap.convertToArabicDigits()
    }
}

// MARK: - 3. FUNGSI PENGAMBILAN DATA

extension BookConnection {

    /*
    // Fungsi helper untuk debugging tree structure dengan depth counter
    func printTree(_ nodes: [TOCNode], indent: String = "", level: Int = 0) {
        for node in nodes {
            print("\(indent)[\(node.id)] L\(node.level)-S\(node.sub): \(node.bab)")
            if !node.children.isEmpty {
                print("\(indent)  ↓ (\(node.children.count) children)")
                printTree(node.children, indent: indent + "  ", level: level + 1)
            }
        }
    }

    // Fungsi untuk validasi tree
    func validateTree(_ nodes: [TOCNode], parentLevel: Int = 0) -> Bool {
        for node in nodes {
            if parentLevel > 0 && node.level <= parentLevel {
                print("⚠️ ERROR: Child level (\(node.level)) <= parent level (\(parentLevel))")
                return false
            }
            if !validateTree(node.children, parentLevel: node.level) {
                return false
            }
        }
        return true
    }
     */
}
