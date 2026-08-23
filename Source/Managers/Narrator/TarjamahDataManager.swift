//
//  TarjamahDataManager.swift
//  maktab
//
//  Created by MacBook on 12/12/25.
//
//  Refactored: Unified Manager + Pause/Resume + Streaming Results

import Foundation
import SQLite3

actor TarjamahDatabaseActor {
    private let conn: SQLiteConnection

    init(dbPath: String) throws {
        self.conn = try SQLiteConnection(dbPath: dbPath)
        let ftsPath = dbPath.replacingOccurrences(of: "special.sqlite", with: "special_fts.sqlite")
        if FileManager.default.fileExists(atPath: ftsPath) {
            try? self.conn.attachDatabase(path: ftsPath, as: "fts_db")
        }
    }

    func queryRows(sql: String, params: [SQLValue]) throws -> [[String: Any?]] {
        return try conn.queryRows(sql: sql, params: params)
    }

    func queryMapped<T>(sql: String, params: [SQLValue], mapper: (OpaquePointer) -> T) throws -> [T] {
        return try conn.queryMapped(sql: sql, params: params, mapper: mapper)
    }

    func queryTarjamah(sql: String, params: [SQLValue], isIsoName: Bool) throws -> [TarjamahMen] {
        return try conn.queryTarjamah(sql: sql, params: params, isIsoName: isIsoName)
    }
}

