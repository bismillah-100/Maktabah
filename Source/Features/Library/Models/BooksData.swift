//
//  BooksData.swift
//  Maktabah
//

import Foundation

final class BooksData: Codable, Identifiable, @unchecked Sendable {
    let id: Int
    var book: String
    var normalizedBook: String

    var archive: Int
    var muallif: Int
    var catId: Int?
    var downloadFilename: String?
    var compressedDownloadSize: Int64?
    var tafseerNam: String?
    var pdfCs: Int?
    var oNum: Int?
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
        normalizedBook = book.normalizeArabic()
        self.archive = archive
        self.muallif = muallif
        self.bithoqoh = bithoqoh.convertToArabicDigits()
        self.info = info.convertToArabicDigits()
    }

    func applyMetadata(from updated: BooksData) {
        guard id == updated.id else { return }
        book = StringInterner.shared.intern(updated.book)
        normalizedBook = updated.normalizedBook
        archive = updated.archive
        muallif = updated.muallif
        catId = updated.catId
        downloadFilename = updated.downloadFilename
        compressedDownloadSize = updated.compressedDownloadSize
        tafseerNam = updated.tafseerNam
        pdfCs = updated.pdfCs
        oNum = updated.oNum
        bithoqoh = updated.bithoqoh
        info = updated.info
    }
}
