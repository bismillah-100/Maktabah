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

/// ----------------------------------------
protocol DBConnectionType {
    func queryRows(sql: String, params: [SQLValue]) throws -> [[String: Any?]]
    func queryMapped<T>(sql: String, params: [SQLValue], mapper: (OpaquePointer) -> T) throws -> [T]
    func queryInts(sql: String, params: [SQLValue]) throws -> [Int]
    func execute(query: String) throws
    func attachDatabase(path: String, as schema: String) throws
    func queryContents(sql: String, params: [SQLValue]) throws -> [BookContent]
    func queryTarjamah(sql: String, params: [SQLValue], isIsoName: Bool) throws -> [TarjamahMen]
    func querySingleNass(sql: String, params: [SQLValue]) throws -> String?
}

enum SQLValue {
    case text(String)
    case int(Int)
    case null
}

// ----------------------------------------
// MARK: - PauseController (actor)

/// ----------------------------------------
actor PauseController {
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
        for cont in conts {
            cont.resume()
        }
    }

    func stopAndResumeAll() {
        resume()
    }

    func waitIfPaused() async {
        guard isPaused else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            continuations.append(continuation)
        }
    }

    func currentlyPaused() -> Bool {
        isPaused
    }
}

// ----------------------------------------
// MARK: - Connection Pool per file (actor)

/// ----------------------------------------
class SQLiteConnectionPool {
    private var connections: [DBConnectionType]

    init(conns: [DBConnectionType]) {
        connections = conns
    }

    var connectionCount: Int {
        connections.count
    }

    /// Ambil koneksi berdasarkan index
    func getConnection(at index: Int) -> DBConnectionType {
        connections[index % connections.count]
    }

    /// Menjalankan read-operation pada koneksi tertentu
    func read<T>(at index: Int, _ body: @escaping (DBConnectionType) throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            let conn = self.getConnection(at: index)
            return try body(conn)
        }.value
    }
}

// ----------------------------------------
// MARK: - Worker per file

