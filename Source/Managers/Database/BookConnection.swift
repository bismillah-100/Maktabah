//
//  BookConnection.swift
//  maktab
//
//  Created by MacBook on 02/12/25.
//

import Foundation
import SQLite

class BookConnection {

    let basePath = DatabaseManager.shared.basePath
    private(set) var db: Connection?
    static let tocTreeCache = NSCache<NSNumber, NSArray>()
    private let totalPartsCache = NSCache<NSString, NSNumber>()

    init() {
        totalPartsCache.countLimit = 100  // max 100 books di cache
        totalPartsCache.name = "BookTotalPartsCache"
    }

    func connect(archive: Int) {
        guard let basePath else { return }
        do {
            db = try Connection("\(basePath)/\(archive).sqlite")
        } catch {
            #if DEBUG
                print("error connect to book.sqlite")
            #endif
        }
    }

    /*
    func fetchBook(archive: Int, bkId: Int) -> BookContent? {
        guard let basePath else { return nil }
        do {
            let db = try Connection("\(basePath)/\(archive).sqlite")
    
            // 1. Definisikan SQL Query dengan parameter placeholder (tanpa kutip)
            let querySQL = """
            SELECT bkid, bk
            FROM b\(bkId)
            WHERE id = ?
            """
    
            // 2. Siapkan Statement dengan binding (menggunakan String)
            let statement = try db.prepare(querySQL)
    
            // 3. Eksekusi dan iterasi
            for row in statement {
                // Catatan: row[0] adalah kolom 'nass', row[1] adalah kolom 'page'
    
                // Perbaikan: Ambil kolom nass (row[0]) dan pastikan nilainya String
                let nass = row[0] as? String ?? ""
    
                // Perbaikan: Ambil kolom page (row[1])
                let page = row[1] as? Int64 ?? -1 // Dapatkan nilai mentah dari kolom page
    
                let id = row[2] as? Int64 ?? -1 // Dapatkan id mentah dari kolom page
    
                let content = BookContent(id: Int(id), nash: nass, page: Int(page))
    
                print("Loaded content: page=\(page), length=\(nass.count)")
    
                // Kita hanya memproses baris pertama karena WHERE id = X harus unik
                return content
            }
    
        } catch {
            print("Error loading content: \(error)")
        }
    
        return nil
    }
     */

    func fetchTafseer(
        archive: Int,
        bkId: Int,
        for aya: Int,
        in surah: Int
    ) -> BookContent? {

        // pastikan koneksi
        if db == nil {
            connect(archive: archive)
        }

        guard let db else { return nil }

        let tableName = "b\(bkId)"

        let sql = """
            SELECT id, nass, page, part, sora, aya
            FROM \(tableName)
            WHERE sora = ? AND aya = ?
            LIMIT 1
            """

        do {
            let stmt = try db.prepare(sql)

            for row in stmt.bind(surah, aya) {
                guard let id = row[0] as? Int64,
                    let blob = row[1] as? Blob,
                    let page = row[2] as? Int64,
                    let part = row[3] as? Int64
                else {
                    #if DEBUG
                        print("error wrap content")
                    #endif
                    return nil
                }

                let nassBlob = Data(blob.bytes)
                let nass = ReusableFunc.decompressData(nassBlob)

                return BookContent(
                    id: Int(id),
                    nash: nass,
                    page: Int(page),
                    part: Int(part)
                )
            }
        } catch {
            #if DEBUG
                print("fetchTafseer error:", error.localizedDescription)
            #endif
        }
        return nil
    }

    func applyShortsMapping(to text: String, with map: [String: String])
        -> String
    {
        guard !map.isEmpty else { return text }

        var output = text

        // Urutkan key dari yang TERPANJANG ke TERPENDEK
        // supaya "An" tidak kalah dengan "A"
        let sortedKeys = map.keys.sorted { $0.count > $1.count }

        for key in sortedKeys {
            if let replacement = map[key] {
                output = output.replacingOccurrences(
                    of: key,
                    with: "\(replacement)\n"
                )
            }
        }

        return output
    }

