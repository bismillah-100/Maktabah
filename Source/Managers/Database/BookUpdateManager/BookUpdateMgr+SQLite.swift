//
//  BookUpdateMgr+SQLite.swift
//  Maktabah
//
//  Created by MacBook on 06/02/26.
//

import Foundation
import SQLite3

extension BookUpdateManager {
    func openDatabase(path: String) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let validDb = db {
            sqlite3_busy_timeout(validDb, 30000)
            _ = sqlite3_exec(validDb, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            _ = sqlite3_exec(validDb, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
            return validDb
        } else {
            let error = sqliteError(db, message: "Gagal membuka database \(path)")
            if let db { sqlite3_close_v2(db) }
            throw error
        }
    }

    func withMainDatabase<T>(_ work: (OpaquePointer) throws -> T) throws -> T {
        guard let mainPath = AppConfig.mainDatabasePath else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Base path main.sqlite tidak tersedia."]
            )
        }
        let db = try openDatabase(path: mainPath)
        defer { db.truncateAndClose() }
        return try work(db)
    }

    func withSpecialDatabase<T>(_ work: (OpaquePointer) throws -> T) throws -> T {
        guard let specialPath = AppConfig.specialDatabasePath else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Base path special.sqlite tidak tersedia."]
            )
        }
        let db = try openDatabase(path: specialPath)
        defer { db.truncateAndClose() }
        return try work(db)
    }

    func executeStatement(
        in db: OpaquePointer,
        sql: String,
        bind: (OpaquePointer) throws -> Void
    ) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw sqliteError(db, message: "Gagal prepare SQL statement.")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw sqliteError(db, message: "Gagal eksekusi SQL statement.")
        }
    }

    func exec(_ db: OpaquePointer, _ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw sqliteError(db, message: "SQL gagal dieksekusi.")
        }
    }

    func withTransaction(
        _ db: OpaquePointer,
        _ work: () throws -> Void
    ) throws {
        try ArchiveDatabaseTools.withTransaction(db: db, work)
    }

    func bindColumnValue(
        from selectStmt: OpaquePointer,
        to insertStmt: OpaquePointer,
        columnIndex: Int32
    ) {
        let type = sqlite3_column_type(selectStmt, columnIndex)
        let bindIndex = columnIndex + 1

        switch type {
        case SQLITE_INTEGER:
            sqlite3_bind_int64(insertStmt, bindIndex, sqlite3_column_int64(selectStmt, columnIndex))
        case SQLITE_FLOAT:
            sqlite3_bind_double(insertStmt, bindIndex, sqlite3_column_double(selectStmt, columnIndex))
        case SQLITE_TEXT:
            bindColumnText(from: selectStmt, to: insertStmt, columnIndex: columnIndex, bindIndex: bindIndex)
        case SQLITE_BLOB:
            bindColumnBlob(from: selectStmt, to: insertStmt, columnIndex: columnIndex, bindIndex: bindIndex)
        default:
            sqlite3_bind_null(insertStmt, bindIndex)
        }
    }

    private func bindColumnText(
        from selectStmt: OpaquePointer,
        to insertStmt: OpaquePointer,
        columnIndex: Int32,
        bindIndex: Int32
    ) {
        if let text = selectStmt.columnString(columnIndex) {
            _ = text.withCString {
                sqlite3_bind_text(insertStmt, bindIndex, $0, -1, sqliteTransient)
            }
        } else {
            sqlite3_bind_null(insertStmt, bindIndex)
        }
    }

    private func bindColumnBlob(
        from selectStmt: OpaquePointer,
        to insertStmt: OpaquePointer,
        columnIndex: Int32,
        bindIndex: Int32
    ) {
        if let blob = selectStmt.columnBlob(columnIndex) {
            _ = blob.withUnsafeBytes { ptr in
                sqlite3_bind_blob(insertStmt, bindIndex, ptr.baseAddress, Int32(blob.count), sqliteTransient)
            }
        } else {
            sqlite3_bind_null(insertStmt, bindIndex)
        }
    }

    func sqliteError(_ db: OpaquePointer?, message: String) -> NSError {
        let detail =
            db.flatMap { String(cString: sqlite3_errmsg($0)) }
                ?? "Unknown error"
        return NSError(
            domain: "BookUpdate",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: "\(message) (\(detail))"]
        )
    }

    func columnText(_ stmt: OpaquePointer?, index: Int32) -> String {
        stmt?.columnString(index) ?? ""
    }

    func resolveVersionColumn(in db: OpaquePointer) -> String? {
        if let cachedVersionColumn {
            #if DEBUG
            print("📦 [Version] Using cached version column: \(cachedVersionColumn)")
            #endif
            return cachedVersionColumn
        }

        let columns = fetchPragmaColumns(in: db, table: "0bok")
        #if DEBUG
        print("📋 [Version] Available columns: \(columns)")
        #endif

        let lowered = columns.map { $0.lowercased() }
        if let index = lowered.firstIndex(where: { versionColumnCandidates.contains($0) }) {
            let matched = columns[index]
            cachedVersionColumn = matched
            #if DEBUG
            print("✅ [Version] Resolved version column: \(matched)")
            #endif
            return matched
        }

        #if DEBUG
        print("❌ [Version] No version column found among candidates: \(versionColumnCandidates)")
        #endif
        return nil
    }

    private func fetchPragmaColumns(in db: OpaquePointer, table: String) -> [String] {
        let sql = "PRAGMA table_info('\(table)');"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            #if DEBUG
            print("⚠️ [Version] Failed to prepare PRAGMA statement")
            #endif
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var columns: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let col = stmt?.columnString(1) {
                columns.append(col)
            }
        }
        return columns
    }
}
