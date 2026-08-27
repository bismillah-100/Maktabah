//
//  BookUpdateMgr+Import.swift
//  Maktabah
//
//  Created by MacBook on 06/02/26.
//

import Foundation
import SQLite3

extension BookUpdateManager {
    func importOfflineUpdate(
        from url: URL,
        providedMetadata: BookMetadata? = nil,
        authorRow: [String: Any]? = nil
    ) async throws -> BookUpdateResult {
        guard let metadata = try providedMetadata ?? readBookMetadata(from: url, fallbackBookId: 0) else {
            throw NSError(
                domain: "BookUpdate",
                code: -6,
                userInfo: [
                    NSLocalizedDescriptionKey: "Metadata kitab (tabel main_update) tidak ditemukan di file sqlite tersebut.",
                ]
            )
        }

        try preCreateArchiveTables(archiveId: metadata.archive, bookId: metadata.bkid)

        let workingDirectory = try makeWorkingDirectory()
        let downloadedBookURL = workingDirectory.appendingPathComponent(
            "book_\(metadata.bkid)_\(UUID().uuidString).sqlite"
        )
        try FileManager.default.copyItem(at: url, to: downloadedBookURL)

        let ftsSourceURL = try prepareFtsSourceAndRename(
            downloadedBookURL: downloadedBookURL,
            bookId: metadata.bkid,
            workingDirectory: workingDirectory
        )

        let entry = BookIndexEntry(
            bkid: metadata.bkid,
            bk: metadata.bk,
            category: metadata.cat ?? 0,
            versionName: Int64(metadata.bVer ?? 0),
            downloadURL: "",
            fileSize: 0
        )

        importAuthorRowIfNeeded(authorRow)

        let stagedUpdate = StagedBookUpdate(
            entry: entry,
            metadata: metadata,
            downloadedBookURL: downloadedBookURL,
            ftsSourceURL: ftsSourceURL,
            authorContext: nil,
            workingDirectory: workingDirectory
        )

        return try await applyStagedBookUpdate(stagedUpdate, isOfflineImport: true)
    }

    private func importAuthorRowIfNeeded(_ authorRow: [String: Any]?) {
        guard let authorRow, let specialPath = AppConfig.specialDatabasePath else { return }
        do {
            let specialDb = try openDatabase(path: specialPath)
            defer { sqlite3_close_v2(specialDb) }
            try insertAuthorRow(authorRow, into: specialDb)
        } catch {
            DispatchQueue.main.async {
                ReusableFunc.showAlert(
                    title: "Error",
                    message: "[Offline Import] Failed to insert author row: \(error)"
                )
            }
        }
    }

    func preCreateArchiveTables(archiveId: Int, bookId: Int) throws {
        guard let targetPath = AppConfig.archiveDatabasePath(archiveId: archiveId) else { return }

        let db = try openDatabase(path: targetPath)
        defer { sqlite3_close_v2(db) }

        #if DEBUG
        print("[Import] Pre-creating tables in archive \(archiveId)...")
        #endif

        let contentSchema = "(nass BLOB, part INTEGER, id INTEGER, page INTEGER)"
        let tocSchema = "(tit TEXT, lvl INTEGER, sub INTEGER, id INTEGER)"
        try exec(db, "CREATE TABLE IF NOT EXISTS \"b\(bookId)\" \(contentSchema);")
        try exec(db, "CREATE TABLE IF NOT EXISTS \"t\(bookId)\" \(tocSchema);")
    }

    #if DEBUG
    func listAllTables(at url: URL) -> [String] {
        guard let db = try? openDatabase(path: url.path) else { return [] }
        defer { sqlite3_close_v2(db) }
        return db.listTableNames(whereCondition: "type IN ('table', 'view')")
    }
    #endif