    func getCached(bkId: String, idContent: Int) -> BookContent? {
        if let bkIdInt = Int(bkId),
            let cached = BookPageCache.shared.get(
                bookId: bkIdInt,
                contentId: idContent
            )
        {
            return cached
        }

        return nil
    }

    private func setCache(bkId: String, content: BookContent) {
        if let bookId = Int(bkId) {
            BookPageCache.shared.set(bookId: bookId, content: content)
        }
    }
}

extension BookConnection {
    /// UPDATED: getContent dengan decompress otomatis
    func getContent(bkid: String, contentId: Int, quran: Bool = false)
        -> BookContent?
    {
        guard let db else { return nil }

        if let cached = getCached(bkId: bkid, idContent: contentId) {
            #if DEBUG
                print("return cached")
            #endif
            return cached
        }

        do {
            let querySQL =
                quran
                ? quranContentQuery(forBook: bkid) : contentQuery(forBook: bkid)

            let contentIdAsString = String(contentId)
            let statement = try db.prepare(querySQL, contentIdAsString)
            let shortsMap = DatabaseManager.shared.loadShortsForBook(bkid)

            for row in statement {
                // ✅ Ambil sebagai Blob (Data), bukan String
                guard let blob = row[0] as? Blob else { continue }
                let nassBlob = Data(blob.bytes)

                // ✅ Decompress BLOB
                #if DEBUG
                    print(
                        "Loaded content: page=\(row[1] as? Int64 ?? 0), decompressed length=\(ReusableFunc.decompressData(nassBlob).count)"
                    )
                #endif
                let decompressedNass = ReusableFunc.decompressData(nassBlob)

                let page = row[1] as? Int64 ?? 0

                let id = row[2] as? Int64 ?? 0

                let part = row[3] as? Int64 ?? 0

                // Apply shorts mapping
                let finalNass =
                    shortsMap.isEmpty
                    ? decompressedNass
                    : applyShortsMapping(to: decompressedNass, with: shortsMap)

                let content = BookContent(
                    id: Int(id),
                    nash: finalNass,
                    page: Int(page),
                    part: Int(part)
                )

                if quran {
                    content.surah = Int(row[4] as? Int64 ?? -1)
                    content.aya = Int(row[5] as? Int64 ?? -1)
                }

                setCache(bkId: bkid, content: content)
                return content
            }

        } catch {
            #if DEBUG
                print("getContent: Error loading content \(error)")
            #endif
        }

        return nil
    }

    func getFirstContent(bkid: String) -> BookContent? {
        guard let db else { return nil }

        do {
            let querySQL = """
                SELECT nass, page, id, part
                FROM b\(bkid)
                ORDER BY id ASC
                LIMIT 1
                """

            let statement = try db.prepare(querySQL)
            let shortsMap = DatabaseManager.shared.loadShortsForBook(bkid)

            if let row = statement.makeIterator().next() {
                // Ambil sebagai Blob
                guard let blob = row[0] as? Blob else { return nil }
                let nassBlob = Data(blob.bytes)

                // Decompress
                let decompressedNass = ReusableFunc.decompressData(nassBlob)

                let page = row[1] as? Int64 ?? 0

                let id = row[2] as? Int64 ?? -1

                let part = row[3] as? Int64 ?? 0

                // Apply shorts mapping
                let finalNass =
                    shortsMap.isEmpty
                    ? decompressedNass
                    : applyShortsMapping(to: decompressedNass, with: shortsMap)

                let content = BookContent(
                    id: Int(id),
                    nash: finalNass,
                    page: Int(page),
                    part: Int(part)
                )

                setCache(bkId: bkid, content: content)
                return content
            }

        } catch {
            #if DEBUG
                print("getFirstContent: Error loading content \(error)")
            #endif
        }

        return nil
    }