/// ----------------------------------------
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
            ? tables.filter { (allowedTables?.contains($0) ?? false) }
            : tables

        print("🔍 Archive \(archiveId): Mulai mencari di \(tablesToProcess.count) tables")
        start(tablesToProcess.count)

        for (index, tableName) in tablesToProcess.enumerated() {
            // ✅ CEK STOP sebelum mulai table
            if stopFlag() {
                print("ℹ️ Archive \(archiveId): stop sebelum table \(index + 1)/\(tablesToProcess.count)")
                return
            }

            await pauseController.waitIfPaused()

            // ✅ CEK STOP setelah resume
            if stopFlag() {
                print("ℹ️ Archive \(archiveId): stop setelah resume sebelum table \(index + 1)")
                return
            }

            print("  📄 [\(index + 1)/\(tablesToProcess.count)] \(tableName)")

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
                return // <-- KELUAR LANGSUNG!
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
        // Phase 1: Fast ID Fetch (mengambil seluruh rowid yang match)
        let matchedIDs: [Int]
        do {
            matchedIDs = try await pool.read(at: 0) { conn in
                let idSQL = """
                    SELECT rowid
                    FROM \(tableName)_fts
                    WHERE nass_clean MATCH ?
                """
                return try conn.queryInts(sql: idSQL, params: [.text(ftsQuery)])
            }
        } catch {
            print("⚠️ Error fetching IDs for table \(tableName): \(error)")
            return 0
        }
        let totalCount = matchedIDs.count
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

            func checkCancel(_ stopFlag: @escaping @Sendable () -> Bool) -> Bool {
                if stopFlag() || shouldCancel {
                    shouldCancel = true
                    return true
                }
                return false
            }


        }

        let coordinator = CancelCoordinator()

        // ✅ PERBAIKAN: Stream hasil real-time + aggressive cancel
        return await withTaskGroup(of: (Int, [BookContent]).self) { group -> Int in
            var processedRows = 0
            // Start workers
            for workerIndex in 0 ..< connectionCount {
                if stopFlag() {
                    print("    🛑 Skip worker \(workerIndex) - stop before start")
                    break
                }

                let startIndex = workerIndex * chunkSize
                if startIndex >= totalCount { continue }
                let endIndex = min(startIndex + chunkSize, totalCount)
                let chunkIDs = Array(matchedIDs[startIndex..<endIndex])

                group.addTask { [weak self] in
                    guard let self else { return (workerIndex, []) }

                    let results = await searchChunkByIDs(
                        tableName: tableName,
                        ids: chunkIDs,
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
                    group.cancelAll() // <-- Cancel semua worker
                    break // <-- Keluar dari loop SEGERA
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

                    onResult(tableName, content)

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

    /// ✅ PERBAIKAN: Menggunakan ID-based fetching untuk menghindari LIMIT ... OFFSET bottleneck
    private func searchChunkByIDs(
        tableName: String,
        ids: [Int],
        connectionIndex: Int,
        pauseController: PauseController,
        stopFlag: @escaping @Sendable () -> Bool
    ) async -> [BookContent] {
        var results: [BookContent] = []
        var currentIndex = 0
        
        while currentIndex < ids.count {
            await pauseController.waitIfPaused()

            if stopFlag() || Task.isCancelled {
                print("      🛑 Worker \(connectionIndex) stopped at index \(currentIndex)")
                return results
            }

            let batchEnd = min(currentIndex + batchSize, ids.count)
            let batchIDs = ids[currentIndex..<batchEnd]
            currentIndex = batchEnd

            let placeholders = String(repeating: "?,", count: batchIDs.count).dropLast()
            let sql = """
                SELECT nass, page, id, part
                FROM \(tableName)
                WHERE id IN (\(placeholders))
            """

            let params = batchIDs.map { SQLValue.int($0) }

            let fetchedContents: [BookContent]
            do {
                fetchedContents = try await pool.read(at: connectionIndex) { conn in
                    try conn.queryContents(sql: sql, params: params)
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

            if fetchedContents.isEmpty { continue }

            for (idx, content) in fetchedContents.enumerated() {
                if idx % 10 == 0, stopFlag() || Task.isCancelled {
                    return results
                }
                results.append(content)
            }
        }

        return results
    }
}

// ----------------------------------------
// MARK: - SearchEngine (koordinator)

/// ----------------------------------------
final class SearchEngine {
    private(set) var workers: [SearchWorker] = []
    private let pauseController = PauseController()
    private var searchTask: Task<Void, Never>?
    private var isStopped = false
    private let stopLock = NSLock()
    private let workersLock = NSLock()


    init() {}

    func registerDB(archiveId: String, tables: [String], connections: [DBConnectionType], batchSize: Int = 200) {
        let pool = SQLiteConnectionPool(conns: connections)
        let worker = SearchWorker(archiveId: archiveId, tables: tables, pool: pool, batchSize: batchSize)
        workersLock.lock()
        workers.append(worker)
        workersLock.unlock()
    }

    func startSearch(
        query: String = "",
        keywords: [String] = [],
        allowedTables: Set<String>? = nil,
        mode: SearchMode,
        nearDistance: Int = 10,
        // Callback BARU untuk inisialisasi total workers
        onInitialize: @escaping (Int) -> Void,
        // Callback untuk setiap table selesai di-process
        onTableComplete: @escaping (String, Int) -> Void,
        onRowProgress: @escaping (String, String, Int, Int) -> Void, // ✅ BARU: (archiveId, tableName, current, total)
        onResult: @escaping (String, String, BookContent) -> Void,
        onComplete: @escaping () -> Void
    ) {
        searchTask?.cancel()
        searchTask = nil
        isStopped = false


        workersLock.lock()
        let currentWorkers = workers
        workersLock.unlock()

        print("=== MEMULAI SEARCH: \(currentWorkers.count) workers ===")

        // Kirim total workers ke UI
        Task { @MainActor in
            onInitialize(currentWorkers.count)
        }

        let inputQuery = query.isEmpty ? keywords.joined(separator: " ") : query
        let ftsQuery = FtsQueryParser.buildFtsQuery(query: inputQuery, mode: mode, nearDistance: nearDistance)

        if ftsQuery.isEmpty {
            Task { @MainActor in onComplete() }
            return
        }

        searchTask = Task.detached(priority: .userInitiated) { [weak self, ftsQuery, currentWorkers] in
            guard let self else { return }
            for worker in currentWorkers {
                if isStopped { break }

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
                        onTableComplete(worker.archiveId, completedTables)
                    },
                    pauseController: pauseController,
                    stopFlag: { [weak self] in
                        guard let self else { return true }
                        return isStopped
                    },
                    onComplete: {
                        // Worker selesai
                    }
                )
            }
            await MainActor.run { onComplete() }
        }
    }

    func checkAndResumeIfNeeded(completion: @escaping (Bool) -> Void) {
        Task {
            let isPaused = await currentlyPaused()

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
    }

    func pause() {
        Task {
            await pauseController.pause()
        }
    }

    func resume() {
        Task {
            await pauseController.resume()
        }
    }

    func stop() {
        stopLock.lock()
        isStopped = true
        stopLock.unlock()
        Task {
            await pauseController.stopAndResumeAll()
        }
        searchTask?.cancel()
        searchTask = nil
        cleanup()
    }

    func isRunning() async -> Bool {
        let isPaused = await currentlyPaused()
        return !isPaused && searchTask != nil
    }

    func currentlyPaused() async -> Bool {
        await pauseController.currentlyPaused()
    }

    func cleanup() {
        workersLock.lock()
        workers.removeAll()
        workersLock.unlock()
    }
}

// ----------------------------------------
// MARK: - SQLite Connection Implementation

/// ----------------------------------------
final class SQLiteConnection: DBConnectionType {
    private let db: OpaquePointer?
    private var statementCache: [String: OpaquePointer] = [:]
    private var cacheKeys: [String] = []
    private let maxCacheSize = 50
    // Mutex explicitly protecting both dictionary manipulation and statement execution
    // to prevent EXC_BAD_ACCESS if multiple Task instances call this connection simultaneously.
    private let executionLock = NSLock()

    init(dbPath: String) throws {
        var dbPtr: OpaquePointer?
        if sqlite3_open(dbPath, &dbPtr) != SQLITE_OK {
            throw NSError(domain: "SQLite", code: Int(sqlite3_errcode(dbPtr)))
        }
        db = dbPtr

        // Attach FTS database
        let ftsPath = dbPath.replacingOccurrences(of: ".sqlite", with: "_fts.sqlite")
        try db?.safeAttachDatabase(path: ftsPath, schema: "fts_db")
    }

    func queryInts(sql: String, params: [SQLValue]) throws -> [Int] {
        guard let db else {
            throw NSError(
                domain: "SQLite",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "DB closed"]
            )
        }

        var results: [Int] = []

        executionLock.lock()
        var statement: OpaquePointer? = statementCache[sql]
        if statement == nil {
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                executionLock.unlock()
                let msg = String(cString: sqlite3_errmsg(db))
                throw NSError(
                    domain: "SQLite",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: msg]
                )
            }
            if statementCache.count >= maxCacheSize, let oldestKey = cacheKeys.first {
                if let oldStmt = statementCache.removeValue(forKey: oldestKey) {
                    sqlite3_finalize(oldStmt)
                }
                cacheKeys.removeFirst()
            }
            statementCache[sql] = statement
            cacheKeys.append(sql)
        } else {
            if let idx = cacheKeys.firstIndex(of: sql) {
                cacheKeys.remove(at: idx)
                cacheKeys.append(sql)
            }
        }
        let stmt = statement!
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        defer { executionLock.unlock() }

        // Bind parameters
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let .text(s):
                s.withCString { ptr in
                    let destructor = unsafeBitCast(
                        OpaquePointer(bitPattern: -1),
                        to: sqlite3_destructor_type.self
                    )
                    sqlite3_bind_text(stmt, idx, ptr, -1, destructor)
                }
            case let .int(n):
                sqlite3_bind_int64(stmt, idx, sqlite3_int64(n))
            case .null:
                sqlite3_bind_null(stmt, idx)
            }
        }

        // Fetch ints directly
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(Int(sqlite3_column_int64(stmt, 0)))
        }

        return results
    }

    func execute(query: String) throws {
        guard let db else {
            throw NSError(domain: "SQLite", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database is closed"])
        }
        var errMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, query, nil, nil, &errMsg) != SQLITE_OK {
            let errorString = errMsg != nil ? String(cString: errMsg!) : "Unknown error"
            sqlite3_free(errMsg)
            throw NSError(domain: "SQLite", code: Int(sqlite3_errcode(db)), userInfo: [NSLocalizedDescriptionKey: errorString])
        }
    }

    func attachDatabase(path: String, as schema: String) throws {
        guard let db else {
            throw NSError(domain: "SQLite", code: -1, userInfo: [NSLocalizedDescriptionKey: "DB closed"])
        }
        try db.safeAttachDatabase(path: path, schema: schema)
    }

    func queryMapped<T>(sql: String, params: [SQLValue], mapper: (OpaquePointer) -> T) throws -> [T] {
        guard let db else {
            throw NSError(domain: "SQLite", code: -1, userInfo: [NSLocalizedDescriptionKey: "DB closed"])
        }

        var results: [T] = []

        executionLock.lock()
        var statement: OpaquePointer? = statementCache[sql]
        if statement == nil {
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                executionLock.unlock()
                let msg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "SQLite", code: -2, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            if statementCache.count >= maxCacheSize, let oldestKey = cacheKeys.first {
                if let oldStmt = statementCache.removeValue(forKey: oldestKey) {
                    sqlite3_finalize(oldStmt)
                }
                cacheKeys.removeFirst()
            }
            statementCache[sql] = statement
            cacheKeys.append(sql)
        } else {
            if let idx = cacheKeys.firstIndex(of: sql) {
                cacheKeys.remove(at: idx)
                cacheKeys.append(sql)
            }
        }
        let stmt = statement!
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        defer { executionLock.unlock() }

        // Bind parameters
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let .text(s):
                s.withCString { ptr in
                    let destructor = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
                    sqlite3_bind_text(stmt, idx, ptr, -1, destructor)
                }
            case let .int(n):
                sqlite3_bind_int64(stmt, idx, sqlite3_int64(n))
            case .null:
                sqlite3_bind_null(stmt, idx)
            }
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(mapper(stmt))
        }

        return results
    }

    /// UPDATED: queryRows dengan support BLOB
    func queryRows(sql: String, params: [SQLValue]) throws -> [[String: Any?]] {
        guard let db else {
            throw NSError(
                domain: "SQLite",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "DB closed"]
            )
        }

        var results: [[String: Any?]] = []

        executionLock.lock()
        var statement: OpaquePointer? = statementCache[sql]
        if statement == nil {
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                executionLock.unlock()
                let msg = String(cString: sqlite3_errmsg(db))
                throw NSError(
                    domain: "SQLite",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: msg]
                )
            }
            if statementCache.count >= maxCacheSize, let oldestKey = cacheKeys.first {
                if let oldStmt = statementCache.removeValue(forKey: oldestKey) {
                    sqlite3_finalize(oldStmt)
                }
                cacheKeys.removeFirst()
            }
            statementCache[sql] = statement
            cacheKeys.append(sql)
        } else {
            if let idx = cacheKeys.firstIndex(of: sql) {
                cacheKeys.remove(at: idx)
                cacheKeys.append(sql)
            }
        }
        let stmt = statement!
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        defer { executionLock.unlock() }

        // Bind parameters
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let .text(s):
                s.withCString { ptr in
                    let destructor = unsafeBitCast(
                        OpaquePointer(bitPattern: -1),
                        to: sqlite3_destructor_type.self
                    )
                    sqlite3_bind_text(stmt, idx, ptr, -1, destructor)
                }
            case let .int(n):
                sqlite3_bind_int64(stmt, idx, sqlite3_int64(n))
            case .null:
                sqlite3_bind_null(stmt, idx)
            }
        }

        // Cache column names to prevent O(N) allocations
        let colCount = sqlite3_column_count(stmt)
        var columnNames: [String] = []
        for c in 0 ..< colCount {
            if let namePtr = sqlite3_column_name(stmt, c) {
                let nameLen = strlen(namePtr)
                let rawPtr = UnsafeRawPointer(namePtr)
                let buffer = UnsafeRawBufferPointer(start: rawPtr, count: Int(nameLen))
                columnNames.append(String(decoding: buffer, as: UTF8.self))
            } else {
                columnNames.append("")
            }
        }

        // Fetch rows
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any?] = [:]

            for c in 0 ..< colCount {
                let name = columnNames[Int(c)]
                let type = sqlite3_column_type(stmt, c)

                switch type {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(stmt, c))

                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, c)

                case SQLITE_TEXT:
                    if let txt = sqlite3_column_text(stmt, c) {
                        let bytes = sqlite3_column_bytes(stmt, c)
                        let buffer = UnsafeBufferPointer(start: txt, count: Int(bytes))
                        row[name] = String(decoding: buffer, as: UTF8.self)
                    } else {
                        row[name] = nil
                    }

                case SQLITE_BLOB:
                    // ✅ HANDLE BLOB: Convert ke Data
                    if let blobPointer = sqlite3_column_blob(stmt, c) {
                        let blobSize = Int(sqlite3_column_bytes(stmt, c))
                        row[name] = Data(bytes: blobPointer, count: blobSize)
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

    func queryContents(sql: String, params: [SQLValue]) throws -> [BookContent] {
        guard let db else { throw NSError(domain: "SQLite", code: -1, userInfo: nil) }
        var results: [BookContent] = []

        executionLock.lock()
        var statement: OpaquePointer? = statementCache[sql]
        if statement == nil {
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                executionLock.unlock()
                throw NSError(domain: "SQLite", code: -2, userInfo: nil)
            }
            if statementCache.count >= maxCacheSize, let oldestKey = cacheKeys.first {
                if let oldStmt = statementCache.removeValue(forKey: oldestKey) {
                    sqlite3_finalize(oldStmt)
                }
                cacheKeys.removeFirst()
            }
            statementCache[sql] = statement
            cacheKeys.append(sql)
        } else {
            if let idx = cacheKeys.firstIndex(of: sql) {
                cacheKeys.remove(at: idx)
                cacheKeys.append(sql)
            }
        }
        let stmt = statement!
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        defer { executionLock.unlock() }

        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let .text(s):
                s.withCString { ptr in
                    let destructor = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
                    sqlite3_bind_text(stmt, idx, ptr, -1, destructor)
                }
            case let .int(n):
                sqlite3_bind_int64(stmt, idx, sqlite3_int64(n))
            case .null:
                sqlite3_bind_null(stmt, idx)
            }
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            var nass = ""
            let type = sqlite3_column_type(stmt, 0)

            if type == SQLITE_TEXT {
                if let txt = sqlite3_column_text(stmt, 0) {
                    let bytes = sqlite3_column_bytes(stmt, 0)
                    let buffer = UnsafeBufferPointer(start: txt, count: Int(bytes))
                    nass = String(decoding: buffer, as: UTF8.self)
                }
            } else if type == SQLITE_BLOB {
                if let blobPointer = sqlite3_column_blob(stmt, 0) {
                    let blobSize = Int(sqlite3_column_bytes(stmt, 0))
                    let buffer = UnsafeRawBufferPointer(start: blobPointer, count: blobSize)
                    nass = ReusableFunc.decompressData(from: buffer)
                }
            }

            let page = Int(sqlite3_column_int64(stmt, 1))
            let id = Int(sqlite3_column_int64(stmt, 2))
            let part = Int(sqlite3_column_int64(stmt, 3))
            results.append(BookContent(id: id, nash: nass, page: page, part: part))
        }
        return results
    }

    func queryTarjamah(sql: String, params: [SQLValue], isIsoName: Bool) throws -> [TarjamahMen] {
        guard let db else { throw NSError(domain: "SQLite", code: -1, userInfo: nil) }
        var results: [TarjamahMen] = []

        executionLock.lock()
        var statement: OpaquePointer? = statementCache[sql]
        if statement == nil {
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                executionLock.unlock()
                throw NSError(domain: "SQLite", code: -2, userInfo: nil)
            }
            if statementCache.count >= maxCacheSize, let oldestKey = cacheKeys.first {
                if let oldStmt = statementCache.removeValue(forKey: oldestKey) {
                    sqlite3_finalize(oldStmt)
                }
                cacheKeys.removeFirst()
            }
            statementCache[sql] = statement
            cacheKeys.append(sql)
        } else {
            if let idx = cacheKeys.firstIndex(of: sql) {
                cacheKeys.remove(at: idx)
                cacheKeys.append(sql)
            }
        }
        let stmt = statement!
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        defer { executionLock.unlock() }

        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let .text(s):
                s.withCString { ptr in
                    let destructor = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
                    sqlite3_bind_text(stmt, idx, ptr, -1, destructor)
                }
            case let .int(n):
                sqlite3_bind_int64(stmt, idx, sqlite3_int64(n))
            case .null:
                sqlite3_bind_null(stmt, idx)
            }
        }

        let nameIndex: Int32 = isIsoName ? 1 : 0

        while sqlite3_step(stmt) == SQLITE_ROW {
            var nameStr = ""
            let type = sqlite3_column_type(stmt, nameIndex)

            if type == SQLITE_TEXT {
                if let txt = sqlite3_column_text(stmt, nameIndex) {
                    let bytes = sqlite3_column_bytes(stmt, nameIndex)
                    let buffer = UnsafeBufferPointer(start: txt, count: Int(bytes))
                    nameStr = String(decoding: buffer, as: UTF8.self)
                }
            } else if type == SQLITE_BLOB {
                if let blobPointer = sqlite3_column_blob(stmt, nameIndex) {
                    let blobSize = Int(sqlite3_column_bytes(stmt, nameIndex))
                    let buffer = UnsafeRawBufferPointer(start: blobPointer, count: blobSize)
                    nameStr = ReusableFunc.decompressData(from: buffer)
                }
            }

            let bk = Int(sqlite3_column_int64(stmt, 2))
            let id = Int(sqlite3_column_int64(stmt, 3))

            results.append(TarjamahMen(name: nameStr, bk: bk, id: id))
        }
        return results
    }

    func querySingleNass(sql: String, params: [SQLValue]) throws -> String? {
        guard let db else { throw NSError(domain: "SQLite", code: -1, userInfo: nil) }

        executionLock.lock()
        var statement: OpaquePointer? = statementCache[sql]
        if statement == nil {
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                executionLock.unlock()
                throw NSError(domain: "SQLite", code: -2, userInfo: nil)
            }
            if statementCache.count >= maxCacheSize, let oldestKey = cacheKeys.first {
                if let oldStmt = statementCache.removeValue(forKey: oldestKey) {
                    sqlite3_finalize(oldStmt)
                }
                cacheKeys.removeFirst()
            }
            statementCache[sql] = statement
            cacheKeys.append(sql)
        } else {
            if let idx = cacheKeys.firstIndex(of: sql) {
                cacheKeys.remove(at: idx)
                cacheKeys.append(sql)
            }
        }
        let stmt = statement!
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        defer { executionLock.unlock() }

        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let .text(s):
                s.withCString { ptr in
                    let destructor = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
                    sqlite3_bind_text(stmt, idx, ptr, -1, destructor)
                }
            case let .int(n):
                sqlite3_bind_int64(stmt, idx, sqlite3_int64(n))
            case .null:
                sqlite3_bind_null(stmt, idx)
            }
        }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let type = sqlite3_column_type(stmt, 0)
            if type == SQLITE_TEXT {
                if let txt = sqlite3_column_text(stmt, 0) {
                    let bytes = sqlite3_column_bytes(stmt, 0)
                    let buffer = UnsafeBufferPointer(start: txt, count: Int(bytes))
                    return String(decoding: buffer, as: UTF8.self)
                }
            } else if type == SQLITE_BLOB {
                if let blobPointer = sqlite3_column_blob(stmt, 0) {
                    let blobSize = Int(sqlite3_column_bytes(stmt, 0))
                    let buffer = UnsafeRawBufferPointer(start: blobPointer, count: blobSize)
                    return ReusableFunc.decompressData(from: buffer)
                }
            }
        }
        return nil
    }

    deinit {
        executionLock.lock()
        for stmt in statementCache.values {
            sqlite3_finalize(stmt)
        }
        statementCache.removeAll()
        executionLock.unlock()

        if let db {
            sqlite3_close(db)
        }
    }
}