    func applyStagedBookUpdate(
        _ stagedUpdate: StagedBookUpdate,
        knownExists: Bool? = nil,
        isOfflineImport: Bool = false
    ) async throws -> BookUpdateResult {
        defer {
            FileManager.default.removeDatabaseAndSidecars(at: stagedUpdate.ftsSourceURL)
            FileManager.default.removeDatabaseAndSidecars(at: stagedUpdate.downloadedBookURL)
        }

        let exists = try knownExists ?? bookExists(id: stagedUpdate.metadata.bkid)

        if !isOfflineImport {
            let needsUpdate = try bookNeedsUpdate(
                id: stagedUpdate.metadata.bkid,
                newVersion: stagedUpdate.entry.versionName
            )

            guard !exists || needsUpdate else {
                return BookUpdateResult(
                    bookId: stagedUpdate.metadata.bkid,
                    catId: stagedUpdate.entry.category,
                    action: .skipped
                )
            }
        }

        if let authorContext = stagedUpdate.authorContext {
            try await ensureAuthor(
                authId: authorContext.authId,
                downloadURL: authorContext.downloadURL,
                workingDirectory: stagedUpdate.workingDirectory,
                newVersion: authorContext.versionName
            )
        }

        try convertBookDatabase(at: stagedUpdate.downloadedBookURL, bookId: stagedUpdate.metadata.bkid)
        try await BookArchiveSingleFlight.shared.run(
            archiveId: stagedUpdate.metadata.archive,
            bookId: stagedUpdate.metadata.bkid
        ) { [weak self] in
            guard let self else { return }
            try self.replaceArchiveDatabase(
                with: stagedUpdate.downloadedBookURL,
                archiveId: stagedUpdate.metadata.archive,
                bookId: stagedUpdate.metadata.bkid,
                ftsSourceURL: stagedUpdate.ftsSourceURL
            )
        }

        if !exists {
            try insertBookMetadata(stagedUpdate.metadata)
        } else if isOfflineImport {
            try updateBookMetadata(stagedUpdate.metadata)
        } else {
            try updateBookVersion(stagedUpdate.metadata)
        }

        // Hapus cache per-kitab di folder Books jika ada, agar pembaca beralih ke arsip yang diperbarui
        BookDownloadManager.shared.removeCachedBook(bookId: stagedUpdate.metadata.bkid)

        return BookUpdateResult(
            bookId: stagedUpdate.metadata.bkid,
            catId: stagedUpdate.entry.category,
            action: exists ? .updated : .inserted
        )
    }