    /// UPDATED: getContent by part and page
    func getContent(bkid: String, part: Int, page: Int) -> BookContent? {
        guard let db else { return nil }

        do {
            let querySQL = """
                SELECT nass, page, id, part
                FROM b\(bkid)
                WHERE part = ? AND page = ?
                LIMIT 1
                """

            let partAsString = String(part)
            let pageAsString = String(page)

            let statement = try db.prepare(querySQL, partAsString, pageAsString)
            let shortsMap = DatabaseManager.shared.loadShortsForBook(bkid)

            for row in statement {
                // ✅ Decompress BLOB
                guard let blob = row[0] as? Blob else { continue }
                let nassBlob = Data(blob.bytes)
                let decompressedNass = ReusableFunc.decompressData(nassBlob)

                let page = row[1] as? Int64 ?? -1

                let id = row[2] as? Int64 ?? -1
                let partValue = row[3] as? Int64 ?? -1

                let finalNass = applyShortsMapping(
                    to: decompressedNass,
                    with: shortsMap
                )

                let content = BookContent(
                    id: Int(id),
                    nash: finalNass,
                    page: Int(page),
                    part: Int(partValue)
                )

                setCache(bkId: bkid, content: content)
                return content
            }

        } catch {
            #if DEBUG
                print("Error loading content by part and page: \(error)")
            #endif
        }

        return nil
    }

    func getNextPage(
        from currentBook: BooksData,
        contentId: Int,
        quran: Bool = false
    ) -> BookContent? {
        guard
            let content = getContentByPage(
                bkid: "\(currentBook.id)",
                idNumber: contentId + 1,
                quran: quran
            )
        else {
            guard
                let content = getContentByPage(
                    bkid: "\(currentBook.id)",
                    idNumber: contentId + 2,
                    quran: quran
                )
            else { return nil }

            return content
        }

        return content
    }

    func getPrevPage(
        from currentBook: BooksData,
        contentId: Int,
        quran: Bool = false
    ) -> BookContent? {
        guard
            let content = getContentByPage(
                bkid: "\(currentBook.id)",
                idNumber: contentId - 1,
                quran: quran
            )
        else {
            guard
                let content = getContentByPage(
                    bkid: "\(currentBook.id)",
                    idNumber: contentId - 2,
                    quran: quran
                )
            else { return nil }

            return content
        }

        return content
    }

    func contentQuery(forBook bkid: String) -> String {
        """
        SELECT nass, page, id, part
        FROM b\(bkid)
        WHERE id = ?
        """
    }

    func quranContentQuery(forBook bkid: String) -> String {
        """
        SELECT nass, page, id, part, sora, aya
        FROM b\(bkid)
        WHERE id = ?
        """
    }

    /// UPDATED: getContentByPage
    func getContentByPage(bkid: String, idNumber: Int, quran: Bool = false)
        -> BookContent?
    {
        guard let db else { return nil }

        if let cached = getCached(bkId: bkid, idContent: idNumber) {
            #if DEBUG
                print("return cached")
            #endif
            return cached
        }

        do {
            let querySQL =
                quran
                ? quranContentQuery(forBook: bkid) : contentQuery(forBook: bkid)

            let pageNumberAsString = String(idNumber)
            let statement = try db.prepare(querySQL, pageNumberAsString)
            let shortsMap = DatabaseManager.shared.loadShortsForBook(bkid)

            for row in statement {
                // ✅ Decompress BLOB
                guard let blob = row[0] as? Blob else { continue }
                let nassBlob = Data(blob.bytes)
                let decompressedNass = ReusableFunc.decompressData(nassBlob)

                let page = row[1] as? Int64 ?? -1

                let id = row[2] as? Int64 ?? -1

                let part = row[3] as? Int64 ?? -1

                let finalNass =
                    shortsMap.isEmpty
                    ? decompressedNass
                    : applyShortsMapping(to: decompressedNass, with: shortsMap)

                let content = BookContent(
                    id: Int(id),
                    nash: finalNass,
                    page: Int(page),
                    part: Int(part)
                )

                if quran {
                    content.surah = Int(row[4] as? Int64 ?? -1)
                    content.aya = Int(row[5] as? Int64 ?? -1)
                }

                setCache(bkId: bkid, content: content)
                return content
            }

        } catch {
            #if DEBUG
                print("Error loading content by page: \(error)")
            #endif
        }

        return nil
    }

