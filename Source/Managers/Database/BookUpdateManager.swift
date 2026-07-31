//
//  BookUpdateManager.swift
//  Maktabah
//
//  Created by MacBook on 06/02/26.
//

import Foundation
import SQLite3

final class BookUpdateManager {
    static let shared = BookUpdateManager()

    private let versionColumnCandidates = [
        "bver", "bVer",
    ]
    private var cachedVersionColumn: String?
    private let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private init() {}

    struct StagedBookUpdate {
        let entry: BookIndexEntry
        let metadata: BookMetadata
        let downloadedBookURL: URL
        let ftsSourceURL: URL
        let authorContext: AuthorContext?
        let workingDirectory: URL
    }

    struct AuthorContext {
        let authId: Int
        let versionName: Int64
        let downloadURL: URL
    }

    private enum BookVersionState {
        case notInLibrary
        case unknownVersion
        case version(Int64)

        var existsInLibrary: Bool {
            switch self {
            case .notInLibrary:
                return false
            case .unknownVersion, .version:
                return true
            }
        }

        var currentVersion: Int64? {
            switch self {
            case .version(let value):
                return value
            case .notInLibrary, .unknownVersion:
                return nil
            }
        }
    }

    // MARK: - Fetch Available Updates (untuk UI)

    /// Mengambil daftar buku yang tersedia dengan informasi versi
    /// Digunakan untuk menampilkan daftar di UI sebelum download
    func fetchAvailableUpdates(
        from indexURL: URL
    ) async throws -> [BookUpdateItem] {

        #if DEBUG
            print("📋 [Fetch Updates] Loading available updates from CSV...")
        #endif

        // Download CSV
        let entries = try await fetchIndexEntries(from: indexURL)

        #if DEBUG
            print("📋 [Fetch Updates] Found \(entries.count) entries in CSV")
        #endif

        // Convert ke BookUpdateItem dengan informasi dari database
        var items: [BookUpdateItem] = []

        for entry in entries {
            // Ambil nama buku dari LibraryDataManager
            let bookName =
            LibraryDataManager.shared.getBook([entry.bkid]).first?.book
                ?? entry.bk

            // Periksa status versi saat ini di database
            let versionState = (try? getBookVersionState(bookId: entry.bkid))
                ?? .unknownVersion
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

            // Set status awal
            if item.newBook {
                item.status = .new
            } else if item.needsUpdate {
                item.status = .needsUpdate
            } else {
                item.status = .upToDate
            }

            items.append(item)

            #if DEBUG
                if item.needsUpdate {
                    let currentVersionText = currentVersion.map(String.init) ??
                        (item.newBook ? "NEW" : "NULL")
                    print(
                        "🔄 [Fetch Updates] Book \(entry.bkid) needs update: \(currentVersionText) → \(entry.versionName)"
                    )
                }
            #endif
        }

        #if DEBUG
            let needsUpdateCount = items.reduce(into: 0) { count, item in
                if item.needsUpdate { count += 1 }
            }
            print(
                "✅ [Fetch Updates] Loaded \(items.count) books, \(needsUpdateCount) need updates"
            )
        #endif

        return items
    }

