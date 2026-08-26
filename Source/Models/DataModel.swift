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

enum SearchSortKey: String, CaseIterable {
    case bookTitle, page, part, content

    var label: String {
        switch self {
        case .bookTitle: "Kitab"
        case .page: "Halaman"
        case .part: "Juz"
        case .content: "Konten"
        }
    }
}

enum SearchResultsSorter {
    static func sort(_ results: inout [SearchResultItem], by key: SearchSortKey, ascending asc: Bool) {
        switch key {
        case .bookTitle:
            results.sort {
                let cmp = $0.bookTitle.localizedStandardCompare($1.bookTitle)
                if cmp != .orderedSame { return asc ? cmp == .orderedAscending : cmp == .orderedDescending }
                if $0.part != $1.part { return asc ? $0.part < $1.part : $0.part > $1.part }
                return asc ? $0.page < $1.page : $0.page > $1.page
            }

        case .page:
            results.sort {
                let cmp = $0.bookTitle.localizedStandardCompare($1.bookTitle)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                if $0.part != $1.part { return $0.part < $1.part }
                return asc ? $0.page < $1.page : $0.page > $1.page
            }

        case .part:
            results.sort {
                let cmp = $0.bookTitle.localizedStandardCompare($1.bookTitle)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                if $0.part != $1.part { return asc ? $0.part < $1.part : $0.part > $1.part }
                return $0.page < $1.page
            }

        case .content:
            results.sort {
                let cmp = $0.attributedText.contentSortKey.localizedStandardCompare($1.attributedText.contentSortKey)
                return asc ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
    }
}

extension NSAttributedString {
    func trimmingCharacters(in set: CharacterSet) -> NSAttributedString {
        let nsString = string as NSString
        var start = 0
        var length = nsString.length

        while start < length {
            let charCode = nsString.character(at: start)
            guard let scalar = UnicodeScalar(charCode), set.contains(scalar) else {
                break
            }
            start += 1
        }

        while length > start {
            let charCode = nsString.character(at: length - 1)
            guard let scalar = UnicodeScalar(charCode), set.contains(scalar) else {
                break
            }
            length -= 1
        }

        return attributedSubstring(from: NSRange(location: start, length: length - start))
    }

    var contentSortKey: String {
        let plain = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // 2 kalimat = split by ". " atau ".\n", ambil 2 elemen pertama
        var sentences: [String] = []
        var current = ""
        for char in plain {
            current.append(char)
            if char == "." || char == "!" || char == "?" {
                sentences.append(current)
                current = ""
                if sentences.count == 2 { break }
            }
        }
        return sentences.joined()
    }
}

struct SavedResultsItem {
    let archive: String
    let tableName: String
    let query: String
    let bookId: Int
    let bookTitle: String
    var searchMode: Int = 0
    var nearDistance: Int = 10
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

// MARK: - NSAttributedString Secure Coding

extension NSAttributedString {
    static var secureCodingClasses: [AnyClass] {
        #if os(macOS)
        [
            NSAttributedString.self,
            NSMutableAttributedString.self,
            NSColor.self,
            NSFont.self,
            NSParagraphStyle.self,
            NSMutableParagraphStyle.self,
            NSDictionary.self,
            NSArray.self,
            NSString.self,
            NSNumber.self,
        ]
        #elseif canImport(UIKit)
        [
            NSAttributedString.self,
            NSMutableAttributedString.self,
            UIColor.self,
            UIFont.self,
            NSParagraphStyle.self,
            NSMutableParagraphStyle.self,
            NSDictionary.self,
            NSArray.self,
            NSString.self,
            NSNumber.self,
        ]
        #else
        [
            NSAttributedString.self,
            NSMutableAttributedString.self,
            NSParagraphStyle.self,
            NSMutableParagraphStyle.self,
            NSDictionary.self,
            NSArray.self,
            NSString.self,
            NSNumber.self,
        ]
        #endif
    }

    func archivedData() throws -> Data {
        try NSKeyedArchiver.archivedData(
            withRootObject: self,
            requiringSecureCoding: true
        )
    }

    static func unarchiveSecure(from data: Data) -> NSAttributedString? {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            let decoded = unarchiver.decodeObject(
                of: secureCodingClasses,
                forKey: NSKeyedArchiveRootObjectKey
            ) as? NSAttributedString
            unarchiver.finishDecoding()
            return decoded
        } catch {
            return nil
        }
    }
}
