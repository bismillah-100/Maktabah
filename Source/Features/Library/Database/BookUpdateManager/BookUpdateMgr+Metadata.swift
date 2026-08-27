//
//  BookUpdateMgr+Metadata.swift
//  Maktabah
//
//  Created by MacBook on 06/02/26.
//

import Foundation
import SQLite3

extension BookUpdateManager {
    func readBookMetadata(from url: URL, fallbackBookId: Int) throws -> BookMetadata? {
        #if DEBUG
        print("url:", url.absoluteString)
        #endif

        let db = try openDatabase(path: url.path)
        defer { sqlite3_close_v2(db) }

        var stmt: OpaquePointer?
        let sql = """
        SELECT bkid, bk, cat, betaka, inf, authno, archive, TafseerNam, bVer, link, PdfCs
        FROM main_update
        WHERE bkid = ? LIMIT 1;
        """
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let fallbackSql = """
            SELECT bkid, bk, cat, betaka, inf, authno, archive, TafseerNam, bVer, link
            FROM main_update
            WHERE bkid = ? LIMIT 1;
            """
            guard sqlite3_prepare_v2(db, fallbackSql, -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(fallbackBookId))
        guard sqlite3_step(stmt) == SQLITE_ROW, let stmt else { return nil }

        return parseBookMetadata(stmt: stmt)
    }

    private func parseBookMetadata(stmt: OpaquePointer) -> BookMetadata {
        let bkid = Int(sqlite3_column_int64(stmt, 0))
        let bk = columnText(stmt, index: 1)
        let cat = Int(sqlite3_column_int64(stmt, 2))
        let betaka = columnText(stmt, index: 3)
        let inf = columnText(stmt, index: 4)
        let authno = Int(sqlite3_column_int64(stmt, 5))
        let archive = Int(sqlite3_column_int64(stmt, 6))
        let tafseerNam = columnText(stmt, index: 7)
        let bVer = Int(sqlite3_column_int64(stmt, 8))
        let link = columnText(stmt, index: 9)

        var pdfCs: Int? = nil
        if sqlite3_column_count(stmt) > 10 {
            pdfCs = Int(sqlite3_column_int64(stmt, 10))
        }

        return BookMetadata(
            bkid: bkid,
            cat: cat,
            bk: bk,
            archive: archive,
            betaka: betaka.isEmpty ? nil : betaka,
            authno: authno,
            inf: inf.isEmpty ? nil : inf,
            tafseerNam: tafseerNam.isEmpty ? nil : tafseerNam,
            bVer: bVer,
            link: link.isEmpty ? nil : link,
            pdfCs: pdfCs
        )
    }

