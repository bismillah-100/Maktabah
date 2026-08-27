//
//  SQLiteConnection.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//

import Foundation
import SQLite3

final class SQLiteConnection: DBConnectionType {
    private let db: OpaquePointer?
    private var statementCache: [String: OpaquePointer] = [:]
    private var cacheKeys: [String] = []
    private let maxCacheSize = 50
    /// Mutex explicitly protecting both dictionary manipulation and statement execution
    /// to prevent EXC_BAD_ACCESS if multiple Task instances call this connection simultaneously.
    private let executionLock = NSLock()

    init(dbPath: String) throws {
        var dbPtr: OpaquePointer?
        if sqlite3_open(dbPath, &dbPtr) != SQLITE_OK {
            throw NSError(domain: "SQLite", code: Int(sqlite3_errcode(dbPtr)))
        }
        db = dbPtr

        let ftsPath = dbPath.replacing(".sqlite", with: "_fts.sqlite")
        try db?.safeAttachDatabase(path: ftsPath, schema: "fts_db")
    }

    private func getOrPrepareStatement(sql: String, db: OpaquePointer) throws -> OpaquePointer {
        if let statement = statementCache[sql] {
            if let idx = cacheKeys.firstIndex(of: sql) {
                cacheKeys.remove(at: idx)
                cacheKeys.append(sql)
            }
            return statement
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "SQLite", code: -2, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        if statementCache.count >= maxCacheSize, let oldestKey = cacheKeys.first {
            if let oldStmt = statementCache.removeValue(forKey: oldestKey) {
                sqlite3_finalize(oldStmt)
            }
            cacheKeys.removeFirst()
        }
        statementCache[sql] = stmt
        cacheKeys.append(sql)
        return stmt
    }

    private func bindParams(_ params: [SQLValue], to stmt: OpaquePointer) {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

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
    }

    func execute(query: String) throws {
        guard let db else {
            throw NSError(domain: "SQLite", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database is closed"])
        }
        executionLock.lock()
        defer { executionLock.unlock() }

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
        executionLock.lock()
        defer { executionLock.unlock() }

        try db.safeAttachDatabase(path: path, schema: schema)
    }

    private func withBoundStatement<T>(
        sql: String,
        params: [SQLValue],
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        guard let db else {
            throw NSError(domain: "SQLite", code: -1, userInfo: [NSLocalizedDescriptionKey: "DB closed"])
        }

        executionLock.lock()
        defer { executionLock.unlock() }

        let stmt = try getOrPrepareStatement(sql: sql, db: db)
        bindParams(params, to: stmt)
        return try body(stmt)
    }

    func queryMapped<T>(sql: String, params: [SQLValue], mapper: (OpaquePointer) -> T) throws -> [T] {
        try withBoundStatement(sql: sql, params: params) { stmt in
            var results: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(mapper(stmt))
            }
            return results
        }
    }

    func queryInts(sql: String, params: [SQLValue]) throws -> [Int] {
        try queryMapped(sql: sql, params: params) { stmt in
            Int(sqlite3_column_int64(stmt, 0))
        }
    }

    func queryContents(sql: String, params: [SQLValue]) throws -> [BookContent] {
        try queryMapped(sql: sql, params: params) { stmt in
            let nass = stmt.columnTextOrDecompressedBlob(0)
            let page = Int(sqlite3_column_int64(stmt, 1))
            let id = Int(sqlite3_column_int64(stmt, 2))
            let part = Int(sqlite3_column_int64(stmt, 3))
            return BookContent(id: id, nash: nass, page: page, part: part)
        }
    }

    func queryTarjamah(sql: String, params: [SQLValue], isIsoName: Bool) throws -> [TarjamahMen] {
        let nameIndex: Int32 = isIsoName ? 1 : 0
        return try queryMapped(sql: sql, params: params) { stmt in
            let nameStr = stmt.columnTextOrDecompressedBlob(nameIndex)
            let bk = Int(sqlite3_column_int64(stmt, 2))
            let id = Int(sqlite3_column_int64(stmt, 3))
            return TarjamahMen(name: nameStr, bk: bk, id: id)
        }
    }

    func querySingleNass(sql: String, params: [SQLValue]) throws -> String? {
        try queryMapped(sql: sql, params: params) { stmt in
            stmt.columnTextOrDecompressedBlob(0)
        }.first
    }

    func queryRows(sql: String, params: [SQLValue]) throws -> [[String: Any?]] {
        try withBoundStatement(sql: sql, params: params) { stmt in
            let colCount = sqlite3_column_count(stmt)
            let columnNames = (0 ..< colCount).map { stmt.columnName($0) }

            var results: [[String: Any?]] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any?] = [:]
                for c in 0 ..< colCount {
                    row[columnNames[Int(c)]] = extractColumnValue(from: stmt, column: c)
                }
                results.append(row)
            }
            return results
        }
    }

    private func extractColumnValue(from stmt: OpaquePointer, column: Int32) -> Any? {
        switch sqlite3_column_type(stmt, column) {
        case SQLITE_INTEGER:
            Int(sqlite3_column_int64(stmt, column))
        case SQLITE_FLOAT:
            sqlite3_column_double(stmt, column)
        case SQLITE_TEXT:
            stmt.columnString(column)
        case SQLITE_BLOB:
            stmt.columnBlob(column)
        default:
            nil
        }
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
