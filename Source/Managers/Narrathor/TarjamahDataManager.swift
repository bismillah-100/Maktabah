//
//  TarjamahDataManager.swift
//  maktab
//
//  Created by MacBook on 12/12/25.
//
//  Refactored: Unified Manager + Pause/Resume + Streaming Results

import Foundation
import SQLite
import SQLite3

actor TarjamahDatabaseActor {
    private let conn: SQLiteConnection

    init(dbPath: String) throws {
        self.conn = try SQLiteConnection(dbPath: dbPath)
    }

    func queryRows(sql: String, params: [SQLValue]) throws -> [[String: Any?]] {
        return try conn.queryRows(sql: sql, params: params)
    }
}

class TarjamahGlobalManager {
    static let shared = TarjamahGlobalManager()

    private let basePath = DatabaseManager.shared.basePath

    // MARK: - Caching
    // Cache koneksi per archive (1.sqlite, 2.sqlite...)
    private var connectionPools: [Int: SQLiteConnectionPool] = [:]
    private let poolLock = NSLock()

    // Cache hasil pencarian Rowa (Query by ID) - Sangat efektif di-cache
    private var rowaCache: [Int: [TarjamahMen]] = [:]

    // Cache hasil pencarian text (Query String) - Optional, hati-hati memori
    private var searchStringCache: [String: [TarjamahMen]] = [:]

    // Ganti dbConnect & dbLock dengan Actor
    private var dbActor: TarjamahDatabaseActor?

    private init() {
        guard let basePath else { return }
        // Inisialisasi actor
        self.dbActor = try? TarjamahDatabaseActor(dbPath: "\(basePath)/Files/special.sqlite")
    }

    // MARK: - 1. Global Search (String) with Pause & Streaming

    /// Pencarian text global (men_b LIKE & men_u FTS) dengan fitur Pause & Streaming
    func searchTarjamah(
        query: String,
        limit: Int = 50,
        pauseController: PauseController?, // Opsional
        stopFlag: @escaping () -> Bool,    // Closure untuk cek stop
        onBatchResult: @escaping @Sendable ([TarjamahMen]) async -> Void, // Ubah jadi async
        onComplete: @escaping () -> Void
    ) async {

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            onComplete()
            return
        }

        // 1. Cek Cache dulu
        if let cached = searchStringCache[normalizedQuery] {
            print("📦 Cache Hit for query: \(normalizedQuery)")
            await onBatchResult(cached) // Kirim semua langsung
            onComplete()
            return
        }

        guard let conn = dbActor else {
            print("❌ Connection error")
            onComplete()
            return
        }

        var allResults: [TarjamahMen] = []
        var batchBuffer: [TarjamahMen] = []

        // Helper untuk flush buffer
        func flushBuffer() async {
            if !batchBuffer.isEmpty {
                let chunk = batchBuffer
                batchBuffer.removeAll()
                // Update ke Main Thread jika perlu, atau biarkan caller handle
                await onBatchResult(chunk)
            }
        }

        // ---------------------------------------------------------
        // A. Search di men_b (LIKE)
        // ---------------------------------------------------------
        do {
            if stopFlag() { return }
            await pauseController?.waitIfPaused()

            let ftsQuery = "\"\(normalizedQuery)\" *"   // phrase + prefix

            let sqlB = """
            SELECT main.Name, main.Bk, main.Id, main.ManId, main.bId
            FROM men_b AS main
            JOIN men_b_fts AS fts ON main.Id = fts.rowid
            WHERE fts.Name_clean MATCH ?
            ORDER BY main.Bk, main.Id
            LIMIT ?
            """

            let rowsB = try await conn.queryRows(
                sql: sqlB,
                params: [.text(ftsQuery), .int(limit)]
            )

            for (index, r) in rowsB.enumerated() {
                if index % 10 == 0 {
                    if stopFlag() { return }
                    await pauseController?.waitIfPaused()
                }

                let name  = r["Name"] as? String ?? ""
                let bk    = (r["Bk"] as? Int) ?? 0
                let id    = (r["Id"] as? Int) ?? 0

                var t = TarjamahMen(name: name, bk: bk, id: id)

                if let bookData = LibraryDataManager.shared.getBook([bk]).first {
                    t.bookTitle = bookData.book
                    t.archive   = bookData.archive
                }

                allResults.append(t)
                batchBuffer.append(t)

                if batchBuffer.count >= 5 {
                    await flushBuffer()
                }
            }
        } catch {
            print("❌ Error men_b (FTS):", error)
        }

        await flushBuffer() // Sisa buffer men_b