class TarjamahGlobalManager {
    static let shared = TarjamahGlobalManager()

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
        setupConnection()
    }

    func setupConnection() {
        guard let specialPath = AppConfig.specialDatabasePath else { return }

        // Inisialisasi actor
        dbActor = try? TarjamahDatabaseActor(dbPath: specialPath)
    }

    #if os(macOS)
    func optimizeSpecialDatabaseIfNeeded() {
        guard let mainDbPath = AppConfig.specialDatabasePath else { return }
        let ftsPath = mainDbPath.replacingOccurrences(
            of: "special.sqlite",
            with: "special_fts.sqlite"
        )

        let fm = FileManager.default
        var needsOptimization = false

        // 0. Ensure index exists to prevent extremely slow FTS JOIN queries
        if let db = try? SQLiteConnection(dbPath: mainDbPath) {
            try? db.execute(query: "CREATE INDEX IF NOT EXISTS idx_men_u_uid ON men_u(uId);")
            try? db.execute(query: "CREATE INDEX IF NOT EXISTS idx_men_b_id ON men_b(Id);")
        }

        if !fm.fileExists(atPath: ftsPath) {
            needsOptimization = true
        } else if let attr = try? fm.attributesOfItem(atPath: ftsPath),
                  let size = attr[.size] as? Int64, size == 0 {
            needsOptimization = true
        }

        guard needsOptimization else { return }

        print("Memulai optimasi special.sqlite (FTS & ZSTD Compression)...")

        try? fm.removeItem(atPath: ftsPath)

        var db: OpaquePointer?
        guard sqlite3_open(mainDbPath, &db) == SQLITE_OK else {
            print("❌ Gagal buka db")
            return
        }
        defer { sqlite3_close(db) }

        // 1. COMPRESS men_u
        sqlite3_exec(db, "BEGIN", nil, nil, nil)

        let renameResult = sqlite3_exec(
            db, "ALTER TABLE men_u RENAME TO old_men_u",
            nil, nil, nil
        )
        if renameResult == SQLITE_OK {
            let createSql = """
                CREATE TABLE men_u (
                    Name BLOB,
                    IsoName BLOB,
                    Bk INTEGER,
                    Id INTEGER,
                    uId INTEGER
                )
            """
            sqlite3_exec(db, createSql, nil, nil, nil)

            var readStmt: OpaquePointer?
            sqlite3_prepare_v2(
                db,
                "SELECT Name, IsoName, Bk, Id, uId FROM old_men_u",
                -1, &readStmt, nil
            )

            var insertStmt: OpaquePointer?
            sqlite3_prepare_v2(
                db,
                "INSERT INTO men_u (Name, IsoName, Bk, Id, uId) VALUES (?, ?, ?, ?, ?)",
                -1, &insertStmt, nil
            )

            let SQLITE_TRANSIENT = unsafeBitCast(
                OpaquePointer(bitPattern: -1),
                to: sqlite3_destructor_type.self
            )

            while sqlite3_step(readStmt) == SQLITE_ROW {
                // Name
                if let namePtr = sqlite3_column_text(readStmt, 0) {
                    let bytes = sqlite3_column_bytes(readStmt, 0)
                    let buffer = UnsafeBufferPointer(start: namePtr, count: Int(bytes))
                    let nameStr = String(decoding: buffer, as: UTF8.self)
                    if let compressed = ReusableFunc.compressData(nameStr, level: 10) {
                        _ = compressed.withUnsafeBytes { ptr in
                            sqlite3_bind_blob(
                                insertStmt, 1,
                                ptr.baseAddress,
                                Int32(compressed.count),
                                SQLITE_TRANSIENT
                            )
                        }
                    } else {
                        sqlite3_bind_null(insertStmt, 1)
                    }
                } else {
                    sqlite3_bind_null(insertStmt, 1)
                }

                // IsoName
                if let isoPtr = sqlite3_column_text(readStmt, 1) {
                    let bytes = sqlite3_column_bytes(readStmt, 1)
                    let buffer = UnsafeBufferPointer(start: isoPtr, count: Int(bytes))
                    let isoStr = String(decoding: buffer, as: UTF8.self)
                    if let compressed = ReusableFunc.compressData(isoStr, level: 10) {
                        _ = compressed.withUnsafeBytes { ptr in
                            sqlite3_bind_blob(
                                insertStmt, 2,
                                ptr.baseAddress,
                                Int32(compressed.count),
                                SQLITE_TRANSIENT
                            )
                        }
                    } else {
                        sqlite3_bind_null(insertStmt, 2)
                    }
                } else {
                    sqlite3_bind_null(insertStmt, 2)
                }

                sqlite3_bind_int(insertStmt, 3, sqlite3_column_int(readStmt, 2))
                sqlite3_bind_int(insertStmt, 4, sqlite3_column_int(readStmt, 3))
                sqlite3_bind_int(insertStmt, 5, sqlite3_column_int(readStmt, 4))

                sqlite3_step(insertStmt)
                sqlite3_reset(insertStmt)
            }
            sqlite3_finalize(readStmt)
            sqlite3_finalize(insertStmt)

            sqlite3_exec(db, "DROP TABLE old_men_u", nil, nil, nil)
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
            print("men_u selesai dikompres")
        } else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            print("Tabel men_u mungkin sudah dikompres atau gagal rename.")
        }

        // 2. CREATE FTS DB
        try? db?.safeAttachDatabase(path: ftsPath, schema: "fts_db")

        let createFtsSql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_db.men_u_fts
        USING fts5(
            IsoName_clean,
            content='',
            tokenize='unicode61'
        )
        """
        sqlite3_exec(db, createFtsSql, nil, nil, nil)

        let createFtsBSql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_db.men_b_fts
        USING fts5(
            Name_clean,
            content='',
            tokenize='unicode61'
        )
        """
        sqlite3_exec(db, createFtsBSql, nil, nil, nil)

        sqlite3_exec(db, "BEGIN", nil, nil, nil)

        var readFtsStmt: OpaquePointer?
        sqlite3_prepare_v2(
            db, "SELECT uId, IsoName FROM men_u WHERE IsoName IS NOT NULL",
            -1, &readFtsStmt, nil
        )

        var insertFtsStmt: OpaquePointer?
        sqlite3_prepare_v2(
            db, "INSERT INTO fts_db.men_u_fts(rowid, IsoName_clean) VALUES (?, ?)",
            -1, &insertFtsStmt, nil
        )

        let SQLITE_TRANSIENT = unsafeBitCast(
            OpaquePointer(bitPattern: -1),
            to: sqlite3_destructor_type.self
        )

        while sqlite3_step(readFtsStmt) == SQLITE_ROW {
            let uid = sqlite3_column_int(readFtsStmt, 0)
            var isoNameClean = ""

            if sqlite3_column_type(readFtsStmt, 1) == SQLITE_BLOB {
                if let blob = sqlite3_column_blob(readFtsStmt, 1) {
                    let bytes = sqlite3_column_bytes(readFtsStmt, 1)
                    let buffer = UnsafeRawBufferPointer(start: blob, count: Int(bytes))
                    let decompressed = ReusableFunc.decompressData(from: buffer)
                    isoNameClean = decompressed.stemArabicLight10()
                }
            } else if sqlite3_column_type(readFtsStmt, 1) == SQLITE_TEXT {
                if let text = sqlite3_column_text(readFtsStmt, 1) {
                    let bytes = sqlite3_column_bytes(readFtsStmt, 1)
                    let buffer = UnsafeBufferPointer(start: text, count: Int(bytes))
                    isoNameClean = String(decoding: buffer, as: UTF8.self).stemArabicLight10()
                }
            }

            if !isoNameClean.isEmpty {
                sqlite3_bind_int(insertFtsStmt, 1, uid)
                _ = isoNameClean.withCString { ptr in
                    sqlite3_bind_text(insertFtsStmt, 2, ptr, -1, SQLITE_TRANSIENT)
                }
                sqlite3_step(insertFtsStmt)
                sqlite3_reset(insertFtsStmt)
            }
        }

        sqlite3_finalize(readFtsStmt)
        sqlite3_finalize(insertFtsStmt)

        // MARK: Populate men_b_fts

        var readFtsBStmt: OpaquePointer?
        sqlite3_prepare_v2(
            db, "SELECT Id, Name FROM men_b WHERE Name IS NOT NULL AND Name != ''",
            -1, &readFtsBStmt, nil
        )

        var insertFtsBStmt: OpaquePointer?
        sqlite3_prepare_v2(
            db, "INSERT INTO fts_db.men_b_fts(rowid, Name_clean) VALUES (?, ?)",
            -1, &insertFtsBStmt, nil)

        while sqlite3_step(readFtsBStmt) == SQLITE_ROW {
            let uid = sqlite3_column_int(readFtsBStmt, 0)
            var nameClean = ""

            if let text = sqlite3_column_text(readFtsBStmt, 1) {
                let bytes = sqlite3_column_bytes(readFtsBStmt, 1)
                let buffer = UnsafeBufferPointer(start: text, count: Int(bytes))
                nameClean = String(decoding: buffer, as: UTF8.self).stemArabicLight10()
            }

            if !nameClean.isEmpty {
                sqlite3_bind_int(insertFtsBStmt, 1, uid)
                _ = nameClean.withCString { ptr in
                    sqlite3_bind_text(insertFtsBStmt, 2, ptr, -1, SQLITE_TRANSIENT)
                }
                sqlite3_step(insertFtsBStmt)
                sqlite3_reset(insertFtsBStmt)
            }
        }

        sqlite3_finalize(readFtsBStmt)
        sqlite3_finalize(insertFtsBStmt)

        sqlite3_exec(db, "COMMIT", nil, nil, nil)

        // 3. VACUUM
        print("VACUUM...")
        sqlite3_exec(db, "VACUUM main", nil, nil, nil)
        sqlite3_exec(db, "VACUUM fts_db", nil, nil, nil)

        sqlite3_exec(db, "DETACH DATABASE fts_db", nil, nil, nil)
        print("DONE: FTS created and optimized")

        // RE-INIT dbActor so it attaches the newly created fts_db
        self.dbActor = try? TarjamahDatabaseActor(dbPath: mainDbPath)
    }
    #endif

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
        defer { onComplete() }

        let sanitizedQuery = query
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .stemArabicLight10()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedQuery.isEmpty else { return }

        // 1. Cek Cache dulu
        if let cached = searchStringCache[sanitizedQuery] {
            print("📦 Cache Hit for query: \(sanitizedQuery)")
            await onBatchResult(cached) // Kirim semua langsung
            return
        }

        guard let conn = dbActor else {
            print("❌ Connection error")
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
            if stopFlag() || Task.isCancelled { return }
            await pauseController?.waitIfPaused()

            let ftsQuery = "\"\(sanitizedQuery)\" *"   // phrase + prefix

            let sqlB = """
            SELECT main.Name, '', main.Bk, main.Id, main.ManId, main.bId
            FROM men_b AS main
            JOIN men_b_fts AS fts ON main.Id = fts.rowid
            WHERE fts.Name_clean MATCH ?
            ORDER BY main.Bk, main.Id
            LIMIT ?
            """

            let rowsB = try await conn.queryMapped(
                sql: sqlB,
                params: [.text(ftsQuery), .int(limit)]
            ) { stmt -> TarjamahMen in
                var nameStr = ""
                let type = sqlite3_column_type(stmt, 0)

                if type == SQLITE_TEXT {
                    if let txt = sqlite3_column_text(stmt, 0) {
                        let bytes = sqlite3_column_bytes(stmt, 0)
                        let buffer = UnsafeBufferPointer(start: txt, count: Int(bytes))
                        nameStr = String(decoding: buffer, as: UTF8.self)
                    }
                } else if type == SQLITE_BLOB {
                    if let blobPointer = sqlite3_column_blob(stmt, 0) {
                        let blobSize = Int(sqlite3_column_bytes(stmt, 0))
                        let buffer = UnsafeRawBufferPointer(start: blobPointer, count: blobSize)
                        nameStr = ReusableFunc.decompressData(from: buffer)
                    }
                }

                let bk = Int(sqlite3_column_int64(stmt, 2))
                let id = Int(sqlite3_column_int64(stmt, 3))

                return TarjamahMen(name: nameStr, bk: bk, id: id)
            }

            for (index, mutT) in rowsB.enumerated() {
                if index % 10 == 0 {
                    if stopFlag() || Task.isCancelled { return }
                    await pauseController?.waitIfPaused()
                }

                var t = mutT

                if let bookData = LibraryDataManager.shared.getBook([t.bk]).first {
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

            let ftsQuery = "\"\(sanitizedQuery)\" *" // Phrase + Prefix

            let sqlU = """
            SELECT main.Name, main.IsoName, main.Bk, main.Id, main.uId
            FROM men_u AS main
            JOIN men_u_fts AS fts ON main.uId = fts.rowid
            WHERE fts.IsoName_clean MATCH ?
            ORDER BY main.Bk, main.Id
            LIMIT ?
            """

            let tarjamahsU = try await conn.queryTarjamah(sql: sqlU, params: [.text(ftsQuery), .int(limit)], isIsoName: true)

            for (index, t) in tarjamahsU.enumerated() {
                var tVar = t
                if index % 10 == 0 {
                    if stopFlag() || Task.isCancelled { return }
                    await pauseController?.waitIfPaused()
                }

                if let bookData = LibraryDataManager.shared.getBook([tVar.bk]).first {
                    tVar.bookTitle = bookData.book
                    tVar.archive = bookData.archive

                    allResults.append(tVar)
                    batchBuffer.append(tVar)

                    if batchBuffer.count >= 5 {
                        await flushBuffer()
                    }
                } else {
                    continue
                }
            }
        } catch {
            print("❌ Error men_u:", error)
        }

        await flushBuffer() // Sisa buffer akhir
        searchStringCache[sanitizedQuery] = allResults
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
            SELECT Name, '', Bk, Id, ManId
            FROM men_b
            WHERE Manid = ?
            ORDER BY Bk, Id
            """

            let tarjamahs = try await conn.queryTarjamah(sql: sql, params: [.int(rowaId)], isIsoName: false)

            for t in tarjamahs {
                var tVar = t
                if let bookData = LibraryDataManager.shared.getBook([tVar.bk]).first {
                    tVar.bookTitle = bookData.book
                    tVar.archive = bookData.archive
                }
                results.append(tVar)
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
        query: String? = nil,
        pauseController: PauseController?,
        stopFlag: @escaping () -> Bool,
        onProgress: @escaping (Int, Int) -> Void
    ) async -> [TarjamahResult] {

        guard !tarjamahList.isEmpty else { return [] }

        var batchBuffer: [TarjamahResult] = []

        let targetQuery = query?.trimmingCharacters(in: .whitespaces)

        if let targetQuery {
            var searchKeywords = FtsQueryParser.extractKeywords(query: targetQuery, mode: .phrase)
            if searchKeywords.isEmpty {
                searchKeywords = [targetQuery.normalizeArabic()]
            }
        }

        for (index, tarjamah) in tarjamahList.enumerated() {
            // Cek Stop
            if stopFlag() || Task.isCancelled {
                print("🛑 Loading stopped at index \(index)")
                break
            }

            // Cek Pause
            await pauseController?.waitIfPaused()

            do {
                let effectiveQuery = targetQuery == nil ? tarjamah.name : targetQuery!
                guard let result = try await loadTarjamahContent(tarjamah, query: effectiveQuery) else {
                    continue
                }
                batchBuffer.append(result)

                await MainActor.run {
                    onProgress(index + 1, tarjamahList.count)
                }

            } catch {
                print("⚠️ Error loading '\(tarjamah.name)': \(error.localizedDescription)")
            }
        }

        return batchBuffer
    }

    /// Load konten single (Atomic operation)
    func loadTarjamahContent(_ tarjamah: TarjamahMen, query: String) async throws -> TarjamahResult? {
        let book: BooksData? = await Task.detached {
            LibraryDataManager.shared.getBook([tarjamah.bk]).first
        }.value
        var archiveId = tarjamah.archive
        if archiveId == nil {
            archiveId = book?.archive
        }
        guard let archive = archiveId else {
            throw NSError(domain: "Tarjamah", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Archive ID"])
        }

        guard let pool = try getOrCreateConnectionPool(forArchive: archive) else { return nil }
        let tableName = "b\(tarjamah.bk)"

        let sql = "SELECT nass FROM \(tableName) WHERE id = ? LIMIT 1"

        let nass = try await pool.read(at: 0) { conn in
            try conn.querySingleNass(sql: sql, params: [.int(tarjamah.id)])
        }

        guard let nass = nass else {
            throw NSError(domain: "Tarjamah", code: -2, userInfo: [NSLocalizedDescriptionKey: "Not found"])
        }

        let isMultilingual = book?.isMultiLanguage ?? false
        let isImported = book?.isImported ?? false

        let strippedNash = isImported ? nass.stripSpanTags() : nass
        let normalizedNash = strippedNash.convertToArabicDigits(isMultilingual: isMultilingual)

        let snippet = normalizedNash
            .snippetAround(keywords: [query], contextLength: 60)
        let highlightedSnippet = snippet.highlightedAttributedText(keywords: [query])

        return TarjamahResult(tarjamah: tarjamah, content: snippet, attributedText: highlightedSnippet)
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
                guard let result = try await loadTarjamahContent(tarjamah, query: tarjamah.name) else { continue }
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

        guard let dbPath = AppConfig.archiveDatabasePath(archiveId: archive) else {
            return nil
        }

        if let pool = connectionPools[archive] { return pool }

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
