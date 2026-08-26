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
        conn = try SQLiteConnection(dbPath: dbPath)
        let ftsPath = dbPath.replacing("special.sqlite", with: "special_fts.sqlite")
        if FileManager.default.fileExists(atPath: ftsPath) {
            try? conn.attachDatabase(path: ftsPath, as: "fts_db")
        }
    }

    func queryRows(sql: String, params: [SQLValue]) throws -> [[String: Any?]] {
        try conn.queryRows(sql: sql, params: params)
    }

    func queryMapped<T>(sql: String, params: [SQLValue], mapper: (OpaquePointer) -> T) throws -> [T] {
        try conn.queryMapped(sql: sql, params: params, mapper: mapper)
    }

    func queryTarjamah(sql: String, params: [SQLValue], isIsoName: Bool) throws -> [TarjamahMen] {
        try conn.queryTarjamah(sql: sql, params: params, isIsoName: isIsoName)
    }
}

class TarjamahGlobalManager {
    static let shared = TarjamahGlobalManager()

    // MARK: - Caching

    // Cache koneksi per archive (1.sqlite, 2.sqlite...)
    private var connectionPools: [Int: SQLiteConnectionPool] = [:]
    private let poolLock = NSLock()

    /// Cache hasil pencarian Rowa (Query by ID) - Sangat efektif di-cache
    private var rowaCache: [Int: [TarjamahMen]] = [:]

    /// Cache hasil pencarian text (Query String) - Optional, hati-hati memori
    private var searchStringCache: [String: [TarjamahMen]] = [:]

    /// Ganti dbConnect & dbLock dengan Actor
    private var dbActor: TarjamahDatabaseActor?

    /// SQLITE_TRANSIENT unsafeBitCast
    private let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

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
        let ftsPath = mainDbPath.replacing("special.sqlite", with: "special_fts.sqlite")

        ensureSpecialIndices(mainDbPath: mainDbPath)
        guard shouldOptimizeSpecialDb(ftsPath: ftsPath) else { return }

        print("Memulai optimasi special.sqlite (FTS & ZSTD Compression)...")
        try? FileManager.default.removeItem(atPath: ftsPath)

        var db: OpaquePointer?
        guard sqlite3_open(mainDbPath, &db) == SQLITE_OK else {
            print("❌ Gagal buka db")
            return
        }
        defer { sqlite3_close(db) }

        compressMenUTable(db: db)
        createFtsTables(db: db, ftsPath: ftsPath)
        populateMenUFts(db: db)
        populateMenBFts(db: db)
        vacuumAndDetachFts(db: db)

