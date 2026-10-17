//
//  SearchTests.swift
//  MaktabahTests
//

import Foundation
@testable import Maktabah_Debug
import Testing

struct SearchTests {
    // MARK: - 1. FtsQueryParser Tests

    @Test("FtsQueryParser: Format query sesuai SearchMode (phrase, contains, or, near)")
    func testFtsQueryParser_modes() {
        let query = "إنما الأعمال بالنيات"

        // Mode Phrase: menghasilkan string quoted
        let phraseResult = FtsQueryParser.buildFtsQuery(query: query, mode: .phrase)
        #expect(phraseResult.hasPrefix("\""))
        #expect(phraseResult.hasSuffix("\""))

        // Mode Contains: dipisahkan oleh operator 'AND'
        let containsResult = FtsQueryParser.buildFtsQuery(query: query, mode: .contains)
        #expect(containsResult.contains(" AND "))

        // Mode Or: dipisahkan oleh operator 'OR'
        let orResult = FtsQueryParser.buildFtsQuery(query: query, mode: .or)
        #expect(orResult.contains(" OR "))

        // Mode Near: menggunakan sintaks NEAR(...)
        let nearResult = FtsQueryParser.buildFtsQuery(query: "الصلاة الصيام", mode: .near, nearDistance: 5)
        #expect(nearResult.contains("NEAR("))
        #expect(nearResult.contains(", 5)"))
    }

    @Test("FtsQueryParser: Deteksi dan ekstraksi sintaks explicit NEAR manual oleh user")
    func testFtsQueryParser_explicitNear() {
        let query1 = "الصلاة NEAR/7 الزكاة"
        let distance1 = FtsQueryParser.extractNearDistance(query: query1)
        #expect(distance1 == 7)

        let parsedQuery1 = FtsQueryParser.buildFtsQuery(query: query1, mode: .contains)
        #expect(parsedQuery1.contains("NEAR("))
        #expect(parsedQuery1.contains(", 7)"))

        // Dengan angka arab timur: NEAR/١٥
        let queryArabicDigits = "الإيمان NEAR/١٥ الإحسان"
        let distanceArabic = FtsQueryParser.extractNearDistance(query: queryArabicDigits)
        #expect(distanceArabic == 15)
    }

    @Test("FtsQueryParser: Ekstraksi keyword bersih untuk snippet highlighting")
    func testFtsQueryParser_extractKeywords() {
        let query = "قَالَ رَسُولُ اللَّهِ"
        let keywords = FtsQueryParser.extractKeywords(query: query, mode: .contains)

        // Harakat harus di-strip dalam keyword list
        #expect(!keywords.isEmpty)
        for kw in keywords {
            #expect(!kw.contains("\u{064E}")) // Fathah
            #expect(!kw.contains("\u{064F}")) // Dammah
        }
    }

    // MARK: - 2. SearchResultsSorter Tests

    @Test("SearchResultsSorter: Sorting hasil pencarian berdasarkan judul, juz/part, dan halaman")
    func testSearchResultsSorter() {
        var items = [
            SearchResultItem(archive: "1", tableName: "b1", bookId: 1, bookTitle: "Buku B", page: 10, part: 2),
            SearchResultItem(archive: "1", tableName: "b1", bookId: 2, bookTitle: "Buku A", page: 50, part: 1),
            SearchResultItem(archive: "1", tableName: "b1", bookId: 3, bookTitle: "Buku A", page: 12, part: 1),
            SearchResultItem(archive: "1", tableName: "b1", bookId: 4, bookTitle: "Buku A", page: 5, part: 2)
        ]

        // 1. Sort by Book Title (Ascending)
        SearchResultsSorter.sort(&items, by: .bookTitle, ascending: true)
        #expect(items[0].bookTitle == "Buku A")
        #expect(items[1].bookTitle == "Buku A")
        #expect(items[2].bookTitle == "Buku A")
        #expect(items[3].bookTitle == "Buku B")

        // 2. Sort by Page (Ascending) di dalam buku/part yang sama
        SearchResultsSorter.sort(&items, by: .page, ascending: true)
        let bukuAPart1 = items.filter { $0.bookTitle == "Buku A" && $0.part == 1 }
        #expect(bukuAPart1.count == 2)
        #expect(bukuAPart1[0].page == 12)
        #expect(bukuAPart1[1].page == 50)

        // 3. Sort by Part (Ascending)
        SearchResultsSorter.sort(&items, by: .part, ascending: true)
        let firstPart = items.first(where: { $0.bookTitle == "Buku A" })
        #expect(firstPart?.part == 1)
    }

    // MARK: - 3. SearchResultBuffer Tests

    @Test("SearchResultBuffer: Batching & manual flush")
    func testSearchResultBuffer() {
        let flushedItems = LockIsolated<[SearchResultItem]>([])

        let buffer = SearchResultBuffer(batchSize: 5, flushInterval: .milliseconds(500)) { items in
            flushedItems.withValue { $0.append(contentsOf: items) }
        }

        // Tambahkan 3 item (belum mencapai batchSize 5)
        for i in 1 ... 3 {
            buffer.append(SearchResultItem(archive: "1", tableName: "b1", bookId: i, bookTitle: "Judul", page: i, part: 1))
        }

        #expect(flushedItems.value.isEmpty)

        // Panggil flush manual
        buffer.flush()

        #expect(flushedItems.value.count == 3)
    }

    // MARK: - 4. SearchViewModel Completion Cooldown Tests

    @Test("SearchViewModel: handleSearchCompletion memicu cooldown dan menghentikan status isSearching")
    @MainActor
    func testSearchViewModel_handleSearchCompletion() async throws {
        let viewModel = SearchViewModel()
        viewModel.isSearching = true

        viewModel.handleSearchCompletion()

        // Sesaat setelah memicu completion, status searching masih aktif selama cooldown
        #expect(viewModel.isSearching == true)

        // Tunggu cooldown selesai (1.0 detik di macOS)
        try await Task.sleep(for: .milliseconds(1000))
        await Task.yield()
        #expect(viewModel.isSearching == false)
    }

    @Test("SearchViewModel: stopSearch membatalkan dismissTask completion yang sedang berjalan")
    @MainActor
    func testSearchViewModel_stopSearchCancelsDismissTask() {
        let viewModel = SearchViewModel()
        viewModel.isSearching = true

        viewModel.handleSearchCompletion()
        viewModel.stopSearch()

        #expect(viewModel.isSearching == false)
    }
}

/// Helper isolation wrapper untuk testing callback asynchronous
private final class LockIsolated<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) {
        _value = value
    }

    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func withValue(_ mutate: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        mutate(&_value)
    }
}
