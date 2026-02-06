//
//  SearchEngine.swift
//  maktab
//
//  Modified: Parallel search within table using 4 connections
//

import Foundation
import SQLite3

struct ArchiveInfo {
    var tables: [String]
    var books: [BooksData]
}

// ----------------------------------------
// MARK: - Abstraction: DB connection
// ----------------------------------------
protocol DBConnectionType {
    func queryRows(sql: String, params: [SQLValue]) throws -> [[String: Any?]]
}

enum SQLValue {
    case text(String)
    case int(Int)
    case null
}

// ----------------------------------------
// MARK: - PauseController (actor)
// ----------------------------------------
class PauseController {
    private var isPaused = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func pause() {
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        let conts = continuations
        continuations.removeAll()
        for cont in conts { cont.resume() }
    }

    func stopAndResumeAll() {
        resume()
    }

    func waitIfPaused() async {
        if !isPaused { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            continuations.append(continuation)
        }
    }

    func currentlyPaused() -> Bool {
        return isPaused
    }
}

// ----------------------------------------
// MARK: - Connection Pool per file (actor)
// ----------------------------------------
class SQLiteConnectionPool {
    private var connections: [DBConnectionType]

    init(conns: [DBConnectionType]) {
        self.connections = conns
    }

    var connectionCount: Int {
        return connections.count
    }

    /// Ambil koneksi berdasarkan index
    func getConnection(at index: Int) -> DBConnectionType {
        return connections[index % connections.count]
    }

    /// Menjalankan read-operation pada koneksi tertentu
    func read<T>(at index: Int, _ body: @escaping (DBConnectionType) throws -> T) async throws -> T {
        return try await Task.detached(priority: .userInitiated) {
            let conn = self.getConnection(at: index)
            return try body(conn)
        }.value
    }
}

// ----------------------------------------
// MARK: - Worker per file
// ----------------------------------------
class SearchWorker {
    let archiveId: String
    let tables: [String]
    let pool: SQLiteConnectionPool
    let batchSize: Int

    init(archiveId: String, tables: [String], pool: SQLiteConnectionPool, batchSize: Int = 200) {
        self.archiveId = archiveId
        self.tables = tables
        self.pool = pool
        self.batchSize = batchSize
    }

    func search(
        ftsQuery: String,
        allowedTables: Set<String>?,
        start: @escaping (Int) -> Void,
        progress: @escaping (Int) -> Void,
        onRowProgress: @escaping (String, Int, Int) -> Void,
        onResult: @escaping (String, BookContent) -> Void,
        onTableComplete: @escaping () -> Void,
        pauseController: PauseController,
        stopFlag: @escaping @Sendable () -> Bool,
        onComplete: @escaping () -> Void
    ) async {
        var totalFetched = 0

        let tablesToProcess = allowedTables != nil
            ? tables.filter { allowedTables!.contains($0) }
            : tables

        print("🔍 Archive \(archiveId): Mulai mencari di \(tablesToProcess.count) tables")
        start(tablesToProcess.count)

        for (index, tableName) in tablesToProcess.enumerated() {
            // ✅ CEK STOP sebelum mulai table
            if stopFlag() {
                print("ℹ️ Archive \(archiveId): stop sebelum table \(index+1)/\(tablesToProcess.count)")
                return
            }

            await pauseController.waitIfPaused()

            // ✅ CEK STOP setelah resume
            if stopFlag() {
                print("ℹ️ Archive \(archiveId): stop setelah resume sebelum table \(index+1)")
                return
            }

            print("  📄 [\(index+1)/\(tablesToProcess.count)] \(tableName)")

            // ✅ KUNCI: searchTableParallel sekarang bisa stop instan
            let tableResultCount = await searchTableParallel(
                tableName: tableName, 
                ftsQuery: ftsQuery,
                onResult: onResult,
                pauseController: pauseController,
                stopFlag: stopFlag,
                progress: progress, 
                onRowProgress: { current, total in
                    onRowProgress(tableName, current, total)
                }
            )

            // ✅ CEK STOP segera setelah searchTableParallel return
            if stopFlag() {
                print("ℹ️ Archive \(archiveId): stop setelah table \(tableName) (partial: \(tableResultCount) hasil)")
                return  // <-- KELUAR LANGSUNG!
            }

            if tableResultCount > 0 {
                print("    ✓ \(tableName): \(tableResultCount) hasil")
                totalFetched += tableResultCount
            }

            onTableComplete()
        }

        onComplete()
        print("✅ Archive \(archiveId): selesai — total \(totalFetched) hasil")
    }