    /// Mendapatkan total jumlah juz/part dalam buku
    func getTotalParts(bkid: String) -> Int {
        let key = bkid as NSString

        // Cek cache dulu
        if let cached = totalPartsCache.object(forKey: key) {
            #if DEBUG
                print("📦 Cache HIT for book \(bkid)")
            #endif
            return cached.intValue
        }

        // Cache MISS - hitung dari database
        #if DEBUG
            print("💾 Cache MISS for book \(bkid) - querying database...")
        #endif
        let total = calculateTotalParts(bkid: bkid)

        // Simpan ke cache
        totalPartsCache.setObject(NSNumber(value: total), forKey: key)

        return total
    }

    private func calculateTotalParts(bkid: String) -> Int {
        guard let db else { return 0 }

        do {
            let querySQL = """
                SELECT MAX(
                    CAST(
                        CASE
                            WHEN instr(part, '-') > 0
                            THEN substr(part, 1, instr(part, '-') - 1)
                            ELSE part
                        END AS INTEGER
                    )
                )
                FROM b\(bkid)
                """

            let statement = try db.prepare(querySQL)

            for row in statement {
                if let totalParts = row[0] as? Int64 {
                    #if DEBUG
                        print("Total parts in book \(bkid): \(totalParts)")
                    #endif
                    return Int(totalParts)
                }
            }

        } catch {
            #if DEBUG
                print("Error getting total parts: \(error)")
            #endif
        }
        return 0
    }

    // Mendapatkan jumlah halaman dalam juz/part tertentu
    func getPagesInPart(bkid: String, part: Int) -> Int {
        guard let db else { return 0 }

        do {
            let querySQL = """
                SELECT MAX(page)
                FROM b\(bkid)
                WHERE part = ?
                """

            let partAsString = String(part)
            let statement = try db.prepare(querySQL, partAsString)

            for row in statement {
                let totalPages = row[0] as? Int64 ?? 0
                #if DEBUG
                    print("Total pages in part \(part): \(totalPages)")
                #endif
                return Int(totalPages)
            }

        } catch {
            #if DEBUG
                print("Error getting pages in part: \(error)")
            #endif
        }

        return 0
    }

    func getMinPagesInPart(bkid: String, part: Int) -> Int {
        guard let db else { return 0 }

        do {
            let querySQL = """
                SELECT MIN(page)
                FROM b\(bkid)
                WHERE part = ?
                """

            let partAsString = String(part)
            let statement = try db.prepare(querySQL, partAsString)

            for row in statement {
                let totalPages = row[0] as? Int64 ?? 0
                #if DEBUG
                    print("Total pages in part \(part): \(totalPages)")
                #endif
                return Int(totalPages)
            }

        } catch {
            #if DEBUG
                print("Error getting pages in part: \(error)")
            #endif
        }

        return 0
    }

    /// Mengambil semua entri TOC dari database.
    func getTOCEntries(_ book: BooksData) async -> [TOC] {
        var tocEntries: [TOC] = []
        connect(archive: book.archive)
        guard let db else { return [] }

        do {
            // Raw SQL dengan COALESCE untuk handle NULL
            let query = """
                SELECT id, tit, COALESCE(lvl, 0) as lvl, COALESCE(sub, 0) as sub
                FROM t\(book.id)
                ORDER BY id
                """

            for row in try db.prepare(query) {
                if Task.isCancelled {
                    // print("Proses getTOCEntries dibatalkan untuk buku \(book.id)")
                    return []
                }
                let toc = TOC(
                    bab: row[1] as? String ?? "",
                    level: Int(row[2] as? Int64 ?? 0),
                    sub: Int(row[3] as? Int64 ?? 0),
                    id: Int(row[0] as? Int64 ?? 0)
                )
                // print("row[0]:", row[0] ?? "", "row[2]:", row[2] ?? "", "row[3]:", row[3] ?? "")
                // print("toc level:", toc.level)
                tocEntries.append(toc)
            }
        } catch {
            #if DEBUG
                print("Gagal mengambil data TOC: \(error)")
            #endif
        }

        return tocEntries
    }