        // ---------------------------------------------------------
        // B. Search di men_u (FTS)
        // ---------------------------------------------------------
        do {
            if stopFlag() { return }
            await pauseController?.waitIfPaused()

            let ftsQuery = "\"\(normalizedQuery)\" *" // Phrase + Prefix

            let sqlU = """
            SELECT main.Name, main.IsoName, main.Bk, main.Id, main.uId
            FROM men_u AS main
            JOIN men_u_fts AS fts ON main.uId = fts.rowid
            WHERE fts.IsoName_clean MATCH ?
            ORDER BY main.Bk, main.Id
            LIMIT ?
            """

            let rowsU = try await conn.queryRows(sql: sqlU, params: [.text(ftsQuery), .int(limit)])

            for (index, r) in rowsU.enumerated() {
                if index % 10 == 0 {
                    if stopFlag() { return }
                    await pauseController?.waitIfPaused()
                }

                // Handle Blob Decompression
                var isoStr = ""
                if let data = r["IsoName"] as? Data {
                    isoStr = ReusableFunc.decompressData(data)
                } else if let s = r["IsoName"] as? String {
                    isoStr = s
                }

                let bk = (r["Bk"] as? Int) ?? 0
                let id = (r["Id"] as? Int) ?? 0

                var t = TarjamahMen(name: isoStr, bk: bk, id: id) // manid nil di men_u

                if let bookData = LibraryDataManager.shared.getBook([bk]).first {
                    t.bookTitle = bookData.book
                    t.archive = bookData.archive
                }

                allResults.append(t)
                batchBuffer.append(t)

                if batchBuffer.count >= 5 {
                    await flushBuffer()
                }
            }
        } catch {
            print("❌ Error men_u:", error)
        }

        await flushBuffer() // Sisa buffer akhir

        // Simpan ke cache untuk query ini
        searchStringCache[normalizedQuery] = allResults