    /// ✅ PERBAIKAN UTAMA: Cancel TaskGroup dengan aggressive checking
    private func searchTableParallel(
        tableName: String,
        ftsQuery: String,
        onResult: @escaping (String, BookContent) -> Void,
        pauseController: PauseController,
        stopFlag: @escaping @Sendable () -> Bool,
        progress: @escaping (Int) -> Void,
        onRowProgress: @escaping (Int, Int) -> Void
    ) async -> Int {
        // Count total menggunakan FTS
        let totalCount: Int
        do {
            totalCount = try await pool.read(at: 0) { conn in
                let countSQL = """
                    SELECT COUNT(*) as total
                    FROM \(tableName)_fts
                    WHERE nass_clean MATCH ?
                """
                let rows = try conn.queryRows(sql: countSQL, params: [.text(ftsQuery)])
                guard let firstRow = rows.first, let total = firstRow["total"] as? Int else {
                    return 0
                }
                return total
            }
        } catch {
            print("⚠️ Error counting table \(tableName): \(error)")
            return 0
        }

        if totalCount == 0 { return 0 }

        // ✅ Report total rows untuk tabel ini
        await MainActor.run {
            onRowProgress(0, totalCount)
        }

        // ✅ CEK STOP setelah count
        if stopFlag() {
            print("    🛑 Stop after counting \(tableName)")
            return 0
        }

        print("    🔢 Total match di \(tableName): \(totalCount)")

        let connectionCount = pool.connectionCount
        let chunkSize = (totalCount + connectionCount - 1) / connectionCount

        // ✅ KUNCI: Gunakan actor untuk koordinasi cancel
        actor CancelCoordinator {
            var shouldCancel = false
            var resultCount = 0

            func checkCancel(_ stopFlag: @escaping @Sendable () -> Bool) -> Bool {
                if stopFlag() || shouldCancel {
                    shouldCancel = true
                    return true
                }
                return false
            }

            func incrementResult() {
                resultCount += 1
            }

            func getResultCount() -> Int {
                return resultCount
            }
        }

        let coordinator = CancelCoordinator()

        // ✅ PERBAIKAN: Stream hasil real-time + aggressive cancel
        return await withTaskGroup(of: (Int, [BookContent]).self) { group -> Int in
            var processedRows = 0
            // Start workers
            for workerIndex in 0..<connectionCount {
                if stopFlag() {
                    print("    🛑 Skip worker \(workerIndex) - stop before start")
                    break
                }

                let offset = workerIndex * chunkSize
                let limit = min(chunkSize, totalCount - offset)
                if limit <= 0 { continue }

                group.addTask { [weak self] in
                    guard let self = self else { return (workerIndex, []) }

                    let results = await self.searchChunk(
                        tableName: tableName,
                        ftsQuery: ftsQuery, 
                        offset: offset,
                        limit: limit,
                        connectionIndex: workerIndex,
                        pauseController: pauseController,
                        stopFlag: stopFlag
                    )

                    return (workerIndex, results)
                }
            }

            var totalResults = 0

            // ✅ KUNCI: Process hasil SEGERA saat tersedia
            for await (workerIndex, results) in group {
                // ✅ CEK STOP di SETIAP iterasi
                let shouldStop = await coordinator.checkCancel(stopFlag)
                if shouldStop {
                    print("    🛑 CANCELLING TaskGroup - discarding worker \(workerIndex) (\(results.count) rows)")
                    group.cancelAll()  // <-- Cancel semua worker
                    break  // <-- Keluar dari loop SEGERA
                }

                // Process hasil dari worker ini
                for (idx, content) in results.enumerated() {
                    // ✅ CEK PAUSE setiap 10 hasil untuk efisiensi
                    if idx % 10 == 0 {
                        await pauseController.waitIfPaused()

                        if stopFlag() {
                            print("    🛑 Stop while processing results from worker \(workerIndex) at row \(idx)")
                            group.cancelAll()
                            return totalResults
                        }
                    }

                    await MainActor.run {
                        onResult(tableName, content)
                    }
                    totalResults += 1
                    processedRows += 1

                    // ✅ Update row progress setiap 10 rows untuk efisiensi
                    if processedRows % 10 == 0 {
                        onRowProgress(processedRows, totalCount)
                    }
                    progress(totalResults)
                }
            }

            // ✅ Final check sebelum return
            if stopFlag() {
                print("    🛑 Stop at end of TaskGroup")
            }

            // ✅ Final update
            await MainActor.run {
                onRowProgress(totalCount, totalCount)
            }

            return totalResults
        }
    }