    func changeBookId(oldId: Int, newId: Int) throws {
        guard let mainPath = AppConfig.mainDatabasePath else { return }

        let db = try openDatabase(path: mainPath)
        defer { db.truncateAndClose() }

        let archiveId = fetchArchiveId(for: oldId, db: db)
        let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId)
        let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)

        if let archivePath {
            try renameArchiveTables(archivePath: archivePath, oldId: oldId, newId: newId)
        }

        if let ftsPath {
            try renameFtsTables(ftsPath: ftsPath, archivePath: archivePath, oldId: oldId, newId: newId)
        }

        try updateMainDatabaseBookId(db: db, archivePath: archivePath, ftsPath: ftsPath, oldId: oldId, newId: newId)
    }

    private func fetchArchiveId(for bookId: Int, db: OpaquePointer?) -> Int {
        var archiveId = 20
        let selectSql = "SELECT `Archive` FROM `0bok` WHERE `bkid` = ? LIMIT 1;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, selectSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(bookId))
            if sqlite3_step(stmt) == SQLITE_ROW {
                archiveId = Int(sqlite3_column_int64(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return archiveId
    }

    private func renameArchiveTables(archivePath: String, oldId: Int, newId: Int) throws {
        let archiveDb = try openDatabase(path: archivePath)
        defer { sqlite3_close_v2(archiveDb) }

        _ = sqlite3_exec(archiveDb, "DROP TABLE IF EXISTS \"b\(newId)\";", nil, nil, nil)
        _ = sqlite3_exec(archiveDb, "DROP INDEX IF EXISTS \"b\(newId)\";", nil, nil, nil)
        _ = sqlite3_exec(archiveDb, "DROP TABLE IF EXISTS \"t\(newId)\";", nil, nil, nil)
        _ = sqlite3_exec(archiveDb, "DROP INDEX IF EXISTS \"t\(newId)\";", nil, nil, nil)

        let sqlB = "ALTER TABLE \"b\(oldId)\" RENAME TO \"b\(newId)\";"
        guard sqlite3_exec(archiveDb, sqlB, nil, nil, nil) == SQLITE_OK else {
            throw NSError(
                domain: "BookUpdate", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Gagal rename tabel b\(oldId) di archive."]
            )
        }

        let sqlT = "ALTER TABLE \"t\(oldId)\" RENAME TO \"t\(newId)\";"
        if sqlite3_exec(archiveDb, sqlT, nil, nil, nil) != SQLITE_OK {
            _ = sqlite3_exec(archiveDb, "ALTER TABLE \"b\(newId)\" RENAME TO \"b\(oldId)\";", nil, nil, nil)
            throw NSError(
                domain: "BookUpdate", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Gagal rename tabel t\(oldId) di archive."]
            )
        }
    }

    private func renameFtsTables(ftsPath: String, archivePath: String?, oldId: Int, newId: Int) throws {
        let ftsDb = try openDatabase(path: ftsPath)
        defer { sqlite3_close_v2(ftsDb) }

        _ = sqlite3_exec(ftsDb, "DROP TABLE IF EXISTS \"b\(newId)_fts\";", nil, nil, nil)

        let sqlFTS = "ALTER TABLE \"b\(oldId)_fts\" RENAME TO \"b\(newId)_fts\";"
        if sqlite3_exec(ftsDb, sqlFTS, nil, nil, nil) != SQLITE_OK {
            rollbackBookIdRenames(archivePath: archivePath, ftsPath: nil, oldId: oldId, newId: newId)
            throw NSError(
                domain: "BookUpdate", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Gagal rename tabel FTS b\(oldId)_fts."]
            )
        }
    }

    private func updateMainDatabaseBookId(
        db: OpaquePointer?,
        archivePath: String?,
        ftsPath: String?,
        oldId: Int,
        newId: Int
    ) throws {
        let deleteSql = "DELETE FROM `0bok` WHERE `bkid` = ?;"
        var deleteStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(deleteStmt, 1, Int64(newId))
            sqlite3_step(deleteStmt)
        }
        sqlite3_finalize(deleteStmt)

        let updateSql = "UPDATE `0bok` SET `bkid` = ? WHERE `bkid` = ?;"
        var updateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSql, -1, &updateStmt, nil) == SQLITE_OK else {
            rollbackBookIdRenames(archivePath: archivePath, ftsPath: ftsPath, oldId: oldId, newId: newId)
            throw NSError(
                domain: "BookUpdate", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Gagal prepare update bkid di main database."]
            )
        }
        defer { sqlite3_finalize(updateStmt) }

        sqlite3_bind_int64(updateStmt, 1, Int64(newId))
        sqlite3_bind_int64(updateStmt, 2, Int64(oldId))

        guard sqlite3_step(updateStmt) == SQLITE_DONE else {
            rollbackBookIdRenames(archivePath: archivePath, ftsPath: ftsPath, oldId: oldId, newId: newId)
            throw NSError(
                domain: "BookUpdate", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Gagal update bkid di main database."]
            )
        }
    }

    private func rollbackBookIdRenames(
        archivePath: String?,
        ftsPath: String?,
        oldId: Int,
        newId: Int
    ) {
        if let archivePath, let archiveDb = try? openDatabase(path: archivePath) {
            defer { sqlite3_close_v2(archiveDb) }
            _ = sqlite3_exec(archiveDb,
                             "ALTER TABLE \"b\(newId)\" RENAME TO \"b\(oldId)\";", nil, nil, nil)
            _ = sqlite3_exec(archiveDb,
                             "ALTER TABLE \"t\(newId)\" RENAME TO \"t\(oldId)\";", nil, nil, nil)
        }
        if let ftsPath, let ftsDb = try? openDatabase(path: ftsPath) {
            defer { sqlite3_close_v2(ftsDb) }
            _ = sqlite3_exec(ftsDb,
                             "ALTER TABLE \"b\(newId)_fts\" RENAME TO \"b\(oldId)_fts\";", nil, nil, nil)
        }
    }

    func convertBookDatabase(at url: URL, bookId: Int) throws {
        let db = try openDatabase(path: url.path)
        defer { sqlite3_close_v2(db) }

        let tableName = "b\(bookId)"
        let tempTable = "\(tableName)_zstd"
        let columns = try ArchiveDatabaseTools.loadTableColumns(tableName: tableName, db: db)

        if columns.isEmpty {
            throw sqliteError(db, message: "Tabel \(tableName) tidak ditemukan di file sumber.")
        }

        try ArchiveDatabaseTools.withTransaction(db: db) {
            try exec(db, "DROP TABLE IF EXISTS \(tempTable);")
            let createSQL = ArchiveDatabaseTools.makeCreateTableSQL(tableName: tempTable, columns: columns)
            try exec(db, createSQL)

            try copyRowsCompressingNass(db: db, sourceTable: tableName, targetTable: tempTable, columns: columns)

            try exec(db, "DROP TABLE \(tableName);")
            try exec(db, "ALTER TABLE \(tempTable) RENAME TO \(tableName);")
        }
    }

    private func copyRowsCompressingNass(
        db: OpaquePointer,
        sourceTable: String,
        targetTable: String,
        columns: [ArchiveDatabaseTools.TableColumnInfo]
    ) throws {
        let columnNames = columns.map(\.name)
        let selectSQL = "SELECT \(columnNames.joined(separator: ", ")) FROM \(sourceTable);"
        let insertSQL = "INSERT INTO \(targetTable) (\(columnNames.joined(separator: ", "))) VALUES (\(String(repeating: "?, ", count: columnNames.count).dropLast(2)));"

        var selectStmt: OpaquePointer?
        var insertStmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
            throw sqliteError(db, message: "Gagal prepare SELECT konversi.")
        }
        defer { sqlite3_finalize(selectStmt) }

        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            throw sqliteError(db, message: "Gagal prepare INSERT konversi.")
        }
        defer { sqlite3_finalize(insertStmt) }

        while sqlite3_step(selectStmt) == SQLITE_ROW {
            sqlite3_reset(insertStmt)
            for (index, column) in columns.enumerated() {
                let colIndex = Int32(index)
                if column.name.lowercased() == "nass" {
                    bindCompressedNass(from: selectStmt, to: insertStmt, colIndex: colIndex)
                } else if let selectStmt, let insertStmt {
                    bindColumnValue(from: selectStmt, to: insertStmt, columnIndex: colIndex)
                }
            }

            if sqlite3_step(insertStmt) != SQLITE_DONE {
                throw sqliteError(db, message: "Gagal insert konversi.")
            }
        }
    }

    private func bindCompressedNass(from selectStmt: OpaquePointer?, to insertStmt: OpaquePointer?, colIndex: Int32) {
        if let text = selectStmt?.columnString(colIndex), let compressed = ZstdDecompressor.compressData(text) {
            _ = compressed.withUnsafeBytes { bytes in
                sqlite3_bind_blob(insertStmt, colIndex + 1, bytes.baseAddress, Int32(compressed.count), sqliteTransient)
            }
        } else {
            sqlite3_bind_null(insertStmt, colIndex + 1)
        }
    }

    func renameTablesIfNeeded(at url: URL, to targetId: Int) throws {
        let db = try openDatabase(path: url.path)
        defer { sqlite3_close_v2(db) }

        let targetBTable = "b\(targetId)"
        let targetTTable = "t\(targetId)"

        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE '%_fts%' AND name NOT LIKE '%_zstd%';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }

        var bCandidates: [String] = []
        var tCandidates: [String] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let tableName = stmt.columnString(0) else { continue }
            if tableName.hasPrefix("b") {
                bCandidates.append(tableName)
            } else if tableName.hasPrefix("t") {
                tCandidates.append(tableName)
            }
        }

        let existingB = bCandidates.first(where: { $0.dropFirst().allSatisfy(\.isNumber) && !$0.dropFirst().isEmpty })
            ?? bCandidates.first(where: { $0 == "b" }) ?? bCandidates.first

        let existingT = tCandidates.first(where: { $0.dropFirst().allSatisfy(\.isNumber) && !$0.dropFirst().isEmpty })
            ?? tCandidates.first(where: { $0 == "t" }) ?? tCandidates.first

        if let existingB, existingB != targetBTable {
            try exec(db, "ALTER TABLE \"\(existingB)\" RENAME TO \"\(targetBTable)\";")
        }

        if let existingT, existingT != targetTTable {
            try exec(db, "ALTER TABLE \"\(existingT)\" RENAME TO \"\(targetTTable)\";")
        }
    }

    func replaceArchiveDatabase(
        with sourceURL: URL,
        archiveId: Int,
        bookId: Int,
        ftsSourceURL: URL
    ) throws {
        guard let targetPath = AppConfig.archiveDatabasePath(archiveId: archiveId),
              let ftsDBPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
        else { return }
        var dbPtr: OpaquePointer? = try openDatabase(path: targetPath)
        guard let db = dbPtr else { return }
        defer {
            if let db = dbPtr {
                checkpoint(db: db)
            }
        }

        try db.safeAttachDatabase(path: sourceURL.path, schema: "source_db")
        try db.safeAttachDatabase(path: ftsSourceURL.path, schema: "fts_source_db")
        try db.safeAttachDatabase(path: ftsDBPath, schema: "fts_db")

        let tableName = "b\(bookId)"
        let tocTable = "t\(bookId)"
        let ftsTable = "\(tableName)_fts"

        // 1. Copy tabel data dan TOC ke main dalam transaksi atomik
        try ArchiveDatabaseTools.withTransaction(db: db) {
            try ArchiveDatabaseTools.copyTable(
                db: db,
                sourceSchema: "source_db",
                tableName: tableName
            )
            try ArchiveDatabaseTools.copyTable(
                db: db,
                sourceSchema: "source_db",
                tableName: tocTable
            )
        }

        // 2. Build FTS terpisah di luar transaksi main
        // (buildFTS memiliki transaksi internal sendiri untuk batch insert)
        // kolom nass merupakan TEXT, tidak perlu konversi dari blob untuk menjaga performa
        try ArchiveDatabaseTools.buildFTS(
            db: db,
            ftsSchema: "fts_db",
            ftsTable: ftsTable,
            sourceSchema: "fts_source_db",
            sourceTable: tableName
        )

        checkpoint(db: db)
        dbPtr = nil

        IntegrationCache.shared.markIntegrated(
            bookId: bookId,
            archiveId: archiveId
        )

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .bookIntegrated,
                object: bookId
            )
        }
    }

    private func checkpoint(db: OpaquePointer) {
        _ = sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA journal_mode = DELETE;", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA fts_db.wal_checkpoint(TRUNCATE);", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA fts_db.journal_mode = DELETE;", nil, nil, nil)

        try? exec(db, "DETACH DATABASE fts_db;")
        try? exec(db, "DETACH DATABASE fts_source_db;")
        try? exec(db, "DETACH DATABASE source_db;")

        sqlite3_close_v2(db)
    }
}
