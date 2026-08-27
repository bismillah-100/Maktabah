//
//  BooksData.swift
//  Maktabah
//

import Foundation

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