    /// ✅ PERBAIKAN: Aggressive stop checking di searchChunk
    private func searchChunk(
        tableName: String,
        ftsQuery: String,
        offset: Int,
        limit: Int,
        connectionIndex: Int,
        pauseController: PauseController,
        stopFlag: @escaping @Sendable () -> Bool
    ) async -> [BookContent] {

        var results: [BookContent] = []
        var currentOffset = offset
        let targetEnd = offset + limit
        // let fullPhrase = normalizedKeywords.joined(separator: " ")

        while currentOffset < targetEnd {
            await pauseController.waitIfPaused()

            if stopFlag() || Task.isCancelled {
                print("      🛑 Worker \(connectionIndex) stopped at offset \(currentOffset)")
                return results
            }

            let batchLimit = min(batchSize, targetEnd - currentOffset)

            let sql = """
                SELECT main.nass, main.page, main.id, main.part
                FROM \(tableName) AS main
                INNER JOIN \(tableName)_fts AS fts ON fts.rowid = main.id
                WHERE fts.nass_clean MATCH ?
                LIMIT ? OFFSET ?
            """
            let queryParams: [SQLValue] = [
                .text(ftsQuery),
                .int(batchLimit),
                .int(currentOffset)
            ]

            let rows: [[String: Any?]]
            do {
                rows = try await pool.read(at: connectionIndex) { conn in
                    try conn.queryRows(sql: sql, params: queryParams)
                }
            } catch {
                let nsError = error as NSError
                if nsError.code == Int(SQLITE_INTERRUPT) {
                    print("      ⚡️ Worker \(connectionIndex) query interrupted")
                }
                return results
            }

            if stopFlag() || Task.isCancelled {
                print("      🛑 Worker \(connectionIndex) stopped after query")
                return results
            }

            if rows.isEmpty { break }

            for (idx, row) in rows.enumerated() {
                if idx % 10 == 0 && (stopFlag() || Task.isCancelled) {
                    return results
                }

                // ✅ PERBAIKAN: Handle nass sebagai BLOB atau String
                var nass = ""
                if let blobData = row["nass"] as? Data {
                    // Jika BLOB, decompress
                    nass = ReusableFunc.decompressData(blobData)
                } else if let textData = row["nass"] as? String {
                    // Fallback: jika masih TEXT (untuk tabel yang belum dikompress)
                    nass = textData
                }

                // Normalize untuk phrase matching
                // let normalizedNass = nass.normalizeArabic()
                // if mode == .phrase, normalizedKeywords.count > 1 {
                    // if !normalizedNass.contains(fullPhrase) {
                        // continue
                    // }
                // }

                let page = (row["page"] as? NSNumber) ?? 0
                let id = (row["id"] as? NSNumber) ?? 0
                let part = (row["part"] as? NSNumber) ?? 0

                let content = BookContent(
                    id: Int(truncating: id),
                    nash: nass,
                    page: Int(truncating: page),
                    part: Int(truncating: part)
                )
                results.append(content)
            }

            currentOffset += rows.count

            if rows.count < batchLimit {
                break
            }
        }

        return results
    }
}

