//
//  ArchiveDatabaseTools.swift
//  Maktabah
//
//  Shared helpers for table copy/replace and FTS building.
//

import Foundation
import SQLite3

enum ArchiveDatabaseTools {
    static let sqliteTransient = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )

    struct TableColumnInfo {
        let name: String
        let type: String
        let isPrimaryKey: Bool
    }

    static func replaceTable(
        db: OpaquePointer,
        tableName: String,
        sourceSchema: String
    ) throws {
        let columns = try loadTableColumns(
            tableName: tableName,
            db: db,
            schemaName: sourceSchema
        )

        let createSQL = makeCreateTableSQL(
            tableName: tableName,
            columns: columns
        )

        try exec(db, "DROP TABLE IF EXISTS \(tableName);")
        try exec(db, createSQL)
        try exec(
            db,
            "INSERT INTO \"\(tableName)\" SELECT * FROM \(sourceSchema).\"\(tableName)\";"
        )
    }


    /// Menyalin satu tabel dari `sourceSchema` ke `main`.
    /// `CREATE TABLE … AS SELECT` menyalin skema + data sekaligus.
    static func copyTable(
        db: OpaquePointer,
        sourceSchema: String,
        tableName: String
    ) throws {
        try exec(db, "DROP TABLE IF EXISTS main.\"\(tableName)\";")
        try exec(
            db,
            "CREATE TABLE main.\"\(tableName)\" AS SELECT * FROM \(sourceSchema).\"\(tableName)\";"
        )
    }

    /// Membangun FTS dari `sourceSchema.<sourceTable>` ke `ftsSchema.<ftsTable>`.
    /// Kolom `nass` diasumsikan TEXT.
    static func buildFTS(
        db: OpaquePointer,
        ftsSchema: String = "fts_db",
        ftsTable: String,
        sourceSchema: String,
        sourceTable: String
    ) throws {
        try exec(db, "DROP TABLE IF EXISTS \(ftsSchema).\(ftsTable);")
        try exec(
            db,
            "CREATE VIRTUAL TABLE \(ftsSchema).\(ftsTable) USING fts5(nass_clean, content='', tokenize='unicode61');"
        )

        let selectSQL =
            "SELECT id, nass FROM \(sourceSchema).\(sourceTable) WHERE nass IS NOT NULL AND nass != '';"
        let insertSQL =
            "INSERT INTO \(ftsSchema).\(ftsTable)(rowid, nass_clean) VALUES (?, ?);"

        var selectStmt: OpaquePointer?
        var insertStmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
            throw sqliteError(db, message: "Error prepare SELECT FTS \(ftsTable).")
        }
        defer { sqlite3_finalize(selectStmt) }

        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            throw sqliteError(db, message: "Error prepare INSERT FTS \(ftsTable).")
        }
        defer { sqlite3_finalize(insertStmt) }

        while sqlite3_step(selectStmt) == SQLITE_ROW {
            guard let textPtr = sqlite3_column_text(selectStmt, 1) else { continue }
            let textBytes = sqlite3_column_bytes(selectStmt, 1)
            let textBuffer = UnsafeBufferPointer(start: textPtr, count: Int(textBytes))
            let normalized = String(decoding: textBuffer, as: UTF8.self)
                .replacingOccurrences(of: "\n", with: " ")
                .normalizeArabic()
            guard !normalized.isEmpty else { continue }

            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)
            sqlite3_bind_int64(insertStmt, 1, sqlite3_column_int64(selectStmt, 0))
            _ = normalized.withCString {
                sqlite3_bind_text(insertStmt, 2, $0, -1, sqliteTransient)
            }

            if sqlite3_step(insertStmt) != SQLITE_DONE {
                throw sqliteError(db, message: "Error insert FTS \(ftsTable).")
            }
        }
    }

    static func loadTableColumns(
        tableName: String,
        db: OpaquePointer,
        schemaName: String = "main"
    ) throws -> [TableColumnInfo] {
        let sql = "PRAGMA \(schemaName).table_info('\(tableName)');"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(
                db,
                message: "Error load info tabel \(tableName)."
            )
        }
        defer { sqlite3_finalize(stmt) }

        var columns: [TableColumnInfo] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let namePtr = sqlite3_column_text(stmt, 1)
            let typePtr = sqlite3_column_text(stmt, 2)

            let name = namePtr.flatMap { String(cString: $0) } ?? ""
            let type = typePtr.flatMap { String(cString: $0) } ?? ""

            let isPrimaryKey = sqlite3_column_int64(stmt, 5) == 1
            columns.append(
                TableColumnInfo(
                    name: name,
                    type: type,
                    isPrimaryKey: isPrimaryKey
                )
            )
        }
        return columns
    }

    static func makeCreateTableSQL(
        tableName: String,
        columns: [TableColumnInfo]
    ) -> String {
        let definitions = columns.map { column -> String in
            let primaryKey = column.isPrimaryKey ? " PRIMARY KEY" : ""
            if column.name.lowercased() == "nass" {
                return "\(column.name) BLOB\(primaryKey)"
            }
            return "\(column.name) \(column.type)\(primaryKey)"
        }
        return
            "CREATE TABLE \(tableName) (\(definitions.joined(separator: ", ")));"
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw sqliteError(db, message: "Run SQL Error.")
        }
    }

    private static func sqliteError(
        _ db: OpaquePointer?,
        message: String
    ) -> NSError {
        let detail =
            db.flatMap { String(cString: sqlite3_errmsg($0)) }
                ?? "Unknown error"
        return NSError(
            domain: "ArchiveDatabaseTools",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: "\(message) (\(detail))"]
        )
    }
}