        onComplete()
    }

    // MARK: - 2. Rowa Lookup (Search by ID) - Merged from MenBManager

    /// Load daftar tarjamah berdasarkan ID Rawi (Rowa)
    func loadTarjamahList(forRowa rowaId: Int) async -> [TarjamahMen] {
        // 1. Cek Cache Rowa
        if let cached = rowaCache[rowaId] {
            // print("📦 Cache hit for Rowa \(rowaId)")
            return cached
        }

        guard let conn = dbActor else { return [] }
        var results: [TarjamahMen] = []

        do {
            let sql = """
            SELECT Name, Bk, Id, ManId
            FROM men_b
            WHERE Manid = ?
            ORDER BY Bk, Id
            """

            let rows = try await conn.queryRows(sql: sql, params: [.int(rowaId)])

            for r in rows {
                let name = r["Name"] as? String ?? ""
                let bk   = (r["Bk"] as? Int) ?? 0
                let id   = (r["Id"] as? Int) ?? 0

                var t = TarjamahMen(name: name, bk: bk, id: id)

                if let bookData = LibraryDataManager.shared.getBook([bk]).first {
                    t.bookTitle = bookData.book
                    t.archive = bookData.archive
                }
                results.append(t)
            }

            // 2. Simpan ke Cache
            if !results.isEmpty {
                rowaCache[rowaId] = results
            }

        } catch {
            print("❌ Error loadTarjamahList: \(error)")
        }

        return results
    }

    // MARK: - 3. Content Loading with Pause & Streaming

    /// Load content untuk banyak item sekaligus dengan progress streaming
    func loadMultipleTarjamahContent(
        _ tarjamahList: [TarjamahMen],
        pauseController: PauseController?,
        stopFlag: @escaping () -> Bool,
        onBatchResult: @escaping ([TarjamahResult]) -> Void,
        onProgress: @escaping (Int, Int) -> Void
    ) async {

        guard !tarjamahList.isEmpty else { return }

        var batchBuffer: [TarjamahResult] = []

        for (index, tarjamah) in tarjamahList.enumerated() {
            // Cek Stop
            if stopFlag() {
                print("🛑 Loading stopped at index \(index)")
                break
            }

            // Cek Pause
            await pauseController?.waitIfPaused()

            do {
                guard let result = try await loadTarjamahContent(tarjamah) else { break }
                batchBuffer.append(result)

                // Stream setiap 5 item selesai
                if batchBuffer.count >= 5 {
                    let chunk = batchBuffer
                    batchBuffer.removeAll()
                    await MainActor.run {
                        onBatchResult(chunk)
                    }
                }

                // Update progress UI
                await MainActor.run {
                    onProgress(index + 1, tarjamahList.count)
                }

            } catch {
                print("⚠️ Error loading '\(tarjamah.name)': \(error.localizedDescription)")
            }
        }

        // Flush sisa buffer
        if !batchBuffer.isEmpty {
            let chunk = batchBuffer
            await MainActor.run {
                onBatchResult(chunk)
            }
        }
    }

    /// Load konten single (Atomic operation)
    func loadTarjamahContent(_ tarjamah: TarjamahMen) async throws -> TarjamahResult? {
        guard let archive = tarjamah.archive else {
            throw NSError(domain: "Tarjamah", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Archive ID"])
        }

        guard let pool = try getOrCreateConnectionPool(forArchive: archive) else { return nil }
        let tableName = "b\(tarjamah.bk)"

        let sql = "SELECT nass FROM \(tableName) WHERE id = ? LIMIT 1"

        let rows = try await pool.read(at: 0) { conn in
            try conn.queryRows(sql: sql, params: [.int(tarjamah.id)])
        }

        guard let firstRow = rows.first else {
            throw NSError(domain: "Tarjamah", code: -2, userInfo: [NSLocalizedDescriptionKey: "Not found"])
        }

        var nass = ""
        // Handle BLOB (Compressed) or TEXT
        if let blobData = firstRow["nass"] as? Data {
            nass = ReusableFunc.decompressData(blobData)
        } else if let textData = firstRow["nass"] as? String {
            nass = textData
        }

        // Buat snippet
        let snippet = nass.snippetAround(keywords: [tarjamah.name], contextLength: 100)

        return TarjamahResult(tarjamah: tarjamah, content: snippet) // atau return nass full
    }

    /// Load semua konten tarjamah untuk rawi
    /// - Parameters:
    ///   - rowaId: ID rawi
    ///   - onProgress: Callback progress (current, total)
    /// - Returns: Array hasil lengkap
    func loadAllTarjamahContent(
        forRowa rowaId: Int,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async -> [TarjamahResult] {
        let tarjamahList = await loadTarjamahList(forRowa: rowaId)

        guard !tarjamahList.isEmpty else {
            print("⚠️ Tidak ada tarjamah untuk rowa \(rowaId)")
            return []
        }

        var results: [TarjamahResult] = []

        for (index, tarjamah) in tarjamahList.enumerated() {
            do {
                guard let result = try await loadTarjamahContent(tarjamah) else { break }
                results.append(result)

                await MainActor.run {
                    onProgress(index + 1, tarjamahList.count)
                }
            } catch {
                print("❌ Error loading content for \(tarjamah.name): \(error)")
            }
        }

        print("✅ Loaded \(results.count)/\(tarjamahList.count) tarjamah content")
        return results
    }

    // MARK: - Utilities
    private func getOrCreateConnectionPool(forArchive archive: Int) throws -> SQLiteConnectionPool? {
        poolLock.lock()
        defer { poolLock.unlock() }

        guard let basePath else { return nil }

        if let pool = connectionPools[archive] { return pool }

        let dbPath = "\(basePath)/\(archive).sqlite"
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw NSError(domain: "Tarjamah", code: -5, userInfo: [NSLocalizedDescriptionKey: "File missing: \(dbPath)"])
        }

        var connections: [DBConnectionType] = []
        // Gunakan 2 koneksi cukup untuk tarjamah lookup (tidak butuh 4 seperti search full)
        for _ in 0..<2 {
            if let conn = try? SQLiteConnection(dbPath: dbPath) {
                connections.append(conn)
            }
        }

        let pool = SQLiteConnectionPool(conns: connections)
        connectionPools[archive] = pool
        return pool
    }
}

/*

 CARA PAKAI:

 // 1. Load list tarjamah (tanpa konten)
 let tarjamahList = TarjamahMenBManager.shared.loadTarjamahList(forRowa: rowaId)

 // Tampilkan di UI (table/list)
 for tarjamah in tarjamahList {
     print("\(tarjamah.name) - \(tarjamah.bookTitle ?? "")")
 }

 // 2. Load konten spesifik saat user klik
 Task {
     do {
         let result = try await TarjamahMenBManager.shared.loadTarjamahContent(tarjamah)
         // Tampilkan result.content di text view
     } catch {
         print("Error: \(error)")
     }
 }

 // 3. Load semua konten sekaligus (dengan progress)
 RowiDataManager.shared.loadTarjamahContent(
     forRowi: selectedRowi,
     onProgress: { current, total in
         print("Loading \(current)/\(total)...")
     },
     onComplete: { results in
         // Tampilkan semua hasil
     }
 )

 // 4. Testing
 Task {
     await TarjamahMenBManager.shared.testTarjamah(forRowi: someRowi)
 }

 */
