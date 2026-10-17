//
//  BookPageCacheTests.swift
//  MaktabahTests
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("BookPageCache Tests", .serialized)
struct BookPageCacheTests {
    let cache = BookPageCache.shared

    init() {
        cache.removeAll()
    }

    @Test("Cache hit dan miss untuk BookContent")
    func testGetAndSet_BookContent() {
        let bookId = 9901
        let contentId = 101
        let content = BookContent(id: contentId, nash: "الحمد لله رب العالمين", page: 1, part: 1)

        // Verifikasi awal: Cache Miss
        #expect(cache.get(bookId: bookId, contentId: contentId) == nil)

        // Set ke cache
        cache.set(bookId: bookId, content: content)

        // Verifikasi: Cache Hit
        let retrieved = cache.get(bookId: bookId, contentId: contentId)
        #expect(retrieved != nil)
        #expect(retrieved?.id == contentId)
        #expect(retrieved?.nash == content.nash)
        #expect(retrieved?.page == 1)
        #expect(retrieved?.part == 1)
    }

    @Test("Subkey isolasi pada ProcessedArabicContent berdasarkan kombinasi CleanedTextKey")
    func testProcessedSubkey_isolation() {
        let bookId = 9902
        let contentId = 202

        let keyWithHarakat = CleanedTextKey(showHarakat: true, isMultiLanguage: false, isImported: false)
        let keyWithoutHarakat = CleanedTextKey(showHarakat: false, isMultiLanguage: false, isImported: false)

        let processedWithHarakat = ProcessedArabicContent(
            sourceText: "بِسْمِ اللَّهِ",
            displayText: "بِسْمِ اللَّهِ",
            coloredRanges: [],
            footnoteRanges: [],
            replacementEvents: [],
            importedHeaderRanges: [],
            ligatureRanges: []
        )

        let processedWithoutHarakat = ProcessedArabicContent(
            sourceText: "بسم الله",
            displayText: "بسم الله",
            coloredRanges: [],
            footnoteRanges: [],
            replacementEvents: [],
            importedHeaderRanges: [],
            ligatureRanges: []
        )

        cache.setProcessed(bookId: bookId, contentId: contentId, key: keyWithHarakat, content: processedWithHarakat)
        cache.setProcessed(bookId: bookId, contentId: contentId, key: keyWithoutHarakat, content: processedWithoutHarakat)

        let retrievedWith = cache.getProcessed(bookId: bookId, contentId: contentId, key: keyWithHarakat)
        let retrievedWithout = cache.getProcessed(bookId: bookId, contentId: contentId, key: keyWithoutHarakat)

        #expect(retrievedWith?.displayText == "بِسْمِ اللَّهِ")
        #expect(retrievedWithout?.displayText == "بسم الله")
    }

    @Test("Hapus cache per-buku dan hapus seluruh cache")
    func testRemoveAndRemoveAll() {
        let bookA = 9903
        let bookB = 9904

        let contentA = BookContent(id: 1, nash: "Konten A")
        let contentB = BookContent(id: 2, nash: "Konten B")

        cache.set(bookId: bookA, content: contentA)
        cache.set(bookId: bookB, content: contentB)

        #expect(cache.get(bookId: bookA, contentId: 1) != nil)
        #expect(cache.get(bookId: bookB, contentId: 2) != nil)

        // Hapus spesifik buku A
        cache.remove(bookId: bookA)
        #expect(cache.get(bookId: bookA, contentId: 1) == nil)
        #expect(cache.get(bookId: bookB, contentId: 2) != nil)

        // Hapus semua
        cache.removeAll()
        #expect(cache.get(bookId: bookB, contentId: 2) == nil)
    }
}
