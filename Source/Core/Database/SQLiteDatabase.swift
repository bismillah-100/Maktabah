//
//  SQLiteDatabase.swift
//  Maktabah
//

import Foundation
import SQLite3

enum SQLiteError: LocalizedError {
    case connectionFailed(String)
    case prepareFailed(String)
    case executionFailed(String)
    case notFound
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .prepareFailed(let msg): return "Prepare failed: \(msg)"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        case .notFound: return "Record not found"
        case .bindFailed(let msg): return "Bind failed: \(msg)"
        }
    }
}

struct SQLiteRow {
    let stmt: OpaquePointer

    func int(at index: Int32) -> Int {
        Int(sqlite3_column_int(stmt, index))
    }

    func int64(at index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    func string(at index: Int32) -> String? {
        stmt.columnString(index)
    }

    func double(at index: Int32) -> Double {
        sqlite3_column_double(stmt, index)
    }

    func blob(at index: Int32) -> Data? {
        stmt.columnBlob(index)
    }

    func rawBlob(at index: Int32) -> UnsafeRawBufferPointer? {
        stmt.columnRawBlob(index)
    }

    func isNull(at index: Int32) -> Bool {
        sqlite3_column_type(stmt, index) == SQLITE_NULL
    }

    func type(at index: Int32) -> Int32 {
        sqlite3_column_type(stmt, index)
    }
}

class SQLiteDatabase {
    let dbPointer: OpaquePointer
    private let lock = NSRecursiveLock()
    private var savepointCounter: Int = 0
    private var statementCache: [String: OpaquePointer] = [:]
    private var cacheKeys: [String] = [] // Untuk LRU eviction
    private let maxCacheSize = 100

    init(
        path: String,
        flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
        queryOnly: Bool = false
    ) throws {

        if flags & SQLITE_OPEN_READWRITE != 0 {
            let fm = FileManager.default
            let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o644]
            try? fm.setAttributes(attrs, ofItemAtPath: path)
            try? fm.setAttributes(attrs, ofItemAtPath: path + "-wal")
            try? fm.setAttributes(attrs, ofItemAtPath: path + "-shm")
        }

        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK {
            dbPointer = db!
            if queryOnly {
                try execute(query: "PRAGMA query_only = ON;")
            }
            sqlite3_busy_timeout(dbPointer, 5000)
        } else {
            let errorMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw SQLiteError.connectionFailed(errorMsg)
        }
    }

    deinit {
        for stmt in statementCache.values {
            sqlite3_finalize(stmt)
        }
        statementCache.removeAll()
        sqlite3_close(dbPointer)
    }

    func transaction(_ block: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        // Cek apakah sudah dalam transaksi aktif untuk mendukung nested transaction.
        // SQLite tidak mendukung nested BEGIN TRANSACTION — gunakan SAVEPOINT sebagai gantinya.
        let isNested = sqlite3_get_autocommit(dbPointer) == 0

        if isNested {
            savepointCounter += 1
            let savepointName = "sp\(savepointCounter)"
            defer { savepointCounter -= 1 }

            try _executeNoLock(query: "SAVEPOINT \(savepointName);")
            do {
                try block()
                try _executeNoLock(query: "RELEASE SAVEPOINT \(savepointName);")
            } catch {
                try? _executeNoLock(query: "ROLLBACK TO SAVEPOINT \(savepointName);")
                try? _executeNoLock(query: "RELEASE SAVEPOINT \(savepointName);")
                throw error
            }
        } else {
            try _executeNoLock(query: "BEGIN TRANSACTION;")
            do {
                try block()
                try _executeNoLock(query: "COMMIT;")
            } catch {
                try? _executeNoLock(query: "ROLLBACK;")
                throw error
            }
        }
    }

    func execute(query: String, parameters: [Any] = []) throws {
        lock.lock()
        defer { lock.unlock() }
        try _executeNoLock(query: query, parameters: parameters)
    }

