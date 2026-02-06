//
//  TarjamahMenManager.swift
//  maktab
//
//  Created by MacBook on 22/12/25.
//
/*
import Foundation

class TarjamahGlobal {
    static let shared = TarjamahGlobal()

    lazy var dbConnect: SQLiteConnection? = {
        return try? SQLiteConnection(dbPath: "\(basePath)/Files/special.sqlite")
    }()

    private let basePath = "/Volumes/Dokumen/Downloads/Shamela/SQLite"

    // Cache koneksi per archive
    private var connectionPools: [Int: SQLiteConnectionPool] = [:]
    private let poolLock = NSLock()

    // Cache hasil pencarian
    private var searchCache: [String: [TarjamahMen]] = [:]
    private let cacheLock = NSLock()

    private init() {}

    // MARK: - Public Methods

    /// Pencarian global di men_b + men_u
    /// - Parameters:
    ///   - query: String pencarian
    ///   - limit: Maksimal hasil per tabel (total bisa 2x limit)
    /// - Returns: Array tarjamah yang cocok
    func searchTarjamah(query: String, limit: Int = 50) -> [TarjamahMen] {
        guard let conn = dbConnect else {
            print("connection error")
            return []
        }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        var results: [TarjamahMen] = []

        do {
            // 1) men_b (LIKE) -- sama seperti sebelumnya
            let sqlB = """
            SELECT Name, Bk, id, Manid, bid
            FROM men_b
            WHERE Name LIKE ?
            ORDER BY Bk, id
            LIMIT ?
            """
            let patternB = "%\(normalizedQuery)%"
            let rowsB = try conn.queryRows(sql: sqlB, params: [.text(patternB), .int(limit)])
            for r in rowsB {
                let name = r["Name"] as? String ?? ""
                let bk   = (r["Bk"] as? Int) ?? 0
                let id   = (r["Id"] as? Int) ?? 0
                let manid = (r["Manid"] as? Int) ?? 0

                var t = TarjamahMen(
                    name: name,
                    bk: bk,
                    id: id,
                    manid: manid
                )

                if let bookData = LibraryDataManager.shared.booksById[bk] {
                    t.bookTitle = bookData.book
                    t.archive = bookData.archive
                }
                results.append(t)
            }
            print("✅ men_b: Found \(rowsB.count) results")
        } catch {
            print("❌ Error men_b:", error)
        }

        // 2) men_u via FTS (pakai sqlite connection => MATCH bekerja)
        let menUStartIndex = results.count
        do {
            // normalisasi NFC + prefix
            let ftsKey = normalizedQuery.precomposedStringWithCanonicalMapping + "*"

            let sqlU = """
            SELECT
                main.Name,
                main.IsoName,
                main.Bk,
                main.Id,
                main.uId
            FROM men_u AS main
            INNER JOIN fts_db.men_u_fts AS fts
                ON fts.rowid = main.uId
            WHERE fts.IsoName_clean MATCH ?
            LIMIT ?
            """

            let rowsU = try conn.queryRows(sql: sqlU, params: [.text(ftsKey), .int(limit)])
            for r in rowsU {
                // Name
                var nameStr = ""
                if let data = r["Name"] as? Data {
                    nameStr = ReusableFunc.decompressData(data)
                } else if let s = r["Name"] as? String {
                    nameStr = s
                }

                // IsoName
                var isoStr = ""
                if let data = r["IsoName"] as? Data {
                    isoStr = ReusableFunc.decompressData(data)
                } else if let s = r["IsoName"] as? String {
                    isoStr = s
                }

                let bk  = (r["Bk"] as? Int) ?? 0
                let id  = (r["Id"] as? Int) ?? 0
                let uId = (r["uId"] as? Int) ?? 0

                print("---- men_u row ----")
                print("name   =", nameStr)
                print("iso    =", isoStr)
                print("Bk,Id,uId =", bk, id, uId)

                if id == 0 {
                    print("----------------------ERROR---------------------")
                    break
                }

                var t = TarjamahMen(
                    name: isoStr,
                    bk: bk,
                    id: id,
                    manid: nil
                )

                if let bookData = LibraryDataManager.shared.booksById[bk] {
                    t.bookTitle = bookData.book
                    t.archive = bookData.archive
                }

                results.append(t)
            }

            let menUCount = results.count - menUStartIndex
            print("✅ men_u (FTS): Found \(menUCount) results")

        } catch {
            print("❌ Error men_u (FTS):", error)
        }

        print("✅ Total: \(results.count) results for '\(normalizedQuery)'")
        return results
    }


    /// Load konten tarjamah lengkap dari archive (dengan BLOB decompression)
    /// - Parameter tarjamah: Entry tarjamah
    /// - Returns: Hasil lengkap dengan konten
    func loadTarjamahContent(_ tarjamah: TarjamahMen) async throws -> TarjamahResult {
        guard let archive = tarjamah.archive else {
            throw NSError(
                domain: "TarjamahMen",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Archive tidak ditemukan untuk book \(tarjamah.bk)"]
            )
        }

        let pool = try getOrCreateConnectionPool(forArchive: archive)

        let tableName = "b\(tarjamah.bk)"
        let sql = """
        SELECT nass
        FROM \(tableName)
        WHERE id = ?
        LIMIT 1
        """

        let rows = try await pool.read(at: 0) { conn in
            try conn.queryRows(sql: sql, params: [.int(tarjamah.id)])
        }

        guard let firstRow = rows.first else {
            throw NSError(
                domain: "TarjamahMen",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Row tidak ditemukan di \(tableName) id=\(tarjamah.id)"]
            )
        }

        // âœ… Handle BLOB atau TEXT
        var nass = ""
        if let blobData = firstRow["nass"] as? Data {
            // File archive (1-20.sqlite) = BLOB compressed
            nass = ReusableFunc.decompressData(blobData)
            print("✅ Decompressed BLOB: \(nass.count) chars")
        } else if let textData = firstRow["nass"] as? String {
            // File special.db = TEXT biasa
            nass = textData
            print("✅ Loaded TEXT: \(nass.count) chars")
        } else {
            throw NSError(
                domain: "TarjamahMen",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Kolom nass tidak valid di \(tableName) id=\(tarjamah.id)"]
            )
        }

        guard !nass.isEmpty else {
            throw NSError(
                domain: "TarjamahMen",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Konten kosong di \(tableName) id=\(tarjamah.id)"]
            )
        }

        return TarjamahResult(tarjamah: tarjamah, content: nass.snippetAround(keywords: [tarjamah.name], contextLength: 50))
    }

    /// Load konten untuk banyak tarjamah sekaligus
    /// - Parameters:
    ///   - tarjamahList: Array tarjamah yang ingin diload
    ///   - onProgress: Callback progress (current, total)
    /// - Returns: Array hasil lengkap
    func loadMultipleTarjamahContent(
        _ tarjamahList: [TarjamahMen],
        onProgress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async -> [TarjamahResult] {
        guard !tarjamahList.isEmpty else {
            print("⚠️ List tarjamah kosong")
            return []
        }

        var results: [TarjamahResult] = []

        for (index, tarjamah) in tarjamahList.enumerated() {
            do {
                let result = try await loadTarjamahContent(tarjamah)
                results.append(result)

                await MainActor.run {
                    onProgress(index + 1, tarjamahList.count)
                }
            } catch {
                print("❌ Error loading content for '\(tarjamah.name)': \(error.localizedDescription)")
            }
        }

        print("✅ Loaded \(results.count)/\(tarjamahList.count) tarjamah content")
        return results
    }

    /// Clear cache
    func clearCache() {
        cacheLock.lock()
        searchCache.removeAll()
        cacheLock.unlock()

        poolLock.lock()
        connectionPools.removeAll()
        poolLock.unlock()

        print("🗑️ Tarjamah global cache cleared")
    }

    // MARK: - Private Methods

    /// Get atau buat connection pool untuk archive
    private func getOrCreateConnectionPool(forArchive archive: Int) throws -> SQLiteConnectionPool {
        poolLock.lock()
        defer { poolLock.unlock() }

        if let pool = connectionPools[archive] {
            return pool
        }

        // Buat koneksi baru
        let dbPath = "\(basePath)/\(archive).sqlite"

        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw NSError(
                domain: "TarjamahMen",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "File tidak ditemukan: \(dbPath)"]
            )
        }

        var connections: [DBConnectionType] = []

        // Buat 4 koneksi untuk pool
        for i in 0..<4 {
            do {
                let conn = try SQLiteConnection(dbPath: dbPath)
                connections.append(conn)
            } catch {
                print("⚠️ Connection \(i+1) gagal untuk archive \(archive): \(error)")
            }
        }

        guard !connections.isEmpty else {
            throw NSError(
                domain: "TarjamahMen",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "Tidak bisa membuat koneksi ke archive \(archive)"]
            )
        }

        let pool = SQLiteConnectionPool(conns: connections)
        connectionPools[archive] = pool

        print("✅ Created connection pool for archive \(archive) (\(connections.count) connections)")

        return pool
    }

    // MARK: - Stats & Utilities

    /// Get statistik hasil pencarian
    func getSearchStats(_ results: [TarjamahMen]) -> (
        total: Int,
        byBook: [String: Int],
        byArchive: [Int: Int]
    ) {
        var byBook: [String: Int] = [:]
        var byArchive: [Int: Int] = [:]

        for tarjamah in results {
            // Per kitab
            let bookName = tarjamah.bookTitle ?? "Book \(tarjamah.bk)"
            byBook[bookName, default: 0] += 1

            // Per archive
            if let archive = tarjamah.archive {
                byArchive[archive, default: 0] += 1
            }
        }

        return (results.count, byBook, byArchive)
    }
}

// MARK: - Testing & Debug

extension TarjamahGlobal {

    /// Test function untuk debug pencarian
    func testSearch(query: String) async {
        print("\n🔍 === TEST GLOBAL SEARCH: '\(query)' ===")

        // 1. Search
        let results = searchTarjamah(query: query, limit: 50)

        if results.isEmpty {
            print("⚠️ Tidak ada hasil ditemukan")
            return
        }

        // 2. Stats
        let stats = getSearchStats(results)
        print("\n📊 Statistik:")
        print("  Total: \(stats.total) hasil")
        print("  Tersebar di \(stats.byBook.count) kitab")
        print("  Tersebar di \(stats.byArchive.count) archive")

        print("\n  Top 5 Kitab:")
        for (book, count) in stats.byBook.sorted(by: { $0.value > $1.value }).prefix(5) {
            print("    • \(book): \(count)")
        }

        // 3. Sample results
        print("\n📋 Sample hasil (10 pertama):")
        for (index, tarjamah) in results.prefix(10).enumerated() {
            let bookTitle = tarjamah.bookTitle ?? "Unknown"
            let archive = tarjamah.archive ?? 0

            print("  \(index + 1). \(tarjamah.name)")
            print("      ISO: \(tarjamah.name)")
            print("      Book: \(bookTitle) (ID: \(tarjamah.bk))")
            print("      Archive: \(archive), Row ID: \(tarjamah.id)")
        }

        if results.count > 10 {
            print("  ... dan \(results.count - 10) lainnya")
        }

        // 4. Load konten sample
        print("\n📖 Loading content (sample 3 pertama):")
        let sampleCount = min(3, results.count)

        for i in 0..<sampleCount {
            let tarjamah = results[i]

            do {
                let result = try await loadTarjamahContent(tarjamah)
                let preview = String(result.content.prefix(100))
                print("\n  [\(i + 1)] \(result.tarjamah.name)")
                print("      Preview: \(preview)...")
                print("      Length: \(result.content.count) chars")
            } catch {
                print("  [\(i + 1)] ❌ Error: \(error.localizedDescription)")
            }
        }
    }
}
 */

/*

 CARA PAKAI:

 // 1. Search global (men_b + men_u)
 let results = TarjamahMenManager.shared.searchTarjamah(
     query: "اسماعيل",
     limit: 100
 )

 // Filter by source jika perlu
 let menBOnly = results.filter { $0.source == .menB }
 let menUOnly = results.filter { $0.source == .menU }

 // 2. Load konten spesifik
 Task {
     do {
         let result = try await TarjamahMenManager.shared.loadTarjamahContent(tarjamah)
         // result.content sudah di-decompress otomatis
         textView.string = result.content
     } catch {
         print("Error: \(error)")
     }
 }

 // 3. Load multiple dengan progress
 Task {
     let results = await TarjamahMenManager.shared.loadMultipleTarjamahContent(
         selectedList,
         onProgress: { current, total in
             print("Loading \(current)/\(total)...")
         }
     )
 }

 // 4. Testing
 Task {
     await TarjamahMenManager.shared.testSearch(query: "اسماعيل")
 }

 // 5. Stats
 let stats = TarjamahMenManager.shared.getSearchStats(results)
 print("Total: \(stats.total), men_b: \(stats.menBCount), men_u: \(stats.menUCount)")

 */