        dbActor = try? TarjamahDatabaseActor(dbPath: mainDbPath)
    }

    private func ensureSpecialIndices(mainDbPath: String) {
        if let db = try? SQLiteConnection(dbPath: mainDbPath) {
            try? db.execute(query: "CREATE INDEX IF NOT EXISTS idx_men_u_uid ON men_u(uId);")
            try? db.execute(query: "CREATE INDEX IF NOT EXISTS idx_men_b_id ON men_b(Id);")
        }
    }

    private func shouldOptimizeSpecialDb(ftsPath: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: ftsPath) else { return true }
        if let attr = try? fm.attributesOfItem(atPath: ftsPath),
           let size = attr[.size] as? Int64, size == 0
        {
            return true
        }
        return false
    }

    private func readColumnString(stmt: OpaquePointer?, column: Int32) -> String? {
        stmt?.columnString(column)
    }

    private func bindCompressedBlob(stmt: OpaquePointer?, index: Int32, text: String?) {
        guard let text, let compressed = ReusableFunc.compressData(text, level: 10) else {
            sqlite3_bind_null(stmt, index)
            return
        }
        _ = compressed.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, index, ptr.baseAddress, Int32(compressed.count), SQLITE_TRANSIENT)
        }
    }

    private func compressMenUTable(db: OpaquePointer?) {
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        guard sqlite3_exec(db, "ALTER TABLE men_u RENAME TO old_men_u", nil, nil, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            print("Tabel men_u mungkin sudah dikompres atau gagal rename.")
            return
        }

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
        guard sqlite3_prepare_v2(db, "SELECT Name, IsoName, Bk, Id, uId FROM old_men_u", -1, &readStmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            print("Gagal prepare readStmt old_men_u")
            return
        }
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO men_u (Name, IsoName, Bk, Id, uId) VALUES (?, ?, ?, ?, ?)", -1, &insertStmt, nil) == SQLITE_OK else {
            finalizeAndRollback(db: db, readStmt: readStmt)
            print("Gagal prepare insertStmt men_u")
            return
        }

        while sqlite3_step(readStmt) == SQLITE_ROW {
            bindCompressedBlob(stmt: insertStmt, index: 1, text: readColumnString(stmt: readStmt, column: 0))
            bindCompressedBlob(stmt: insertStmt, index: 2, text: readColumnString(stmt: readStmt, column: 1))
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
    }

    private func createFtsTables(db: OpaquePointer?, ftsPath: String) {
        try? db?.safeAttachDatabase(path: ftsPath, schema: "fts_db")
        let createFtsSql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_db.men_u_fts
        USING fts5(IsoName_clean, content='', tokenize='unicode61')
        """
        sqlite3_exec(db, createFtsSql, nil, nil, nil)

        let createFtsBSql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_db.men_b_fts
        USING fts5(Name_clean, content='', tokenize='unicode61')
        """
        sqlite3_exec(db, createFtsBSql, nil, nil, nil)
    }

    private func extractCleanString(stmt: OpaquePointer?, column: Int32) -> String {
        stmt?.columnTextOrDecompressedBlob(column).stemArabicLight10() ?? ""
    }

    private func populateMenUFts(db: OpaquePointer?) {
        populateMenFts(
            db: db,
            readQuery: "SELECT uId, IsoName FROM men_u WHERE IsoName IS NOT NULL",
            insertQuery: "INSERT INTO fts_db.men_u_fts(rowid, IsoName_clean) VALUES (?, ?)",
        )
    }

    private func populateMenBFts(db: OpaquePointer?) {
        populateMenFts(
            db: db,
            readQuery: "SELECT Id, Name FROM men_b WHERE Name IS NOT NULL AND Name != ''",
            insertQuery: "INSERT INTO fts_db.men_b_fts(rowid, Name_clean) VALUES (?, ?)"
        )
    }

    private func populateMenFts(db: OpaquePointer?, readQuery: String, insertQuery: String) {
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        var readStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, readQuery, -1, &readStmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertQuery, -1, &insertStmt, nil) == SQLITE_OK else {
            finalizeAndRollback(db: db, readStmt: readStmt)
            return
        }

        stemTextAndBind(readStmt: readStmt, insertStmt: insertStmt)
        finalizeAndCommit(db: db, readStmt: readStmt, insertStmt: insertStmt)
    }

    @inline(__always)
    private func stemTextAndBind(readStmt: OpaquePointer?, insertStmt: OpaquePointer?) {
        while sqlite3_step(readStmt) == SQLITE_ROW {
            let uid = sqlite3_column_int(readStmt, 0)
            let clean = readStmt?.columnTextOrDecompressedBlob(1).stemArabicLight10() ?? ""
            if !clean.isEmpty {
                sqlite3_bind_int(insertStmt, 1, uid)
                _ = clean.withCString { ptr in
                    sqlite3_bind_text(insertStmt, 2, ptr, -1, SQLITE_TRANSIENT)
                }
                sqlite3_step(insertStmt)
                sqlite3_reset(insertStmt)
            }
        }
    }

    private func finalizeAndCommit(
        db: OpaquePointer?,
        readStmt: OpaquePointer?,
        insertStmt: OpaquePointer?
    ) {
        sqlite3_finalize(readStmt)
        sqlite3_finalize(insertStmt)
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private func vacuumAndDetachFts(db: OpaquePointer?) {
        print("VACUUM...")
        sqlite3_exec(db, "VACUUM main", nil, nil, nil)
        sqlite3_exec(db, "VACUUM fts_db", nil, nil, nil)
        sqlite3_exec(db, "DETACH DATABASE fts_db", nil, nil, nil)
        print("DONE: FTS created and optimized")
    }
    #endif

    // MARK: - 1. Global Search (String) with Pause & Streaming

    /// Pencarian text global (men_b LIKE & men_u FTS) dengan fitur Pause & Streaming
    func searchTarjamah(
        query: String,
        limit: Int = 50,
        pauseController: PauseController?,
        stopFlag: @escaping () -> Bool,
        onBatchResult: @escaping @Sendable ([TarjamahMen]) async -> Void,
        onComplete: @escaping () -> Void
    ) async {
        defer { onComplete() }

        guard let sanitizedQuery = sanitize(query: query) else { return }

        if let cached = searchStringCache[sanitizedQuery] {
            print("📦 Cache Hit for query: \(sanitizedQuery)")
            await onBatchResult(cached)
            return
        }

        guard dbActor != nil else {
            print("❌ Connection error")
            return
        }

        let results = await executeSearch(
            sanitizedQuery: sanitizedQuery,
            limit: limit,
            pauseController: pauseController,
            stopFlag: stopFlag,
            onBatchResult: onBatchResult
        )
        searchStringCache[sanitizedQuery] = results
    }

    private func sanitize(query: String) -> String? {
        let sanitized = query
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .stemArabicLight10()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }

    private func executeSearch(
        sanitizedQuery: String,
        limit: Int,
        pauseController: PauseController?,
        stopFlag: @escaping () -> Bool,
        onBatchResult: @escaping @Sendable ([TarjamahMen]) async -> Void
    ) async -> [TarjamahMen] {
        var allResults: [TarjamahMen] = []
        let ftsQuery = "\"\(sanitizedQuery)\" *"

        allResults += await searchMenBFts(
            ftsQuery: ftsQuery,
            limit: limit,
            pauseController: pauseController,
            stopFlag: stopFlag,
            onBatchResult: onBatchResult
        )

        guard !stopFlag(), !Task.isCancelled else {
            return allResults
        }

        allResults += await searchMenUFts(
            ftsQuery: ftsQuery,
            limit: limit,
            pauseController: pauseController,
            stopFlag: stopFlag,
            onBatchResult: onBatchResult
        )

        return allResults
    }

    private func executeFtsSearch(
        pauseController: PauseController?,
        stopFlag: @escaping () -> Bool,
        onBatchResult: @escaping @Sendable ([TarjamahMen]) async -> Void,
        fetch: (TarjamahDatabaseActor) async throws -> [TarjamahMen]
    ) async -> [TarjamahMen] {
        guard let conn = dbActor, !stopFlag(), !Task.isCancelled else { return [] }
        await pauseController?.waitIfPaused()

        do {
            let items = try await fetch(conn)
            return await streamProcessedResults(
                items,
                pauseController: pauseController,
                stopFlag: stopFlag,
                onBatchResult: onBatchResult
            )
        } catch {
            print("❌ Error Tarjamah FTS:", error)
            return []
        }
    }

    private func searchMenBFts(
        ftsQuery: String,
        limit: Int,
        pauseController: PauseController?,
        stopFlag: @escaping () -> Bool,
        onBatchResult: @escaping @Sendable ([TarjamahMen]) async -> Void
    ) async -> [TarjamahMen] {
        let sqlB = """
        SELECT main.Name, '', main.Bk, main.Id, main.ManId, main.bId
        FROM men_b AS main
        JOIN men_b_fts AS fts ON main.Id = fts.rowid
        WHERE fts.Name_clean MATCH ?
        ORDER BY main.Bk, main.Id
        LIMIT ?
        """

        return await executeFtsSearch(
            pauseController: pauseController,
            stopFlag: stopFlag,
            onBatchResult: onBatchResult
        ) { [weak self] conn in
            try await conn.queryMapped(
                sql: sqlB,
                params: [.text(ftsQuery), .int(limit)]
            ) { stmt -> TarjamahMen in
                let nameStr = self?.extractTarjamahName(from: stmt) ?? ""
                let bk = Int(sqlite3_column_int64(stmt, 2))
                let id = Int(sqlite3_column_int64(stmt, 3))
                return TarjamahMen(name: nameStr, bk: bk, id: id)
            }
        }
    }

    private func searchMenUFts(
        ftsQuery: String,
        limit: Int,
        pauseController: PauseController?,
        stopFlag: @escaping () -> Bool,
        onBatchResult: @escaping @Sendable ([TarjamahMen]) async -> Void
    ) async -> [TarjamahMen] {
        let sqlU = """
        SELECT main.Name, main.IsoName, main.Bk, main.Id, main.uId
        FROM men_u AS main
        JOIN men_u_fts AS fts ON main.uId = fts.rowid
        WHERE fts.IsoName_clean MATCH ?
        ORDER BY main.Bk, main.Id
        LIMIT ?
        """

        return await executeFtsSearch(
            pauseController: pauseController,
            stopFlag: stopFlag,
            onBatchResult: onBatchResult
        ) { conn in
            try await conn.queryTarjamah(
                sql: sqlU,
                params: [.text(ftsQuery), .int(limit)],
                isIsoName: true
            )
        }
    }

    private func extractTarjamahName(from stmt: OpaquePointer) -> String {
        stmt.columnTextOrDecompressedBlob(0)
    }

    private func streamProcessedResults(
        _ items: [TarjamahMen],
        pauseController: PauseController?,
        stopFlag: @escaping () -> Bool,
        onBatchResult: @escaping @Sendable ([TarjamahMen]) async -> Void
    ) async -> [TarjamahMen] {
        var results: [TarjamahMen] = []
        var batchBuffer: [TarjamahMen] = []

        for (index, mutT) in items.enumerated() {
            if index % 10 == 0 {
                if stopFlag() || Task.isCancelled {
                    break
                }
                await pauseController?.waitIfPaused()
            }

            var item = mutT
            if let bookData = LibraryDataManager.shared.getBook([item.bk]).first {
                item.bookTitle = bookData.book
                item.archive = bookData.archive
            }

            results.append(item)
            batchBuffer.append(item)

            if batchBuffer.count >= 5 {
                let chunk = batchBuffer
                batchBuffer.removeAll()
                await onBatchResult(chunk)
            }
        }

        if !batchBuffer.isEmpty {
            let chunk = batchBuffer
            batchBuffer.removeAll()
            await onBatchResult(chunk)
        }

        return results
    }

    // MARK: - 2. Rowa Lookup (Search by ID) - Merged from MenBManager

    /// Load daftar tarjamah berdasarkan ID Rawi (Rowa)
    func loadTarjamahList(forRowa rowaId: Int) async -> [TarjamahMen] {
        if let cached = rowaCache[rowaId] {
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

        for (index, tarjamah) in tarjamahList.enumerated() {
            if stopFlag() || Task.isCancelled {
                print("🛑 Loading stopped at index \(index)")
                break
            }

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

        guard let nass else {
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

        if let pool = connectionPools[archive] {
            return pool
        }

        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw NSError(domain: "Tarjamah", code: -5, userInfo: [NSLocalizedDescriptionKey: "File missing: \(dbPath)"])
        }

        var connections: [DBConnectionType] = []
        for _ in 0 ..< 2 {
            if let conn = try? SQLiteConnection(dbPath: dbPath) {
                connections.append(conn)
            }
        }

        let pool = SQLiteConnectionPool(conns: connections)
        connectionPools[archive] = pool
        return pool
    }

    private func finalizeAndRollback(db: OpaquePointer?, readStmt: OpaquePointer?) {
        sqlite3_finalize(readStmt)
        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
    }
}
