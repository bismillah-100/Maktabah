//
//  QuranDataManager.swift
//  maktab
//
//  Created by MacBook on 23/12/25.
//

import Foundation
import SQLite3

class QuranDataManager {
    static var shared: QuranDataManager = .init()
    private var db: SQLiteDatabase?

    private(set) var surahNodes: [SurahNode] = []
    private(set) lazy var tafseerBooks: [BooksData] = []

    let path = AppConfig.specialDatabasePath

    let bkConn = BookConnection()
    private(set) var selectedQuran: (aya: Int, surah: Int)?
    var selectedBook: BooksData?
    var currentBookContent: BookContent?

    private init() {
        guard let path else { return }
        do {
            db = try SQLiteDatabase(path: path, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
        } catch {
#if DEBUG
            print("error saat mencoba membuka database:", error)
#endif
        }
    }

    func connect(to book: BooksData) {
#if DEBUG
        print("QuranDataManager connect")
#endif
        try? bkConn.connect(archive: book.archive)
        selectedBook = book
    }

    @discardableResult
    func loadTafseer(for aya: Int, in surah: Int) -> String? {
#if DEBUG
        print("loadTafseer")
#endif
        selectedQuran = (aya: aya, surah: surah)
        guard let selectedBook else {
#if DEBUG
            print("no selectedBook")
#endif
            return nil
        }
        currentBookContent = bkConn.fetchTafseer(
            archive: selectedBook.archive,
            bkId: selectedBook.id,
            for: aya, in: surah
        )

        return currentBookContent?.nash
    }

    // =====================================================
    // FETCH QURAN → SURAH NODE
    // =====================================================

    func fetchSurahNodes() throws {
        guard let db else { return }

        let sql = """
        SELECT
            q.Id,
            q.nass,
            q.sora,
            q.aya,
            q.Page,
            s.sora AS surah_name
        FROM Qr q
        JOIN Sora s ON q.sora = s.id
        ORDER BY q.sora, q.aya
        """

        // Grouping sementara
        var surahMap: [Int: (name: String, aya: [Quran])] = [:]

        try db.fetch(query: sql) { row in
            let nass = row.string(at: 1) ?? ""
            let sora = row.int(at: 2)
            let aya = row.int(at: 3)
            let surahName = row.string(at: 5) ?? ""

            let ayat = Quran(
                nass: nass,
                aya: aya
            )

            if surahMap[sora] == nil {
                surahMap[sora] = (surahName, [])
            }
            surahMap[sora]?.aya.append(ayat)
        }

        // Build node berurutan
        let nodes = surahMap
            .sorted { $0.key < $1.key }
            .map { key, value in
                SurahNode(
                    id: key,
                    surah: value.name,
                    aya: value.aya
                )
            }

        surahNodes = nodes
#if DEBUG
        print("total nodes:", nodes.count)
#endif
    }

    func buildTafseerMap() {
        tafseerBooks.removeAll(keepingCapacity: true)

        for cat in LibraryDataManager.shared.allRootCategories {
            guard cat.id == 127 || cat.id == 70 else { continue }
            for case let book as BooksData in cat.children {
                if book.tafseerNam != nil {
                    tafseerBooks.append(book)
                }
            }
        }

#if DEBUG
        print("tafseerBooks:", tafseerBooks.count)
#endif
    }

    func nextPage() -> BookContent? {
        guard let selectedBook, let currentBookContent else { return nil }
        let content = bkConn.getNextPage(
            from: selectedBook,
            contentId: currentBookContent.id,
            quran: true
        )

        self.currentBookContent = content

        return content
    }

    func prevPage() -> BookContent? {
        guard let selectedBook, let currentBookContent else { return nil }
        let content = bkConn.getPrevPage(
            from: selectedBook,
            contentId: currentBookContent.id,
            quran: true
        )

        self.currentBookContent = content
        return content
    }

    func searchTafseerBooks(_ query: String) -> [BooksData] {
        let q = query
        guard !q.isEmpty else {
            return tafseerBooks
        }

        return tafseerBooks.filter {
            $0.book.contains(q)
                || ($0.tafseerNam?.contains(q) ?? false)
        }
    }

    func searchSurah(_ query: String) -> [SurahNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return surahNodes }

        let nq = q.normalizeArabic()

        return surahNodes.compactMap { surah in
            surah.surah.contains(nq) ? surah : nil
        }
    }
}