    func insertBookMetadata(_ metadata: BookMetadata) throws {
        try withMainDatabase { db in
            let sql = """
            INSERT INTO `0bok` (`bkid`, `cat`, `bk`, `Archive`, `betaka`, `authno`, `inf`, `TafseerNam`, `bVer`, `PdfCs`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            try executeStatement(in: db, sql: sql) { stmt in
                sqlite3_bind_int64(stmt, 1, Int64(metadata.bkid))
                bindCommonMetadataFields(metadata, to: stmt, startingAt: 2)
            }
        }
    }

    func updateBookVersion(_ metadata: BookMetadata) throws {
        try withMainDatabase { db in
            let sql = "UPDATE `0bok` SET `bVer` = ? WHERE `bkid` = ?;"
            try executeStatement(in: db, sql: sql) { stmt in
                bindOptionalInt(stmt, index: 1, value: metadata.bVer)
                sqlite3_bind_int64(stmt, 2, Int64(metadata.bkid))
            }
            #if DEBUG
            print("[Update Version] bVer berhasil diperbarui ke \(metadata.bVer ?? 0) untuk book \(metadata.bkid)")
            #endif
        }
    }

    func updateBookMetadata(_ metadata: BookMetadata) throws {
        try withMainDatabase { db in
            let sql = """
            UPDATE `0bok` SET 
                `cat` = ?, 
                `bk` = ?, 
                `Archive` = ?, 
                `betaka` = ?, 
                `authno` = ?, 
                `inf` = ?, 
                `TafseerNam` = ?, 
                `bVer` = ?, 
                `PdfCs` = ?
            WHERE `bkid` = ?;
            """
            try executeStatement(in: db, sql: sql) { stmt in
                bindCommonMetadataFields(metadata, to: stmt, startingAt: 1)
                sqlite3_bind_int64(stmt, 10, Int64(metadata.bkid))
            }
            #if DEBUG
            print("[Update Metadata] Metadata berhasil diperbarui untuk book \(metadata.bkid)")
            #endif
        }
    }

    private func bindOptionalText(_ stmt: OpaquePointer, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalInt(_ stmt: OpaquePointer, index: Int32, value: Int?) {
        if let value {
            sqlite3_bind_int64(stmt, index, Int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindCommonMetadataFields(_ metadata: BookMetadata, to stmt: OpaquePointer, startingAt base: Int32) {
        sqlite3_bind_int64(stmt, base, Int64(metadata.cat ?? 0))
        sqlite3_bind_text(stmt, base + 1, metadata.bk, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, base + 2, Int64(metadata.archive))
        sqlite3_bind_text(stmt, base + 3, metadata.betaka ?? "", -1, sqliteTransient)
        sqlite3_bind_int64(stmt, base + 4, Int64(metadata.authno ?? 0))
        sqlite3_bind_text(stmt, base + 5, metadata.inf ?? "", -1, sqliteTransient)
        bindOptionalText(stmt, index: base + 6, value: metadata.tafseerNam)
        bindOptionalInt(stmt, index: base + 7, value: metadata.bVer)
        bindOptionalInt(stmt, index: base + 8, value: metadata.pdfCs)
    }

    func bookExists(id: Int) throws -> Bool {
        DatabaseManager.shared.bookExists(id: id)
    }

    func bookNeedsUpdate(id: Int, newVersion: Int64) throws -> Bool {
        try withMainDatabase { db in
            guard let versionColumn = resolveVersionColumn(in: db) else {
                return true
            }

            let sql = "SELECT `\(versionColumn)` FROM `0bok` WHERE `bkid` = ? LIMIT 1;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return true
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, Int64(id))
            guard sqlite3_step(stmt) == SQLITE_ROW else { return true }

            if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return true }
            let currentVersion = sqlite3_column_int64(stmt, 0)
            return currentVersion != newVersion
        }
    }

    func ensureAuthor(
        authId: Int,
        downloadURL: URL,
        workingDirectory: URL,
        newVersion: Int64
    ) async throws {
        let needsUpdate = try withSpecialDatabase { specialDb in
            authorNeedsUpdate(authId: authId, newVersion: newVersion, in: specialDb)
        }
        guard needsUpdate else { return }

        let downloadedAuthURL = try await downloadFile(from: downloadURL, to: workingDirectory, SQLite: true)
        defer { FileManager.default.removeDatabaseAndSidecars(at: downloadedAuthURL) }

        let newAuthDb = try openDatabase(path: downloadedAuthURL.path)
        defer { sqlite3_close(newAuthDb) }

        guard let row = fetchAuthorRow(authId: authId, in: newAuthDb) else {
            throw NSError(domain: DatabaseError.authorNotFound(authId).localizedDescription, code: 1)
        }

        try withSpecialDatabase { specialDb in
            try insertAuthorRow(row, into: specialDb)
        }
    }

    func getAuthorVersion(authId: Int, in db: OpaquePointer) -> Int? {
        let sql = "SELECT oVer FROM Auth WHERE authid = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(authId))
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : nil
    }

    func authorNeedsUpdate(authId: Int, newVersion: Int64, in db: OpaquePointer) -> Bool {
        guard let currentVersion = getAuthorVersion(authId: authId, in: db) else { return true }
        return newVersion > currentVersion
    }

    func fetchAuthorRow(authId: Int, in db: OpaquePointer) -> [String: Any]? {
        let sql = "SELECT authid, auth, inf, Lng, HigriD, oVer FROM Auth WHERE authid = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(authId))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        return [
            "authid": Int(sqlite3_column_int64(stmt, 0)),
            "auth": columnText(stmt, index: 1),
            "inf": columnText(stmt, index: 2),
            "Lng": columnText(stmt, index: 3),
            "HigriD": columnText(stmt, index: 4),
            "oVer": Int(sqlite3_column_int64(stmt, 5)),
        ]
    }

    func insertAuthorRow(_ row: [String: Any], into db: OpaquePointer) throws {
        let sql = "INSERT INTO Auth (authid, auth, inf, Lng, HigriD, oVer) VALUES (?, ?, ?, ?, ?, ?);"
        let authId = row["authid"] as? Int ?? 0
        let authName = row["auth"] as? String ?? ""
        let authInf = row["inf"] as? String ?? ""
        let authLng = row["Lng"] as? String ?? ""
        let higriD = row["HigriD"] as? String ?? ""
        let oVer = Int64(row["oVer"] as? Int ?? 0)

        try executeStatement(in: db, sql: sql) { stmt in
            sqlite3_bind_int64(stmt, 1, Int64(authId))
            sqlite3_bind_text(stmt, 2, authName, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 3, authInf, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 4, authLng, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 5, higriD, -1, sqliteTransient)
            sqlite3_bind_int64(stmt, 6, oVer)
        }

        let muallif = Muallif(nama: authName, info: authInf, namaLengkap: authLng)
        LibraryDataManager.shared.updateAuthorInCache(id: authId, muallif: muallif)
    }
}