// ----------------------------------------
// MARK: - SearchEngine (koordinator)
// ----------------------------------------
final class SearchEngine {
    private(set) var workers: [SearchWorker] = []
    private let pauseController = PauseController()
    private var searchTask: Task<Void, Never>?
    private var isStopped = false
    private let stopLock = NSLock()

    private var completedWorkers: Int = 0
    private let progressLock = NSLock()

    init() {}

    func registerDB(archiveId: String, tables: [String], connections: [DBConnectionType], batchSize: Int = 200) {
        let pool = SQLiteConnectionPool(conns: connections)
        let worker = SearchWorker(archiveId: archiveId, tables: tables, pool: pool, batchSize: batchSize)
        workers.append(worker)
    }

    func startSearch(
        keywords: [String],
        allowedTables: Set<String>? = nil,
        mode: SearchMode,
        // Callback BARU untuk inisialisasi total workers
        onInitialize: @escaping (Int) -> Void,
        // Callback untuk setiap table selesai di-process
        onTableComplete: @escaping (String, Int) -> Void,
        onRowProgress: @escaping (String, String, Int, Int) -> Void,  // ✅ BARU: (archiveId, tableName, current, total)
        onResult: @escaping (String, String, BookContent) -> Void,
        onComplete: @escaping () -> Void
    ) {

        searchTask?.cancel()
        searchTask = nil
        isStopped = false

        progressLock.lock()
        completedWorkers = 0
        progressLock.unlock()

        print("=== MEMULAI SEARCH: \(workers.count) workers ===")

        // Kirim total workers ke UI
        Task { @MainActor in
            onInitialize(workers.count)
        }

        // Normalisasi keywords
        let normalizedKeywords = keywords.map { ($0) }

        // Buat FTS query - gunakan AND untuk multiple keywords
        let ftsQuery: String
        switch mode {
        case .phrase:
            // keywords.count == 1, karena tidak di-split
            // Wrap dengan quotes untuk phrase search
            ftsQuery = "\"" + normalizedKeywords.joined(separator: " ") + "\""
            // Result: "\"كتاب العلم النافع\""
        case .contains:
            // keywords.count bisa > 1, karena di-split pakai koma
            // Gunakan AND - semua keyword harus ada (tapi tidak harus bersebelahan)
            ftsQuery = normalizedKeywords.joined(separator: " AND ")
            // Result: "كتاب AND العلم AND النافع"
        }

        searchTask = Task.detached(priority: .userInitiated) { [weak self, ftsQuery] in
            guard let self = self else { return }
            for worker in self.workers {
                if self.isStopped { break }

                var completedTables = 0

                await worker.search(
                    ftsQuery: ftsQuery,
                    allowedTables: allowedTables,
                    start: { _ in
                        // Tidak perlu callback start lagi
                    },
                    progress: { count in
                        // Progress per hasil tidak perlu di sini
                    }, 
                    onRowProgress: { tableName, current, total in
                        onRowProgress(worker.archiveId, tableName, current, total)
                    },
                    onResult: { tableName, content in
                        onResult(tableName, worker.archiveId, content)
                    },
                    // TAMBAHAN: Callback per table selesai
                    onTableComplete: {
                        completedTables += 1
                        Task { @MainActor [completedTables] in
                            onTableComplete(worker.archiveId, completedTables)
                        }
                    },
                    pauseController: self.pauseController,
                    stopFlag: { [weak self] in
                        guard let self = self else { return true }
                        return self.isStopped
                    },
                    onComplete: {
                        // Worker selesai
                        self.progressLock.lock()
                        self.completedWorkers += 1
                        self.progressLock.unlock()
                        self.progressLock.unlock()
                    }
                )
            }
            await MainActor.run { onComplete() }
        }
    }