    private func getBookVersionState(bookId: Int) throws -> BookVersionState {
        guard let mainPath = AppConfig.mainDatabasePath else {
            return .unknownVersion
        }
        let db = try openDatabase(path: mainPath)
        defer { sqlite3_close(db) }

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

    func fetchIndexEntries(from url: URL) async throws -> [BookIndexEntry] {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let csv = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "CSV encoding tidak valid."
                ]
            )
        }
        return try parseIndexCSV(csv)
    }

    func fetchAuthIndexEntries(from url: URL) async throws -> [AuthIndexEntry] {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let csv = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "CSV encoding tidak valid."
                ]
            )
        }
        return parseAuthIndexCSV(csv)
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

    func stageBookDownload(
        _ entry: BookIndexEntry,
        authIndex: [Int: AuthIndexEntry]
    ) async throws -> StagedBookUpdate {
        guard
            let downloadURL = URL(
                string: entry.downloadURL
            )
        else {
            throw NSError(
                domain: "BookUpdate",
                code: -8,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Download URL metadata tidak valid untuk buku \(entry.bkid)."
                ]
            )
        }

        let workingDirectory = try makeWorkingDirectory()
        let downloadedMetadataURL = try await downloadFile(
            from: downloadURL,
            to: workingDirectory,
            SQLite: true,
            filePrefix: "metadata_\(entry.bkid)"
        )

        defer {
            try? FileManager.default.removeItem(at: downloadedMetadataURL)
        }

        guard
            let metadata = try readBookMetadata(
                from: downloadedMetadataURL,
                fallbackBookId: entry.bkid
            )
        else {
            throw NSError(
                domain: "BookUpdate",
                code: -6,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Metadata kitab tidak ditemukan di book sqlite."
                ]
            )
        }

        guard let link = metadata.link,
            let bookURL = URL(
                string: BookUpdateViewModel.driveLink + link
            )
        else {
            throw NSError(
                domain: "BookUpdate",
                code: -9,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Link download buku tidak tersedia untuk buku \(entry.bkid)."
                ]
            )
        }

        let newWorkingDirectory = try makeWorkingDirectory()
        let downloadedBookURL = try await downloadFile(
            from: bookURL,
            to: newWorkingDirectory,
            SQLite: true,
            filePrefix: "book_\(metadata.bkid)"
        )

        let ftsSourceURL = newWorkingDirectory.appendingPathComponent(
            "b\(metadata.bkid)_fts_source_\(UUID().uuidString).sqlite"
        )
        do {
            if FileManager.default.fileExists(atPath: ftsSourceURL.path) {
                try FileManager.default.removeItem(at: ftsSourceURL)
            }
            try FileManager.default.copyItem(at: downloadedBookURL, to: ftsSourceURL)
        } catch {
            try? FileManager.default.removeItem(at: ftsSourceURL)
            try? FileManager.default.removeItem(at: downloadedBookURL)
            throw error
        }

        var authorContext: AuthorContext?
        if let authId = metadata.authno, let authEntry = authIndex[authId],
            let authDownloadURL = URL(string: authEntry.downloadURL)
        {
            authorContext = AuthorContext(
                authId: authId,
                versionName: authEntry.versionName,
                downloadURL: authDownloadURL
            )
        }

        return StagedBookUpdate(
            entry: entry,
            metadata: metadata,
            downloadedBookURL: downloadedBookURL,
            ftsSourceURL: ftsSourceURL,
            authorContext: authorContext,
            workingDirectory: workingDirectory
        )
    }

    func importOfflineUpdate(
        from url: URL,
        providedMetadata: BookMetadata? = nil,
        authorRow: [String: Any]? = nil
    ) async throws -> BookUpdateResult {
        let metadata: BookMetadata
        if let provided = providedMetadata {
            metadata = provided
        } else {
            guard let readMeta = try readBookMetadata(from: url, fallbackBookId: 0) else {
                throw NSError(
                    domain: "BookUpdate",
                    code: -6,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Metadata kitab (tabel main_update) tidak ditemukan di file sqlite tersebut."
                    ]
                )
            }
            metadata = readMeta
        }

        return try await executeOfflineImport(url: url, metadata: metadata, authorRow: authorRow)
    }

    private func executeOfflineImport(
        url: URL,
        metadata: BookMetadata,
        authorRow: [String: Any]?
    ) async throws -> BookUpdateResult {
        // 1. Langsung buat tabel di arsip target di awal sesuai permintaan user
        try preCreateArchiveTables(archiveId: metadata.archive, bookId: metadata.bkid)

        let workingDirectory = try makeWorkingDirectory()

        let downloadedBookURL = workingDirectory.appendingPathComponent(
            "book_\(metadata.bkid)_\(UUID().uuidString).sqlite"
        )
        try FileManager.default.copyItem(at: url, to: downloadedBookURL)

        let ftsSourceURL = workingDirectory.appendingPathComponent(
            "b\(metadata.bkid)_fts_source_\(UUID().uuidString).sqlite"
        )
        try FileManager.default.copyItem(at: url, to: ftsSourceURL)

        #if DEBUG
            print("[Import] Initial: \(listAllTables(at: downloadedBookURL))")
        #endif

        try renameTablesIfNeeded(at: downloadedBookURL, to: metadata.bkid)
        try renameTablesIfNeeded(at: ftsSourceURL, to: metadata.bkid)

        let entry = BookIndexEntry(
            bkid: metadata.bkid,
            bk: metadata.bk,
            category: metadata.cat ?? 0,
            versionName: Int64(metadata.bVer ?? 0),
            downloadURL: "",
            fileSize: 0
        )

        // Handle custom author row insertion if needed
        if let authorRow = authorRow, let specialPath = AppConfig.specialDatabasePath {
            do {
                let specialDb = try openDatabase(path: specialPath)
                defer { sqlite3_close(specialDb) }
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

        let exists = try bookExists(id: metadata.bkid)

        try convertBookDatabase(
            at: downloadedBookURL,
            bookId: metadata.bkid
        )

        try replaceArchiveDatabase(
            with: downloadedBookURL,
            archiveId: metadata.archive,
            bookId: metadata.bkid,
            ftsSourceURL: ftsSourceURL
        )

        if !exists {
            try insertBookMetadata(metadata)
        } else {
            try updateBookMetadata(metadata)
        }

        // Cleanup
        try? FileManager.default.removeItem(at: downloadedBookURL)
        try? FileManager.default.removeItem(at: ftsSourceURL)

        return BookUpdateResult(
            bookId: metadata.bkid,
            catId: entry.category,
            action: exists ? .updated : .inserted
        )
    }

    private func preCreateArchiveTables(archiveId: Int, bookId: Int) throws {
        guard let targetPath = AppConfig.archiveDatabasePath(archiveId: archiveId) else { return }

        // Membuka database arsip (misal 20.sqlite)
        var db: OpaquePointer?
        guard sqlite3_open_v2(targetPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return
        }
        defer { sqlite3_close(db) }

        #if DEBUG
            print("[Import] Pre-creating tables in archive \(archiveId)...")
        #endif

        let schema = "(nass BLOB, part INTEGER, id INTEGER, page INTEGER)"
        try exec(db, "CREATE TABLE IF NOT EXISTS \"b\(bookId)\" \(schema);")
        try exec(db, "CREATE TABLE IF NOT EXISTS \"t\(bookId)\" \(schema);")
    }

    #if DEBUG
    private func listAllTables(at url: URL) -> [String] {
        guard let db = try? openDatabase(path: url.path) else { return [] }
        defer { sqlite3_close(db) }
        var objects: [String] = []
        let sql = "SELECT name FROM sqlite_master WHERE type IN ('table', 'view');"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 0) {
                    let bytes = sqlite3_column_bytes(stmt, 0)
                    let buffer = UnsafeBufferPointer(start: name, count: Int(bytes))
                    objects.append(String(decoding: buffer, as: UTF8.self))
                }
            }
        }
        sqlite3_finalize(stmt)
        return objects
    }
    #endif

    @MainActor
    func integrateBooks(metadata: BookMetadata) {
        // Mark as integrated since the tables are already copied to the archive
        IntegrationCache.shared.markIntegrated(
            bookId: metadata.bkid,
            archiveId: metadata.archive
        )

        NotificationCenter.default.post(
            name: .bookIntegrated,
            object: metadata.bkid
        )
    }

    func applyStagedBookUpdate(
        _ stagedUpdate: StagedBookUpdate,
        knownExists: Bool? = nil
    ) async throws -> BookUpdateResult {
        defer {
            try? FileManager.default.removeItem(at: stagedUpdate.ftsSourceURL)
            try? FileManager.default.removeItem(at: stagedUpdate.downloadedBookURL)
        }

        let exists: Bool
        if let knownExists {
            exists = knownExists
        } else {
            exists = try bookExists(id: stagedUpdate.metadata.bkid)
        }
        let needsUpdate = try bookNeedsUpdate(
            id: stagedUpdate.metadata.bkid,
            newVersion: stagedUpdate.entry.versionName
        )

        if exists, !needsUpdate {
            return BookUpdateResult(
                bookId: stagedUpdate.metadata.bkid,
                catId: stagedUpdate.entry.category,
                action: .skipped
            )
        }

        if let authorContext = stagedUpdate.authorContext {
            try await ensureAuthor(
                authId: authorContext.authId,
                downloadURL: authorContext.downloadURL,
                workingDirectory: stagedUpdate.workingDirectory,
                newVersion: authorContext.versionName
            )
        }

        try convertBookDatabase(
            at: stagedUpdate.downloadedBookURL,
            bookId: stagedUpdate.metadata.bkid
        )
        try replaceArchiveDatabase(
            with: stagedUpdate.downloadedBookURL,
            archiveId: stagedUpdate.metadata.archive,
            bookId: stagedUpdate.metadata.bkid,
            ftsSourceURL: stagedUpdate.ftsSourceURL
        )

        if !exists {
            try insertBookMetadata(stagedUpdate.metadata)
        } else {
            try updateBookVersion(stagedUpdate.metadata)
        }

        return BookUpdateResult(
            bookId: stagedUpdate.metadata.bkid,
            catId: stagedUpdate.entry.category,
            action: exists ? .updated : .inserted
        )
    }

    private func bookExists(id: Int) throws -> Bool {
        return DatabaseManager.shared.bookExists(id: id)
    }

    private func bookNeedsUpdate(id: Int, newVersion: Int64) throws -> Bool {
        guard let mainPath = AppConfig.mainDatabasePath else {
            #if DEBUG
                print("⚠️ [Update Check] basePath is nil")
            #endif
            return false
        }

        #if DEBUG
            print(
                "🔍 [Update Check] Checking book \(id) with new version: \(newVersion)"
            )
        #endif

        let db = try openDatabase(path: mainPath)
        defer { sqlite3_close(db) }

        guard let versionColumn = resolveVersionColumn(in: db) else {
            #if DEBUG
                print(
                    "⚠️ [Update Check] Version column not found, assuming update needed for book \(id)"
                )
            #endif
            return true
        }

        // Coba dengan backticks untuk nama tabel yang dimulai dengan angka
        let sql =
            "SELECT `\(versionColumn)` FROM `0bok` WHERE `bkid` = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            #if DEBUG
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print(
                    "⚠️ [Update Check] Failed to prepare SELECT statement for book \(id)"
                )
                print("❌ SQL Error: \(errorMsg)")
                print("❌ SQL: \(sql)")
            #endif
            return true
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(id))

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            #if DEBUG
                print(
                    "📭 [Update Check] Book \(id) not found in database, needs insert"
                )
            #endif
            return true
        }

        // Cek apakah kolom NULL
        if sqlite3_column_type(stmt, 0) == SQLITE_NULL {
            #if DEBUG
                print(
                    "🆕 [Update Check] Book \(id) has NULL version, needs update to: \(newVersion)"
                )
            #endif
            return true
        }

        // Ambil nilai INTEGER sebagai Int64
        let currentVersion = sqlite3_column_int64(stmt, 0)
        let needsUpdate = currentVersion != newVersion

        #if DEBUG
            if needsUpdate {
                print(
                    "🔄 [Update Check] Book \(id) needs update: \(currentVersion) → \(newVersion)"
                )
            } else {
                print(
                    "⏭️ [Update Check] Book \(id) is already version \(currentVersion), skipping download"
                )
            }
        #endif

        return needsUpdate
    }

    private func insertBookMetadata(_ metadata: BookMetadata) throws {
        guard let mainPath = AppConfig.mainDatabasePath else { return }

        var db: OpaquePointer?
        guard
            sqlite3_open_v2(
                mainPath,
                &db,
                SQLITE_OPEN_READWRITE,
                nil
            ) == SQLITE_OK,
            let db
        else {
            let message =
            db.map { String(cString: sqlite3_errmsg($0)) }
            ?? "Failed to open main.sqlite"
            sqlite3_close(db)
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO `0bok` (`bkid`, `cat`, `bk`, `Archive`, `betaka`, `authno`, `inf`, `TafseerNam`, `bVer`, `PdfCs`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
                ]
            )
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(metadata.bkid))
        sqlite3_bind_int64(stmt, 2, Int64(metadata.cat ?? 0))
        sqlite3_bind_text(stmt, 3, metadata.bk, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 4, Int64(metadata.archive))
        sqlite3_bind_text(stmt, 5, metadata.betaka ?? "", -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 6, Int64(metadata.authno ?? 0))
        sqlite3_bind_text(stmt, 7, metadata.inf ?? "", -1, sqliteTransient)
        if let tafseerNam = metadata.tafseerNam {
            sqlite3_bind_text(stmt, 8, tafseerNam, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        if let bVer = metadata.bVer {
            sqlite3_bind_int64(stmt, 9, Int64(bVer))
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        if let pdfCs = metadata.pdfCs {
            sqlite3_bind_int64(stmt, 10, Int64(pdfCs))
        } else {
            sqlite3_bind_null(stmt, 10)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
                ]
            )
        }
    }

    private func updateBookVersion(_ metadata: BookMetadata) throws {
        guard let mainPath = AppConfig.mainDatabasePath else { return }

        var db: OpaquePointer?
        guard
            sqlite3_open_v2(
                mainPath,
                &db,
                SQLITE_OPEN_READWRITE,
                nil
            ) == SQLITE_OK,
            let db
        else {
            let message =
            db.map { String(cString: sqlite3_errmsg($0)) }
            ?? "Failed to open main.sqlite"
            sqlite3_close(db)
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        defer { sqlite3_close(db) }

        let sql = "UPDATE `0bok` SET `bVer` = ? WHERE `bkid` = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
                ]
            )
        }
        defer { sqlite3_finalize(stmt) }

        if let bVer = metadata.bVer {
            sqlite3_bind_int64(stmt, 1, Int64(bVer))
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_int64(stmt, 2, Int64(metadata.bkid))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
                ]
            )
        }
        #if DEBUG
            print("[Update Version] bVer berhasil diperbarui ke \(metadata.bVer ?? 0) untuk book \(metadata.bkid)")
        #endif
    }

    private func updateBookMetadata(_ metadata: BookMetadata) throws {
        guard let mainPath = AppConfig.mainDatabasePath else { return }

        var db: OpaquePointer?
        guard
            sqlite3_open_v2(
                mainPath,
                &db,
                SQLITE_OPEN_READWRITE,
                nil
            ) == SQLITE_OK,
            let db
        else {
            let message =
            db.map { String(cString: sqlite3_errmsg($0)) }
            ?? "Failed to open main.sqlite"
            sqlite3_close(db)
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        defer { sqlite3_close(db) }

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
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
                ]
            )
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(metadata.cat ?? 0))
        sqlite3_bind_text(stmt, 2, metadata.bk, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 3, Int64(metadata.archive))
        sqlite3_bind_text(stmt, 4, metadata.betaka ?? "", -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 5, Int64(metadata.authno ?? 0))
        sqlite3_bind_text(stmt, 6, metadata.inf ?? "", -1, sqliteTransient)
        if let tafseerNam = metadata.tafseerNam {
            sqlite3_bind_text(stmt, 7, tafseerNam, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        if let bVer = metadata.bVer {
            sqlite3_bind_int64(stmt, 8, Int64(bVer))
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        if let pdfCs = metadata.pdfCs {
            sqlite3_bind_int64(stmt, 9, Int64(pdfCs))
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        sqlite3_bind_int64(stmt, 10, Int64(metadata.bkid))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(
                domain: "BookUpdate",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
                ]
            )
        }
        #if DEBUG
            print("[Update Metadata] Metadata berhasil diperbarui untuk book \(metadata.bkid)")
        #endif
    }

    func changeBookId(oldId: Int, newId: Int) throws {
        guard let mainPath = AppConfig.mainDatabasePath else { return }

        let db = try openDatabase(path: mainPath)
        defer { sqlite3_close(db) }

        // Step 0: Ambil archiveId dari main DB
        var archiveId: Int = 20
        let selectSql = "SELECT `Archive` FROM `0bok` WHERE `bkid` = ? LIMIT 1;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, selectSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(oldId))
            if sqlite3_step(stmt) == SQLITE_ROW {
                archiveId = Int(sqlite3_column_int64(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)

        let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId)
        let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)

        // Phase 1: Rename tabel archive DULU (sebelum main DB disentuh).
        if let archivePath {
            let archiveDb = try openDatabase(path: archivePath)
            defer { sqlite3_close(archiveDb) }

            // Tambahan Proteksi: Hapus tabel atau indeks target lama jika sudah ada
            // untuk menghindari bentrok nama (Error: table or index already exists)
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
                // Rollback: kembalikan b rename
                _ = sqlite3_exec(archiveDb,
                    "ALTER TABLE \"b\(newId)\" RENAME TO \"b\(oldId)\";", nil, nil, nil)
                throw NSError(
                    domain: "BookUpdate", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Gagal rename tabel t\(oldId) di archive."]
                )
            }
        }

        // Phase 2: Rename tabel FTS.
        if let ftsPath {
            let ftsDb = try openDatabase(path: ftsPath)
            defer { sqlite3_close(ftsDb) }

            // Tambahan Proteksi: Hapus tabel FTS target lama jika ada
            _ = sqlite3_exec(ftsDb, "DROP TABLE IF EXISTS \"b\(newId)_fts\";", nil, nil, nil)

            let sqlFTS = "ALTER TABLE \"b\(oldId)_fts\" RENAME TO \"b\(newId)_fts\";"
            if sqlite3_exec(ftsDb, sqlFTS, nil, nil, nil) != SQLITE_OK {
                rollbackBookIdRenames(archivePath: archivePath, ftsPath: nil,
                                      oldId: oldId, newId: newId)
                throw NSError(
                    domain: "BookUpdate", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Gagal rename tabel FTS b\(oldId)_fts."]
                )
            }
        }

        // Phase 3: Update main DB TERAKHIR.
        // Tambahan Proteksi: Hapus baris dengan newId di main DB jika sudah ada.
        // Ini krusial agar query UPDATE di bawah tidak melanggar constraint PRIMARY KEY atau UNIQUE pada `0bok`.
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
            rollbackBookIdRenames(archivePath: archivePath, ftsPath: ftsPath,
                                  oldId: oldId, newId: newId)
            throw NSError(
                domain: "BookUpdate", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Gagal prepare update bkid di main database."]
            )
        }
        sqlite3_bind_int64(updateStmt, 1, Int64(newId))
        sqlite3_bind_int64(updateStmt, 2, Int64(oldId))
        let stepResult = sqlite3_step(updateStmt)
        sqlite3_finalize(updateStmt)

        if stepResult != SQLITE_DONE {
            rollbackBookIdRenames(archivePath: archivePath, ftsPath: ftsPath,
                                  oldId: oldId, newId: newId)
            throw NSError(
                domain: "BookUpdate", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Gagal update bkid di main database."]
            )
        }
    }

    /// Compensating rollback: kembalikan semua rename tabel ke nama semula.
    /// Dipanggil jika Phase 3 (update main DB) gagal.
    private func rollbackBookIdRenames(
        archivePath: String?,
        ftsPath: String?,
        oldId: Int,
        newId: Int
    ) {
        if let archivePath, let archiveDb = try? openDatabase(path: archivePath) {
            defer { sqlite3_close(archiveDb) }
            _ = sqlite3_exec(archiveDb,
                "ALTER TABLE \"b\(newId)\" RENAME TO \"b\(oldId)\";", nil, nil, nil)
            _ = sqlite3_exec(archiveDb,
                "ALTER TABLE \"t\(newId)\" RENAME TO \"t\(oldId)\";", nil, nil, nil)
        }
        if let ftsPath, let ftsDb = try? openDatabase(path: ftsPath) {
            defer { sqlite3_close(ftsDb) }
            _ = sqlite3_exec(ftsDb,
                "ALTER TABLE \"b\(newId)_fts\" RENAME TO \"b\(oldId)_fts\";", nil, nil, nil)
        }
    }

    private func ensureAuthor(
        authId: Int,
        downloadURL: URL,
        workingDirectory: URL,
        newVersion: Int64
    ) async throws {
        guard let specialPath = AppConfig.specialDatabasePath else { return }

        let specialDb = try openDatabase(path: specialPath)
        defer { sqlite3_close(specialDb) }

        if !authorNeedsUpdate(
            authId: authId,
            newVersion: newVersion,
            in: specialDb
        ) {
            return  // Skip jika versi sudah up-to-date
        }

        let downloadedAuthURL = try await downloadFile(
            from: downloadURL,
            to: workingDirectory,
            SQLite: true
        )
        defer {
            try? FileManager.default.removeItem(at: downloadedAuthURL)
        }

        let newAuthDb = try openDatabase(path: downloadedAuthURL.path)
        defer { sqlite3_close(newAuthDb) }

        guard let row = fetchAuthorRow(authId: authId, in: newAuthDb) else {
            throw NSError(
                domain: DatabaseError.authorNotFound(authId)
                    .localizedDescription,
                code: 1
            )
        }

        try insertAuthorRow(row, into: specialDb)
    }

    func fetchAuthIndexEntriesIfNeeded(from url: URL?) async throws
        -> [AuthIndexEntry]
    {
        guard let url else { return [] }
        return try await fetchAuthIndexEntries(from: url)
    }

    private func trimHeaderIfNeeded(_ rows: [[String]], headerKey: String)
        -> [[String]]
    {
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

    private func readBookMetadata(from url: URL, fallbackBookId: Int) throws
        -> BookMetadata?
    {
        #if DEBUG
            print("url:", url.absoluteString)
        #endif

        let db = try openDatabase(path: url.path)
        defer { sqlite3_close(db) }

        let sql = """
            SELECT bkid, bk, cat, betaka, inf, authno, archive, TafseerNam, bVer, link, PdfCs
            FROM main_update
            WHERE bkid = ? LIMIT 1;
            """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            // Fallback if PdfCs column is missing
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
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

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

    private func getAuthorVersion(
        authId: Int,
        in db: OpaquePointer
    ) -> Int? {
        let sql = "SELECT oVer FROM Auth WHERE authid = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(authId))

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return nil
    }

    // Untuk cek apakah perlu update:
    private func authorNeedsUpdate(
        authId: Int,
        newVersion: Int64,
        in db: OpaquePointer
    ) -> Bool {
        guard let currentVersion = getAuthorVersion(authId: authId, in: db)
        else {
            return true  // Author belum ada, perlu insert
        }
        return newVersion > currentVersion  // Update jika versi baru lebih tinggi
    }

    private func fetchAuthorRow(authId: Int, in db: OpaquePointer) -> [String:
        Any]?
    {
        let sql = """
            SELECT authid, auth, inf, Lng, HigriD, oVer
            FROM Auth
            WHERE authid = ? LIMIT 1;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(authId))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let authIdValue = Int(sqlite3_column_int64(stmt, 0))
        let authName = columnText(stmt, index: 1)
        let authInf = columnText(stmt, index: 2)
        let authLng = columnText(stmt, index: 3)
        let authHigri = columnText(stmt, index: 4)
        let oVer = Int(sqlite3_column_int64(stmt, 5))

        return [
            "authid": authIdValue,
            "auth": authName,
            "inf": authInf,
            "Lng": authLng,
            "HigriD": authHigri,
            "oVer": oVer,
        ]
    }

    private func insertAuthorRow(_ row: [String: Any], into db: OpaquePointer)
        throws
    {
        let sql = """
            INSERT INTO Auth (authid, auth, inf, Lng, HigriD, oVer)
            VALUES (?, ?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(db, message: "Gagal prepare insert Auth.")
        }
        defer { sqlite3_finalize(stmt) }

        let authId = row["authid"] as? Int ?? 0
        let authName = row["auth"] as? String ?? ""
        let authInf = row["inf"] as? String ?? ""
        let authLng = row["Lng"] as? String ?? ""

        sqlite3_bind_int64(stmt, 1, Int64(authId))
        sqlite3_bind_text(
            stmt,
            2,
            authName,
            -1,
            sqliteTransient
        )
        sqlite3_bind_text(
            stmt,
            3,
            authInf,
            -1,
            sqliteTransient
        )
        sqlite3_bind_text(
            stmt,
            4,
            authLng,
            -1,
            sqliteTransient
        )
        sqlite3_bind_text(
            stmt,
            5,
            (row["HigriD"] as? String ?? ""),
            -1,
            sqliteTransient
        )
        sqlite3_bind_int64(
            stmt,
            6,
            Int64(row["oVer"] as? Int ?? 0)
        )

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw sqliteError(db, message: "Gagal insert Auth.")
        }

        // Sync with LibraryDataManager cache
        let muallif = Muallif(nama: authName, info: authInf, namaLengkap: authLng)
        LibraryDataManager.shared.updateAuthorInCache(id: authId, muallif: muallif)
    }

    func convertBookDatabase(at url: URL, bookId: Int) throws {
        let db = try openDatabase(path: url.path)
        defer { sqlite3_close(db) }

        let tableName = "b\(bookId)"
        let tempTable = "\(tableName)_zstd"
        let columns = try ArchiveDatabaseTools.loadTableColumns(
            tableName: tableName,
            db: db
        )

        if columns.isEmpty {
            throw sqliteError(db, message: "Tabel \(tableName) tidak ditemukan di file sumber.")
        }

        try withTransaction(db) {
            try exec(db, "DROP TABLE IF EXISTS \(tempTable);")
            let createSQL = ArchiveDatabaseTools.makeCreateTableSQL(
                tableName: tempTable,
                columns: columns
            )
            try exec(db, createSQL)

            let columnNames = columns.map { $0.name }
            let selectSQL =
                "SELECT \(columnNames.joined(separator: ", ")) FROM \(tableName);"
            let insertSQL =
                "INSERT INTO \(tempTable) (\(columnNames.joined(separator: ", "))) VALUES (\(columnNames.map { _ in "?" }.joined(separator: ", ")));"

            var selectStmt: OpaquePointer?
            var insertStmt: OpaquePointer?

            guard
                sqlite3_prepare_v2(
                    db,
                    selectSQL,
                    -1,
                    &selectStmt,
                    nil
                ) == SQLITE_OK
            else {
                throw sqliteError(db, message: "Gagal prepare SELECT konversi.")
            }
            defer { sqlite3_finalize(selectStmt) }

            guard
                sqlite3_prepare_v2(
                    db,
                    insertSQL,
                    -1,
                    &insertStmt,
                    nil
                ) == SQLITE_OK
            else {
                throw sqliteError(db, message: "Gagal prepare INSERT konversi.")
            }
            defer { sqlite3_finalize(insertStmt) }

            while sqlite3_step(selectStmt) == SQLITE_ROW {
                sqlite3_reset(insertStmt)

                for (index, column) in columns.enumerated() {
                    let colIndex = Int32(index)
                    if column.name.lowercased() == "nass" {
                        if let textPtr = sqlite3_column_text(selectStmt, colIndex)
                        {
                            let bytes = sqlite3_column_bytes(selectStmt, colIndex)
                            let buffer = UnsafeBufferPointer(start: textPtr, count: Int(bytes))
                            let text = String(decoding: buffer, as: UTF8.self)
                            if let compressed = ReusableFunc.compressData(text) {
                                _ = compressed.withUnsafeBytes { bytes in
                                    sqlite3_bind_blob(
                                        insertStmt,
                                        colIndex + 1,
                                        bytes.baseAddress,
                                        Int32(compressed.count),
                                        sqliteTransient
                                    )
                                }
                            } else {
                                sqlite3_bind_null(insertStmt, colIndex + 1)
                            }
                        } else {
                            sqlite3_bind_null(insertStmt, colIndex + 1)
                        }
                    } else {
                        if let selectStmt, let insertStmt {
                            bindColumnValue(
                                from: selectStmt,
                                to: insertStmt,
                                columnIndex: colIndex
                            )
                        }
                    }
                }

                if sqlite3_step(insertStmt) != SQLITE_DONE {
                    throw sqliteError(db, message: "Gagal insert konversi.")
                }
            }

            try exec(db, "DROP TABLE \(tableName);")
            try exec(db, "ALTER TABLE \(tempTable) RENAME TO \(tableName);")
        }
    }

    private func renameTablesIfNeeded(at url: URL, to targetId: Int) throws {
        let db = try openDatabase(path: url.path)
        defer { sqlite3_close(db) }

        let targetBTable = "b\(targetId)"
        let targetTTable = "t\(targetId)"

        var existingBTable: String? = nil
        var existingTTable: String? = nil

        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE '%_fts%' AND name NOT LIKE '%_zstd%';"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            var bCandidates: [String] = []
            var tCandidates: [String] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 0) {
                    let bytes = sqlite3_column_bytes(stmt, 0)
                    let buffer = UnsafeBufferPointer(start: name, count: Int(bytes))
                    let tableName = String(decoding: buffer, as: UTF8.self)
                    if tableName.hasPrefix("b") {
                        bCandidates.append(tableName)
                    } else if tableName.hasPrefix("t") {
                        tCandidates.append(tableName)
                    }
                }
            }
            sqlite3_finalize(stmt)

            // Prefer b<numbers>, then 'b', then any b*
            existingBTable = bCandidates.first(where: { $0.dropFirst().allSatisfy({ $0.isNumber }) && !$0.dropFirst().isEmpty })
                ?? bCandidates.first(where: { $0 == "b" })
                ?? bCandidates.first

            // Prefer t<numbers>, then 't', then any t*
            existingTTable = tCandidates.first(where: { $0.dropFirst().allSatisfy({ $0.isNumber }) && !$0.dropFirst().isEmpty })
                ?? tCandidates.first(where: { $0 == "t" })
                ?? tCandidates.first
        } else {
            sqlite3_finalize(stmt)
        }

        if let existingB = existingBTable, existingB != targetBTable {
            try exec(db, "ALTER TABLE \"\(existingB)\" RENAME TO \"\(targetBTable)\";")
        }

        if let existingT = existingTTable, existingT != targetTTable {
            try exec(db, "ALTER TABLE \"\(existingT)\" RENAME TO \"\(targetTTable)\";")
        }
    }

    private func replaceArchiveDatabase(
        with sourceURL: URL,
        archiveId: Int,
        bookId: Int,
        ftsSourceURL: URL
    ) throws {
        guard let targetPath = AppConfig.archiveDatabasePath(archiveId: archiveId),
              let ftsDBPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
        else { return }
        let db = try openDatabase(path: targetPath)
        defer { sqlite3_close(db) }

        try exec(db, "ATTACH DATABASE '\(sourceURL.path)' AS source_db;")
        try exec(
            db,
            "ATTACH DATABASE '\(ftsSourceURL.path)' AS fts_source_db;"
        )
        try exec(db, "ATTACH DATABASE '\(ftsDBPath)' AS fts_db;")
        defer {
            try? exec(db, "DETACH DATABASE fts_db;")
            try? exec(db, "DETACH DATABASE fts_source_db;")
            try? exec(db, "DETACH DATABASE source_db;")
        }

        try withTransaction(db) {
            let tableName = "b\(bookId)"
            let ftsTable = "\(tableName)_fts"
            try ArchiveDatabaseTools.replaceTable(
                db: db,
                tableName: tableName,
                sourceSchema: "source_db"
            )

            try ArchiveDatabaseTools.replaceTable(
                db: db,
                tableName: "t\(bookId)",
                sourceSchema: "source_db"
            )

            try ArchiveDatabaseTools.buildFTS(
                db: db,
                ftsSchema: "fts_db",
                ftsTable: ftsTable,
                sourceSchema: "fts_source_db",
                sourceTable: tableName
            )
        }

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

    private func makeWorkingDirectory() throws -> URL {
        guard let filesPath = AppConfig.databaseFilesPath else {
            throw NSError(
                domain: "BookUpdate",
                code: -4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Base path tidak tersedia."
                ]
            )
        }

        let directory = URL(fileURLWithPath: filesPath)
            .appendingPathComponent("Updates", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        return directory
    }

    private func downloadFile(
        from url: URL,
        to directory: URL,
        SQLite: Bool = false,
        filePrefix: String? = nil
    ) async throws
        -> URL
    {
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        let defaultName =
            url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let cleanedPrefix = filePrefix?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let nameSeed = cleanedPrefix.flatMap { $0.isEmpty ? nil : $0 } ?? defaultName
        var destination = directory.appendingPathComponent(
            "\(nameSeed)_\(UUID().uuidString)"
        )

        if SQLite {
            destination.appendPathExtension("sqlite")
        }

        #if DEBUG
            print("destination:", destination)
        #endif

        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    private func resolveVersionColumn(in db: OpaquePointer) -> String? {
        if let cachedVersionColumn {
            #if DEBUG
                print(
                    "📦 [Version] Using cached version column: \(cachedVersionColumn)"
                )
            #endif
            return cachedVersionColumn
        }

        let sql = "PRAGMA table_info('0bok');"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            #if DEBUG
                print("⚠️ [Version] Failed to prepare PRAGMA statement")
            #endif
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var columns: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(stmt, 1) {
                let bytes = sqlite3_column_bytes(stmt, 1)
                let buffer = UnsafeBufferPointer(start: namePtr, count: Int(bytes))
                columns.append(String(decoding: buffer, as: UTF8.self))
            }
        }

        #if DEBUG
            print("📋 [Version] Available columns: \(columns)")
        #endif

        let lowered = columns.map { $0.lowercased() }
        if let index = lowered.firstIndex(where: {
            versionColumnCandidates.contains($0)
        }) {
            cachedVersionColumn = columns[index]
            #if DEBUG
                print(
                    "✅ [Version] Resolved version column: \(cachedVersionColumn ?? "nil")"
                )
            #endif
            return cachedVersionColumn
        }

        #if DEBUG
            print(
                "❌ [Version] No version column found among candidates: \(versionColumnCandidates)"
            )
        #endif
        return nil
    }

    private func openDatabase(path: String) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK {
            sqlite3_busy_timeout(db, 5000)
            return db!
        } else {
            throw sqliteError(db, message: "Gagal membuka database \(path)")
        }
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw sqliteError(db, message: "SQL gagal dieksekusi.")
        }
    }

    private func withTransaction(
        _ db: OpaquePointer,
        mode: String = "IMMEDIATE",
        _ work: () throws -> Void
    ) throws {
        try exec(db, "BEGIN \(mode) TRANSACTION;")
        do {
            try work()
            try exec(db, "COMMIT;")
        } catch {
            try? exec(db, "ROLLBACK;")
            throw error
        }
    }

    private func bindColumnValue(
        from selectStmt: OpaquePointer,
        to insertStmt: OpaquePointer,
        columnIndex: Int32
    ) {
        let type = sqlite3_column_type(selectStmt, columnIndex)
        let bindIndex = columnIndex + 1

        switch type {
        case SQLITE_INTEGER:
            sqlite3_bind_int64(
                insertStmt,
                bindIndex,
                sqlite3_column_int64(selectStmt, columnIndex)
            )
        case SQLITE_FLOAT:
            sqlite3_bind_double(
                insertStmt,
                bindIndex,
                sqlite3_column_double(selectStmt, columnIndex)
            )
        case SQLITE_TEXT:
            if let textPtr = sqlite3_column_text(selectStmt, columnIndex) {
                sqlite3_bind_text(
                    insertStmt,
                    bindIndex,
                    textPtr,
                    -1,
                    sqliteTransient
                )
            } else {
                sqlite3_bind_null(insertStmt, bindIndex)
            }
        case SQLITE_BLOB:
            if let blob = sqlite3_column_blob(selectStmt, columnIndex) {
                let size = sqlite3_column_bytes(selectStmt, columnIndex)
                sqlite3_bind_blob(
                    insertStmt,
                    bindIndex,
                    blob,
                    size,
                    sqliteTransient
                )
            } else {
                sqlite3_bind_null(insertStmt, bindIndex)
            }
        default:
            sqlite3_bind_null(insertStmt, bindIndex)
        }
    }

    private func sqliteError(_ db: OpaquePointer?, message: String) -> NSError {
        let detail =
            db.flatMap { String(cString: sqlite3_errmsg($0)) }
            ?? "Unknown error"
        return NSError(
            domain: "BookUpdate",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: "\(message) (\(detail))"]
        )
    }

    private func columnText(_ stmt: OpaquePointer?, index: Int32) -> String {
        guard let stmt, let textPtr = sqlite3_column_text(stmt, index) else {
            return ""
        }
        let bytes = sqlite3_column_bytes(stmt, index)
        let buffer = UnsafeBufferPointer(start: textPtr, count: Int(bytes))
        return String(decoding: buffer, as: UTF8.self)
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