    func buildTOCTree(from flatTOCs: [TOC], bookId: Int) async -> [TOCNode] {
        guard !flatTOCs.isEmpty else { return [] }

        let key = NSNumber(value: bookId)
        if let cached = Self.tocTreeCache.object(forKey: key) as? [TOCNode] {
            return cached
        }

        // print("=== PASS 1: Buat semua nodes ===")

        // Pass 1: Buat semua node dulu, simpan dalam dictionary
        var allNodes: [TOCNode] = []
        var levelStacks: [Int: [TOCNode]] = [:]  // key = level, value = array of nodes di level itu

        for toc in flatTOCs {
            if Task.isCancelled {
                // print("Proses buildTOCTree dibatalkan untuk buku \(bookId)")
                return []
            }
            let node = TOCNode(from: toc)
            allNodes.append(node)

            // Simpan node berdasarkan level-nya
            if levelStacks[node.level] == nil {
                levelStacks[node.level] = []
            }
            levelStacks[node.level]?.append(node)

            // print("Created node ID:\(node.id) L:\(node.level) S:\(node.sub) - \(node.bab.prefix(40))")
        }

        // print("\n=== PASS 2: Bangun hierarki ===")

        // Pass 2: Identifikasi root nodes (level 1, sub 0)
        var rootNodes: [TOCNode] = []
        if let level1Nodes = levelStacks[1] {
            rootNodes = level1Nodes.filter { $0.sub == 0 }
            // print("Found \(rootNodes.count) root nodes (level 1, sub 0)")
        }

        // Pass 3: Hubungkan children ke parent
        // Urutkan level dari kecil ke besar untuk proses hierarki
        let sortedLevels = levelStacks.keys.sorted()

        for currentLevel in sortedLevels where currentLevel > 1 {
            if Task.isCancelled {
                // print("Proses buildTOCTree dibatalkan untuk buku \(bookId)")
                return []
            }
            guard let nodesAtCurrentLevel = levelStacks[currentLevel] else {
                continue
            }

            // print("\nProcessing level \(currentLevel) (\(nodesAtCurrentLevel.count) nodes)")

            for node in nodesAtCurrentLevel {
                if Task.isCancelled {
                    // print("Proses buildTOCTree dibatalkan untuk buku \(bookId)")
                    return []
                }
                // Cari parent: node di level yang lebih kecil
                var foundParent = false

                // Cari dari level terdekat ke bawah (currentLevel-1, currentLevel-2, ...)
                for parentLevel in stride(
                    from: currentLevel - 1,
                    through: 1,
                    by: -1
                ) {
                    if Task.isCancelled {
                        // print("Proses buildTOCTree dibatalkan untuk buku \(bookId)")
                        return []
                    }
                    guard let candidateParents = levelStacks[parentLevel] else {
                        continue
                    }

                    // Strategi: ambil parent terakhir yang ID-nya <= current node ID
                    // Ini mengasumsikan parent muncul sebelum/bersamaan dengan child dalam urutan ID
                    if let parent = candidateParents.last(where: {
                        $0.id <= node.id
                    }) {
                        parent.children.append(node)
                        // print("  ID:\(node.id) → CHILD of ID:\(parent.id) (L:\(parent.level)) '\(parent.bab.prefix(30))'")
                        foundParent = true
                        break
                    }
                }

                if !foundParent {
                    // Tidak ada parent, promosikan ke root
                    rootNodes.append(node)
                    // print("  ID:\(node.id) → PROMOTED TO ROOT (no parent found)")
                }
            }
        }

        // Cache disimpan dari TOCLoader
        return rootNodes
    }
}