    func checkAndResumeIfNeeded(completion: @escaping (Bool) -> Void) {
        let isPaused = currentlyPaused()

        if isPaused {
            print("Pencarian saat ini dijeda. Melanjutkan (Resuming)...")
            self.resume()
            // Kasus Resume: Kita sudah melanjutkan yang lama. Jangan panggil startSearch.
            completion(true) // <-- Mengembalikan TRUE
        } else {
            print("Pencarian saat ini tidak dijeda. Memerlukan Start Baru.")
            // Kasus Start Baru: Tidak ada yang dijeda, jadi kita perlu mulai baru.
            completion(false) // <-- Mengembalikan FALSE
        }
    }

    func pause() {
        pauseController.pause()
    }

    func resume() {
        pauseController.resume()
    }

    func stop() {
        stopLock.lock()
        isStopped = true
        stopLock.unlock()
        pauseController.stopAndResumeAll()
        searchTask?.cancel()
        searchTask = nil
        cleanup()
    }

    func isRunning() -> Bool {
        !currentlyPaused() && searchTask != nil
    }

    func currentlyPaused() -> Bool {
        return pauseController.currentlyPaused()
    }

    func cleanup() {
        workers.removeAll()
    }
}

// ----------------------------------------
// MARK: - SQLite Connection Implementation
// ----------------------------------------
final class SQLiteConnection: DBConnectionType {
    private let db: OpaquePointer?

    init(dbPath: String) throws {
        var dbPtr: OpaquePointer?
        if sqlite3_open(dbPath, &dbPtr) != SQLITE_OK {
            throw NSError(domain: "SQLite", code: Int(sqlite3_errcode(dbPtr)))
        }
        self.db = dbPtr

        // Attach FTS database
        let ftsPath = dbPath.replacingOccurrences(of: ".sqlite", with: "_fts.sqlite")
        let attachSQL = "ATTACH DATABASE '\(ftsPath)' AS fts_db;"
        sqlite3_exec(db, attachSQL, nil, nil, nil)
    }

    /// UPDATED: queryRows dengan support BLOB
    func queryRows(sql: String, params: [SQLValue]) throws -> [[String: Any?]] {
        guard let db = db else {
            throw NSError(
                domain: "SQLite",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "DB closed"]
            )
        }

        var statement: OpaquePointer?
        var results: [[String: Any?]] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(
                domain: "SQLite",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }

        defer {
            sqlite3_finalize(statement)
        }

        // Bind parameters
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case .text(let s):
                s.withCString { ptr in
                    let destructor = unsafeBitCast(
                        OpaquePointer(bitPattern: -1),
                        to: sqlite3_destructor_type.self
                    )
                    sqlite3_bind_text(statement, idx, ptr, -1, destructor)
                }
            case .int(let n):
                sqlite3_bind_int64(statement, idx, sqlite3_int64(n))
            case .null:
                sqlite3_bind_null(statement, idx)
            }
        }

        // Fetch rows
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any?] = [:]
            let colCount = sqlite3_column_count(statement)

            for c in 0..<colCount {
                let name = String(cString: sqlite3_column_name(statement, c))
                let type = sqlite3_column_type(statement, c)

                switch type {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(statement, c))

                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(statement, c)

                case SQLITE_TEXT:
                    if let txt = sqlite3_column_text(statement, c) {
                        row[name] = String(cString: txt)
                    } else {
                        row[name] = nil
                    }

                case SQLITE_BLOB:
                    // ✅ HANDLE BLOB: Convert ke Data
                    if let blobPointer = sqlite3_column_blob(statement, c) {
                        let blobSize = Int(sqlite3_column_bytes(statement, c))
                        let data = Data(bytes: blobPointer, count: blobSize)
                        row[name] = data
                    } else {
                        row[name] = nil
                    }

                case SQLITE_NULL:
                    row[name] = nil

                default:
                    row[name] = nil
                }
            }

            results.append(row)
        }

        return results
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
}
