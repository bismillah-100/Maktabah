//
//  DataModel.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

#if canImport(AppKit)
import AppKit
#endif
import Foundation

// MARK: - TOC dengan Children (untuk NSOutlineView)

class TOCNode: Identifiable {
    let bab: String
    let level: Int
    let sub: Int
    let id: Int
    var children: [TOCNode] = []

    var endID: Int = .max

    init(from toc: TOC) {
        bab = toc.bab.convertToArabicDigits()
        level = toc.level
        sub = toc.sub
        id = toc.id
    }
}

struct TOC {
    let bab: String // Memetakan ke kolom 'tit'
    let level: Int // Memetakan ke kolom 'lvl'
    let sub: Int
    let id: Int
}

class BooksData: Codable, Identifiable {
    let id: Int
    let book: String
    let normalizedBook: String

    let archive: Int
    let muallif: Int
    var catId: Int?
    var downloadFilename: String?
    var compressedDownloadSize: Int64?
    var tafseerNam: String?
    var pdfCs: Int?
    var isMultiLanguage: Bool {
        pdfCs == 3
    }

    var isImported: Bool {
        pdfCs == 4
    }

    var bithoqoh: String = .init() {
        didSet {
            bithoqoh = bithoqoh.convertToArabicDigits()
        }
    }

    var info: String = .init() {
        didSet {
            info = info.convertToArabicDigits()
        }
    }

    var isChecked: Bool = true

    init(id: Int, book: String, archive: Int, muallif: Int, bithoqoh: String = "", info: String = "") {
        self.id = id
        self.book = StringInterner.shared.intern(book)
        normalizedBook = book.normalizeArabic(false)
        self.archive = archive
        self.muallif = muallif
        self.bithoqoh = bithoqoh.convertToArabicDigits()
        self.info = info.convertToArabicDigits()
    }
}

class CategoryData {
    let id: Int
    let name: String
    let normalizedName: String
    let level: Int
    let order: Int
    var isChecked: Bool = true
    var children: [Any] = [] // Bisa berisi CategoryData atau BooksData

    init(id: Int, name: String, level: Int, order: Int) {
        self.id = id
        self.name = StringInterner.shared.intern(name)
        normalizedName = name.normalizeArabic(false)
        self.level = level
        self.order = order
    }

    func copy(with zone: NSZone? = nil) -> CategoryData {
        CategoryData(
            id: id,
            name: StringInterner.shared.intern(name),
            level: level,
            order: order
        )
    }

    var allBooks: [BooksData] {
        var result: [BooksData] = []
        collectBooks(into: &result)
        return result
    }

    var allSubcategories: [CategoryData] {
        var result: [CategoryData] = []
        collectSubcategories(into: &result)
        return result
    }

    private func collectBooks(into books: inout [BooksData]) {
        for child in children {
            if let book = child as? BooksData {
                books.append(book)
            } else if let sub = child as? CategoryData {
                sub.collectBooks(into: &books)
            }
        }
    }

    private func collectSubcategories(into categories: inout [CategoryData]) {
        for child in children {
            if let sub = child as? CategoryData {
                categories.append(sub)
                sub.collectSubcategories(into: &categories)
            }
        }
    }
}

struct CleanedTextKey: Hashable {
    let showHarakat: Bool
    let isMultiLanguage: Bool
    let isImported: Bool
}

final class ProcessedArabicContent {
    let sourceText: String
    let displayText: String
    let coloredRanges: [NSRange]
    let footnoteRanges: [NSRange]
    let replacementEvents: [HonorificReplacementEvent]
    let importedHeaderRanges: [NSRange]
    let ligatureRanges: [NSRange]

    init(
        sourceText: String,
        displayText: String,
        coloredRanges: [NSRange],
        footnoteRanges: [NSRange],
        replacementEvents: [HonorificReplacementEvent],
        importedHeaderRanges: [NSRange],
        ligatureRanges: [NSRange]
    ) {
        self.sourceText = sourceText
        self.displayText = displayText
        self.coloredRanges = coloredRanges
        self.footnoteRanges = footnoteRanges
        self.replacementEvents = replacementEvents
        self.importedHeaderRanges = importedHeaderRanges
        self.ligatureRanges = ligatureRanges
    }
}

class BookContent {
    let id: Int
    let nash: String
    let page: Int
    let part: Int

    var surah: Int?
    var aya: Int?

    init(id: Int, nash: String, page: Int = 1, part: Int = 1) {
        self.id = id
        self.nash = nash
        self.page = page
        self.part = part
    }
}

struct Muallif: Decodable {
    /// Nama pengarang (auth)
    let nama: String

    /// Informasi tambahan/biografi singkat pengarang (inf)
    let info: String // Opsional, mungkin kosong di DB

    /// Bahasa pengarang atau informasi bahasa (Lng)
    let namaLengkap: String // Opsional, tergantung penggunaannya

    // Properti tambahan yang sering ada di Syamilah (tapi tidak di kueri Anda)

    // MARK: - CodingKeys (Jika nama properti Swift berbeda dari nama Kolom SQL)

    private enum CodingKeys: String, CodingKey {
        case nama = "auth"
        case info = "inf"
        case namaLengkap = "Lng"
    }

    init(nama: String, info: String, namaLengkap: String) {
        self.nama = nama
        self.info = info
            .replacing("\\n", with: "\n")
            .convertToArabicDigits()
        self.namaLengkap = namaLengkap.convertToArabicDigits()
    }
}

