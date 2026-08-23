//
//  SQLiteDatabase.swift
//  Maktabah
//

import Foundation
import SQLite3

enum SQLiteError: Error {
    case connectionFailed(String)
    case prepareFailed(String)
    case executionFailed(String)
    case notFound
    case bindFailed(String)
}

struct SQLiteRow {
    let stmt: OpaquePointer

    func int(at index: Int32) -> Int {
        return Int(sqlite3_column_int(stmt, index))
    }

    func int64(at index: Int32) -> Int64 {
        return sqlite3_column_int64(stmt, index)
    }

    func string(at index: Int32) -> String? {
        guard let textPtr = sqlite3_column_text(stmt, index) else { return nil }
        let bytes = sqlite3_column_bytes(stmt, index)
        let buffer = UnsafeBufferPointer(start: textPtr, count: Int(bytes))
        return String(decoding: buffer, as: UTF8.self)
    }

    func double(at index: Int32) -> Double {
        return sqlite3_column_double(stmt, index)
    }

    func blob(at index: Int32) -> Data? {
        guard let blobPtr = sqlite3_column_blob(stmt, index) else { return nil }
        let blobSize = sqlite3_column_bytes(stmt, index)
        return Data(bytes: blobPtr, count: Int(blobSize))
    }

    func rawBlob(at index: Int32) -> UnsafeRawBufferPointer? {
        guard let blobPtr = sqlite3_column_blob(stmt, index) else { return nil }
        let blobSize = sqlite3_column_bytes(stmt, index)
        return UnsafeRawBufferPointer(start: blobPtr, count: Int(blobSize))
    }

    func isNull(at index: Int32) -> Bool {
        return sqlite3_column_type(stmt, index) == SQLITE_NULL
    }

    func type(at index: Int32) -> Int32 {
        return sqlite3_column_type(stmt, index)
    }
}

class SQLiteDatabase {
    let dbPointer: OpaquePointer
    private let lock = NSRecursiveLock()
    private var savepointCounter: Int = 0
    private var statementCache: [String: OpaquePointer] = [:]
    private var cacheKeys: [String] = [] // Untuk LRU eviction
    private let maxCacheSize = 100

    init(path: String, flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX) throws {
        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK {
            self.dbPointer = db!
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

    private func _executeNoLock(query: String, parameters: [Any] = []) throws {
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

        if sqlite3_step(stmt) != SQLITE_DONE {
            let error = String(cString: sqlite3_errmsg(dbPointer))
            throw SQLiteError.executionFailed(error)
        }
    }

    @discardableResult
    private func _fetchNoLock<T>(query: String, parameters: [Any] = [], mapping: (SQLiteRow) throws -> T) throws -> [T] {
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

        var results: [T] = []
        let row = SQLiteRow(stmt: stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let mapped = try mapping(row)
            results.append(mapped)
        }

        return results
    }

    func lastInsertRowId() -> Int64 {
        return sqlite3_last_insert_rowid(dbPointer)
    }

    func checkpoint() {
        lock.lock()
        defer { lock.unlock() }
        try? _executeNoLock(query: "PRAGMA wal_checkpoint(TRUNCATE);")
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
}