    @discardableResult
    func fetch<T>(query: String, parameters: [Any] = [], mapping: (SQLiteRow) throws -> T) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }
        return try _fetchNoLock(query: query, parameters: parameters, mapping: mapping)
    }

    // MARK: - Internal no-lock variants (caller must hold lock)

    private func preparedStatement(for query: String, parameters: [Any]) throws -> OpaquePointer {
        let stmt: OpaquePointer

        if let cachedStmt = statementCache[query] {
            stmt = cachedStmt
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            // Perbarui LRU order
            if let idx = cacheKeys.firstIndex(of: query) {
                cacheKeys.remove(at: idx)
                cacheKeys.append(query)
            }
        } else {
            var newStmt: OpaquePointer?
            guard sqlite3_prepare_v2(dbPointer, query, -1, &newStmt, nil) == SQLITE_OK else {
                let error = String(cString: sqlite3_errmsg(dbPointer))
                throw SQLiteError.prepareFailed(error)
            }
            stmt = newStmt!

            if statementCache.count >= maxCacheSize, let oldestKey = cacheKeys.first {
                if let oldStmt = statementCache.removeValue(forKey: oldestKey) {
                    sqlite3_finalize(oldStmt)
                }
                cacheKeys.removeFirst()
            }
            statementCache[query] = stmt
            cacheKeys.append(query)
        }

        try bind(parameters: parameters, to: stmt)
        return stmt
    }

    private func _executeNoLock(query: String, parameters: [Any] = []) throws {
        let stmt = try preparedStatement(for: query, parameters: parameters)
        defer { sqlite3_reset(stmt) }

        if sqlite3_step(stmt) != SQLITE_DONE {
            let error = String(cString: sqlite3_errmsg(dbPointer))
            throw SQLiteError.executionFailed(error)
        }
    }

    @discardableResult
    private func _fetchNoLock<T>(query: String, parameters: [Any] = [], mapping: (SQLiteRow) throws -> T) throws -> [T] {
        let stmt = try preparedStatement(for: query, parameters: parameters)
        defer { sqlite3_reset(stmt) }

        var results: [T] = []
        let row = SQLiteRow(stmt: stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let mapped = try mapping(row)
            results.append(mapped)
        }

        return results
    }

    func lastInsertRowId() -> Int64 {
        sqlite3_last_insert_rowid(dbPointer)
    }

    func checkpoint() {
        lock.lock()
        defer { lock.unlock() }
        try? _executeNoLock(query: "PRAGMA wal_checkpoint(TRUNCATE);")
    }

    func enableWALMode() {
        lock.lock()
        defer { lock.unlock() }
        _ = try? _fetchNoLock(query: "PRAGMA journal_mode = WAL;") { row in
            row.string(at: 0) ?? ""
        }
    }

    func tableColumns(tableName: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return (try? _fetchNoLock(query: "PRAGMA table_info('\(tableName)');") { row in
            row.string(at: 1) ?? ""
        }) ?? []
    }

    private func bind(parameters: [Any], to stmt: OpaquePointer?) throws {
        for (index, value) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            switch value {
            case let intVal as Int:
                sqlite3_bind_int64(stmt, bindIndex, Int64(intVal))
            case let int64Val as Int64:
                sqlite3_bind_int64(stmt, bindIndex, int64Val)
            case let doubleVal as Double:
                sqlite3_bind_double(stmt, bindIndex, doubleVal)
            case let stringVal as String:
                let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                sqlite3_bind_text(stmt, bindIndex, stringVal, -1, SQLITE_TRANSIENT)
            case is NSNull:
                sqlite3_bind_null(stmt, bindIndex)
            default:
                throw SQLiteError.bindFailed("Unsupported type for parameter at index \(index)")
            }
        }
    }
}

// MARK: - Safe Database Attach

extension OpaquePointer {
    func safeAttachDatabase(path: String, schema: String) throws {
        let sql = "ATTACH DATABASE ? AS \(schema)"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(self, sql, -1, &stmt, nil) == SQLITE_OK else {
            let errorString = String(cString: sqlite3_errmsg(self))
            throw NSError(domain: "SQLite", code: Int(sqlite3_errcode(self)), userInfo: [NSLocalizedDescriptionKey: "Prepare failed: \(errorString)"])
        }
        defer { sqlite3_finalize(stmt) }

        path.withCString { ptr in
            let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, ptr, -1, SQLITE_TRANSIENT)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let errorString = String(cString: sqlite3_errmsg(self))
            throw NSError(domain: "SQLite", code: Int(sqlite3_errcode(self)), userInfo: [NSLocalizedDescriptionKey: "Step failed: \(errorString)"])
        }
    }

    // MARK: - Statement Column Readers

    /// Reads UTF-8 string from a SQLite statement column at index.
    func columnString(_ index: Int32) -> String? {
        guard let textPtr = sqlite3_column_text(self, index) else { return nil }
        let bytes = sqlite3_column_bytes(self, index)
        let buffer = UnsafeBufferPointer(start: textPtr, count: Int(bytes))
        return String(bytes: buffer, encoding: .utf8)
    }

    /// Reads column name from a SQLite statement at index.
    func columnName(_ index: Int32) -> String {
        guard let namePtr = sqlite3_column_name(self, index) else { return "" }
        let nameLen = strlen(namePtr)
        let buffer = UnsafeRawBufferPointer(start: UnsafeRawPointer(namePtr), count: Int(nameLen))
        return String(bytes: buffer, encoding: .utf8) ?? ""
    }

    /// Reads blob Data from a SQLite statement column at index.
    func columnBlob(_ index: Int32) -> Data? {
        guard let blobPtr = sqlite3_column_blob(self, index) else { return nil }
        let blobSize = sqlite3_column_bytes(self, index)
        return Data(bytes: blobPtr, count: Int(blobSize))
    }

    /// Reads raw blob buffer from a SQLite statement column at index.
    func columnRawBlob(_ index: Int32) -> UnsafeRawBufferPointer? {
        guard let blobPtr = sqlite3_column_blob(self, index) else { return nil }
        let blobSize = sqlite3_column_bytes(self, index)
        return UnsafeRawBufferPointer(start: blobPtr, count: Int(blobSize))
    }

    /// Reads text or decompressed LZString blob from a SQLite statement column at index.
    func columnTextOrDecompressedBlob(_ index: Int32) -> String {
        let type = sqlite3_column_type(self, index)
        if type == SQLITE_TEXT {
            return columnString(index) ?? ""
        } else if type == SQLITE_BLOB, let raw = columnRawBlob(index) {
            return ZstdDecompressor.decompressData(from: raw)
        }
        return ""
    }

    // MARK: - Database Table Queries

    /// Lists table/view names from a SQLite database connection.
    func listTableNames(schemaName: String = "main", whereCondition: String = "type='table'") -> [String] {
        let sql = "SELECT name FROM \(schemaName).sqlite_master WHERE \(whereCondition) ORDER BY name;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(self, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var tables: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = stmt.columnString(0) {
                tables.append(name)
            }
        }
        return tables
    }

    // MARK: - Database Close

    /// Truncate wal_checkpoint and close_v2.
    func truncateAndClose() {
        _ = sqlite3_exec(self, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        sqlite3_close_v2(self)
    }
}
