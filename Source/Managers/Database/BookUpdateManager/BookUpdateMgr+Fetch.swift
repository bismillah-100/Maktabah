//
//  BookUpdateMgr+Fetch.swift
//  Maktabah
//
//  Created by MacBook on 06/02/26.
//

import Foundation
import SQLite3

extension BookUpdateManager {
    // MARK: - Fetch Available Updates (untuk UI)

    /// Mengambil daftar buku yang tersedia dengan informasi versi
    /// Digunakan untuk menampilkan daftar di UI sebelum download
    func fetchAvailableUpdates(
        from indexURL: URL
    ) async throws -> [BookUpdateItem] {
        #if DEBUG
        print("📋 [Fetch Updates] Loading available updates from CSV...")
        #endif

        let entries = try await fetchIndexEntries(from: indexURL)

        #if DEBUG
        print("📋 [Fetch Updates] Found \(entries.count) entries in CSV")
        #endif

        let items = entries.map { createUpdateItem(from: $0) }

        #if DEBUG
        let needsUpdateCount = items.reduce(into: 0) { count, item in
            if item.needsUpdate { count += 1 }
        }
        print("📋 [Fetch Updates] Processed \(items.count) books: \(needsUpdateCount) need update")
        #endif

        return items
    }

    private func createUpdateItem(from entry: BookIndexEntry) -> BookUpdateItem {
        let bookName = LibraryDataManager.shared.getBook([entry.bkid]).first?.book ?? entry.bk
        let versionState = (try? getBookVersionState(bookId: entry.bkid)) ?? .unknownVersion
        let currentVersion = versionState.currentVersion

        let item = BookUpdateItem(
            id: entry.bkid,
            bookName: bookName,
            category: entry.category,
            existsInLibrary: versionState.existsInLibrary,
            currentVersion: currentVersion,
            newVersion: entry.versionName,
            fileSize: entry.fileSize,
            downloadURL: entry.downloadURL
        )

        if item.newBook {
            item.status = .new
        } else if item.needsUpdate {
            item.status = .needsUpdate
        } else {
            item.status = .upToDate
        }

        #if DEBUG
        if item.needsUpdate {
            let currentVersionText = currentVersion.map(String.init) ?? (item.newBook ? "NEW" : "NULL")
            print("🔄 [Fetch Updates] Book \(entry.bkid) needs update: \(currentVersionText) → \(entry.versionName)")
        }
        #endif

        return item
    }

    private func getBookVersionState(bookId: Int) throws -> BookVersionState {
        guard let mainPath = AppConfig.mainDatabasePath else {
            return .unknownVersion
        }
        let db = try openDatabase(path: mainPath)
        defer { sqlite3_close_v2(db) }

        guard let versionColumn = resolveVersionColumn(in: db) else {
            return .unknownVersion
        }

        let sql =
            "SELECT `\(versionColumn)` FROM `0bok` WHERE `bkid` = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return .unknownVersion
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(bookId))

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return .notInLibrary
        }

        if sqlite3_column_type(stmt, 0) == SQLITE_NULL {
            return .unknownVersion
        }

        return .version(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Fetch data yang diperlukan dari internet.

    private func fetchCSVString(from url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let csv = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "CSV encoding tidak valid.",
                ]
            )
        }
        return csv
    }

    func fetchIndexEntries(from url: URL) async throws -> [BookIndexEntry] {
        let csv = try await fetchCSVString(from: url)
        return try parseIndexCSV(csv)
    }

    func fetchAuthIndexEntries(from url: URL) async throws -> [AuthIndexEntry] {
        let csv = try await fetchCSVString(from: url)
        return parseAuthIndexCSV(csv)
    }

    func fetchAuthIndexEntriesIfNeeded(from url: URL?) async throws -> [AuthIndexEntry] {
        guard let url else { return [] }
        return try await fetchAuthIndexEntries(from: url)
    }

    // MARK: - PARSE CSV

    func parseIndexCSV(_ csv: String) throws -> [BookIndexEntry] {
        let rows = CSVParser.parse(csv, separator: ";")
        guard !rows.isEmpty else { return [] }

        let dataRows = trimHeaderIfNeeded(rows, headerKey: "bkid")

        return dataRows.compactMap { columns in
            guard columns.count >= 5 else { return nil }
            guard let bkid = Int(columns[0]) else { return nil }
            guard let cat = Int(columns[1]) else { return nil }
            guard let versionName = Int64(columns[2]) else { return nil }
            let idFile = columns[3]
            let downloadURL = BookUpdateViewModel.driveLink + idFile
            guard let size = Int64(columns[4]) else { return nil }
            let bkName = columns[5]

            return BookIndexEntry(
                bkid: bkid,
                bk: bkName,
                category: cat,
                versionName: versionName,
                downloadURL: downloadURL,
                fileSize: size
            )
        }
    }

    func parseAuthIndexCSV(_ csv: String) -> [AuthIndexEntry] {
        let rows = CSVParser.parse(csv, separator: ";")
        guard !rows.isEmpty else { return [] }

        let dataRows = trimHeaderIfNeeded(rows, headerKey: "authid")

        return dataRows.compactMap { columns in
            guard columns.count >= 3 else { return nil }
            guard let authId = Int(columns[0]) else { return nil }
            guard let versionName = Int64(columns[1]) else { return nil }
            let idFile = columns[2]
            let downloadURL = BookUpdateViewModel.driveLink + idFile

            return AuthIndexEntry(
                authId: authId,
                versionName: versionName,
                downloadURL: downloadURL
            )
        }
    }

    func trimHeaderIfNeeded(_ rows: [[String]], headerKey: String) -> [[String]] {
        guard let first = rows.first, let firstCell = first.first else {
            return rows
        }
        if firstCell.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(headerKey) == .orderedSame
        {
            return Array(rows.dropFirst())
        }
        return rows
    }
}

private enum CSVParser {
    static func parse(_ csv: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false

        for char in csv {
            switch char {
            case "\"":
                insideQuotes.toggle()
            case separator:
                if insideQuotes {
                    currentField.append(char)
                } else {
                    currentRow.append(currentField)
                    currentField = ""
                }
            case "\n":
                if insideQuotes {
                    currentField.append(char)
                } else {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                }
            case "\r":
                continue
            default:
                currentField.append(char)
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }
}
