//
//  BookUpdateManager.swift
//  Maktabah
//
//  Created by MacBook on 06/02/26.
//

import Foundation
import SQLite
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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

            // Periksa versi saat ini di database
            let currentVersion = try? getCurrentVersion(bookId: entry.bkid)

            let item = BookUpdateItem(
                id: entry.bkid,
                bookName: bookName,
                category: entry.category,
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
                    print(
                        "🔄 [Fetch Updates] Book \(entry.bkid) needs update: \(currentVersion ?? -1) → \(entry.versionName)"
                    )
                }
            #endif
        }

        #if DEBUG
            let needsUpdateCount = items.filter { $0.needsUpdate }.count
            print(
                "✅ [Fetch Updates] Loaded \(items.count) books, \(needsUpdateCount) need updates"
            )
        #endif

        return items
    }

    private func getCurrentVersion(bookId: Int) throws -> Int64? {
        guard let basePath = DatabaseManager.shared.basePath else {
            return nil
        }
        let mainPath = "\(basePath)/Files/main.sqlite"
        let db = try openDatabase(path: mainPath)
        defer { sqlite3_close(db) }

        guard let versionColumn = resolveVersionColumn(in: db) else {
            return nil
        }

        let sql =
            "SELECT `\(versionColumn)` FROM `0bok` WHERE `bkid` = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(bookId))

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil  // Book not found
        }

        if sqlite3_column_type(stmt, 0) == SQLITE_NULL {
            return nil  // NULL version
        }

        return sqlite3_column_int64(stmt, 0)
    }

    // MARK: - Process Single Book (untuk selective download)

    /// Memproses satu buku saja (digunakan saat download selektif)
    func processSingleBook(
        _ entry: BookIndexEntry,
        authIndex: [Int: AuthIndexEntry]
    ) async throws -> BookUpdateResult? {

        #if DEBUG
            print("🔄 [Process Single] Starting process for book \(entry.bkid)")
        #endif

        // Gunakan method process yang sudah ada
        return try await process(entry, authIndex: authIndex)
    }

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

    private func process(
        _ entry: BookIndexEntry,
        authIndex: [Int: AuthIndexEntry]
    ) async throws -> BookUpdateResult? {
        let exists = try bookExists(id: entry.bkid)
        let needsUpdate = try bookNeedsUpdate(
            id: entry.bkid,
            newVersion: entry.versionName
        )

        if exists, !needsUpdate {
            return BookUpdateResult(
                bookId: entry.bkid,
                catId: entry.category,
                action: .skipped
            )
        }

        guard
            let downloadURL = URL(
                string: entry.downloadURL
            )
        else { return nil }

        let workingDirectory = try makeWorkingDirectory()
        let downloadedMetadataURL = try await downloadFile(
            from: downloadURL,
            to: workingDirectory,
            SQLite: true
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

        if let authId = metadata.authno, let authEntry = authIndex[authId],
            let downloadURL = URL(
                string: authEntry.downloadURL
            )
        {
            try await ensureAuthor(
                authId: authId,
                downloadURL: downloadURL,
                workingDirectory: workingDirectory,
                newVersion: authEntry.versionName
            )
        }

        guard let link = metadata.link,
            let bookURL = URL(
                string: BookUpdateViewModel.driveLink + link
            )
        else { return nil }

        let newWorkingDirectory = try makeWorkingDirectory()
        let downloadedBookURL = try await downloadFile(
            from: bookURL,
            to: newWorkingDirectory,
            SQLite: true
        )

        try rebuildFTS(
            with: downloadedBookURL,
            archiveId: metadata.archive,
            bookId: metadata.bkid
        )

        try convertBookDatabase(at: downloadedBookURL, bookId: metadata.bkid)
        try replaceArchiveDatabase(
            with: downloadedBookURL,
            archiveId: metadata.archive,
            bookId: metadata.bkid
        )

        if !exists {
            try insertBookMetadata(metadata)
        }

        return BookUpdateResult(
            bookId: metadata.bkid,
            catId: entry.category,
            action: exists ? .updated : .inserted
        )
    }

    private func bookExists(id: Int) throws -> Bool {
        guard let db = DatabaseManager.shared.db else { return false }
        let query = DatabaseManager.shared.booksTable.filter(
            DatabaseManager.shared.bokId == id
        )
        return try db.pluck(query) != nil
    }

    private func bookNeedsUpdate(id: Int, newVersion: Int64) throws -> Bool {
        guard let basePath = DatabaseManager.shared.basePath else {
            #if DEBUG
                print("⚠️ [Update Check] basePath is nil")
            #endif
            return false
        }
        let mainPath = "\(basePath)/Files/main.sqlite"

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
        guard let db = DatabaseManager.shared.db else { return }

        let manager = DatabaseManager.shared
        let insert = manager.booksTable.insert(
            manager.bokId <- metadata.bkid,
            manager.bokCat <- metadata.cat ?? 0,
            manager.bokName <- metadata.bk,
            manager.bokArchive <- metadata.archive,
            manager.bokBithoqoh <- metadata.betaka ?? "",
            manager.bokMuallif <- metadata.authno ?? 0,
            manager.bokInf <- metadata.inf ?? "",
            manager.tafseerNam <- metadata.tafseerNam,
            manager.bVer <- metadata.bVer
        )

        try db.run(insert)
    }

    private func ensureAuthor(
        authId: Int,
        downloadURL: URL,
        workingDirectory: URL,
        newVersion: Int64
    ) async throws {
        guard let basePath = DatabaseManager.shared.basePath else { return }
        let specialPath = "\(basePath)/Files/special.sqlite"

        let specialDb = try openDatabase(path: specialPath)
        defer { sqlite3_close(specialDb) }

        if !authorNeedsUpdate(
            authId: authId,
            newVersion: Int(newVersion),
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
            .lowercased() == headerKey
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
            SELECT bkid, bk, cat, betaka, inf, authno, archive, TafseerNam, bVer, link
            FROM main_update
            WHERE bkid = ? LIMIT 1;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(fallbackBookId))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let bkid = Int(sqlite3_column_int(stmt, 0))
        let bk = columnText(stmt, index: 1)
        let cat = sqlite3_column_int(stmt, 2)
        let betaka = columnText(stmt, index: 3)
        let inf = columnText(stmt, index: 4)
        let authno = sqlite3_column_int(stmt, 5)
        let archive = sqlite3_column_int(stmt, 6)
        let tafseerNam = columnText(stmt, index: 7)
        let bVer = sqlite3_column_int(stmt, 8)
        let link = columnText(stmt, index: 9)

        return BookMetadata(
            bkid: bkid,
            cat: Int(cat),
            bk: bk,
            archive: Int(archive),
            betaka: betaka.isEmpty ? nil : betaka,
            authno: Int(authno),
            inf: inf.isEmpty ? nil : inf,
            tafseerNam: tafseerNam.isEmpty ? nil : tafseerNam,
            bVer: Int(bVer),
            link: link.isEmpty ? nil : link
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

        sqlite3_bind_int(stmt, 1, Int32(authId))

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return nil
    }

    // Untuk cek apakah perlu update:
    private func authorNeedsUpdate(
        authId: Int,
        newVersion: Int,
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

        sqlite3_bind_int(stmt, 1, Int32(authId))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let authIdValue = Int(sqlite3_column_int(stmt, 0))
        let authName = columnText(stmt, index: 1)
        let authInf = columnText(stmt, index: 2)
        let authLng = columnText(stmt, index: 3)
        let authHigri = columnText(stmt, index: 4)
        let oVer = Int(sqlite3_column_int(stmt, 5))

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

        sqlite3_bind_int(stmt, 1, Int32(row["authid"] as? Int ?? 0))
        sqlite3_bind_text(
            stmt,
            2,
            (row["auth"] as? String ?? ""),
            -1,
            sqliteTransient
        )
        sqlite3_bind_text(
            stmt,
            3,
            (row["inf"] as? String ?? ""),
            -1,
            sqliteTransient
        )
        sqlite3_bind_text(
            stmt,
            4,
            (row["Lng"] as? String ?? ""),
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
        sqlite3_bind_int(
            stmt,
            6,
            Int32(row["oVer"] as? Int ?? 0)
        )

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw sqliteError(db, message: "Gagal insert Auth.")
        }
    }

    private func convertBookDatabase(at url: URL, bookId: Int) throws {
        let db = try openDatabase(path: url.path)
        defer { sqlite3_close(db) }

        let tableName = "b\(bookId)"
        let tempTable = "\(tableName)_zstd"
        let columns = try loadTableColumns(tableName: tableName, db: db)

        try exec(db, "DROP TABLE IF EXISTS \(tempTable);")
        let createSQL = makeCreateTableSQL(
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
            sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK
        else {
            throw sqliteError(db, message: "Gagal prepare SELECT konversi.")
        }
        defer { sqlite3_finalize(selectStmt) }

        guard
            sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK
        else {
            throw sqliteError(db, message: "Gagal prepare INSERT konversi.")
        }
        defer { sqlite3_finalize(insertStmt) }

        while sqlite3_step(selectStmt) == SQLITE_ROW {
            sqlite3_reset(insertStmt)

            for (index, column) in columns.enumerated() {
                let colIndex = Int32(index)
                if column.name.lowercased() == "nass" {
                    if let textPtr = sqlite3_column_text(selectStmt, colIndex) {
                        let text = String(cString: textPtr)
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

    private func replaceArchiveDatabase(
        with sourceURL: URL,
        archiveId: Int,
        bookId: Int
    ) throws {
        guard let basePath = DatabaseManager.shared.basePath else { return }
        let targetPath = "\(basePath)/\(archiveId).sqlite"
        let db = try openDatabase(path: targetPath)
        defer { sqlite3_close(db) }
        let attachSQL = "ATTACH DATABASE '\(sourceURL.path)' AS source_db;"
        try exec(db, attachSQL)

        try replaceTable(
            db: db,
            tableName: "b\(bookId)",
            sourceSchema: "source_db"
        )

        try replaceTable(
            db: db,
            tableName: "t\(bookId)",
            sourceSchema: "source_db"
        )

        try exec(db, "DETACH DATABASE source_db;")
        try exec(db, "VACUUM;")
    }

    private func replaceTable(
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

    func registerNormalizeFunction(db: OpaquePointer?) {
        sqlite3_create_function_v2(
            db,
            "normalize_arabic",
            1,
            SQLITE_UTF8,
            nil,
            { context, argc, argv in
                guard argc == 1, let arg = argv?[0] else { return }
                guard let textPtr = sqlite3_value_text(arg) else { return }
                let input = String(cString: textPtr)
                var normalized = input.replacingOccurrences(
                    of: "\\n",
                    with: " "
                )
                normalized = input.normalizeArabic()
                sqlite3_result_text(context, normalized, -1, SQLITE_TRANSIENT)
            },
            nil,
            nil,
            nil
        )
    }

    private func rebuildFTS(
        with contentDBPath: URL,
        archiveId: Int,
        bookId: Int
    ) throws {
        guard let basePath = DatabaseManager.shared.basePath else { return }
        let ftsDBPath = "\(basePath)/\(archiveId)_fts.sqlite"

        var db: OpaquePointer?
        // Gunakan file yang di-download sebagai database UTAMA (main)
        if sqlite3_open(contentDBPath.path, &db) != SQLITE_OK {
            throw sqliteError(db, message: "Gagal membuka DB konten")
        }
        defer { sqlite3_close(db) }

        registerNormalizeFunction(db: db)

        // Attach database FTS eksternal
        let attachSQL = "ATTACH DATABASE '\(ftsDBPath)' AS fts_db;"
        try exec(db!, attachSQL)

        let tableName = "b\(bookId)"
        let ftsTable = "\(tableName)_fts"

        // Gunakan DROP & CREATE untuk contentless table agar tidak error
        try exec(db!, "DROP TABLE IF EXISTS fts_db.\(ftsTable);")
        let createFTS =
            "CREATE VIRTUAL TABLE fts_db.\(ftsTable) USING fts5(nass_clean, content='', tokenize='unicode61');"
        try exec(db!, createFTS)

        // SEKARANG INSERT:
        // Kita baca dari 'main' (yaitu file download yang masih berisi TEXT)
        // Kita tulis ke 'fts_db'
        let insertSQL = """
                INSERT INTO fts_db.\(ftsTable)(rowid, nass_clean)
                SELECT id, normalize_arabic(nass)
                FROM main.\(tableName) -- 'main' di sini adalah file contentDBPath
                WHERE nass IS NOT NULL AND nass != '';
            """
        try exec(db!, insertSQL)

        try exec(db!, "DETACH DATABASE fts_db;")
    }

    private func makeWorkingDirectory() throws -> URL {
        guard let basePath = DatabaseManager.shared.basePath else {
            throw NSError(
                domain: "BookUpdate",
                code: -4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Base path tidak tersedia."
                ]
            )
        }

        let directory = URL(fileURLWithPath: basePath)
            .appendingPathComponent("Files", isDirectory: true)
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
        SQLite: Bool = false
    ) async throws
        -> URL
    {
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        var destination = directory.appendingPathComponent(
            url.lastPathComponent
        )

        if SQLite {
            destination = URL(string: destination.absoluteString + ".sqlite")!
        }

        #if DEBUG
            print("destination:", destination)
        #endif

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

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
                columns.append(String(cString: namePtr))
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
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw sqliteError(db, message: "Gagal membuka database \(path)")
        }
        return db!
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw sqliteError(db, message: "SQL gagal dieksekusi.")
        }
    }

    private func loadTableColumns(
        tableName: String,
        db: OpaquePointer,
        schemaName: String = "main"
    ) throws -> [TableColumnInfo] {
        let sql = "PRAGMA \(schemaName).table_info('\(tableName)');"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError(
                db,
                message: "Gagal load info tabel \(tableName)."
            )
        }
        defer { sqlite3_finalize(stmt) }

        var columns: [TableColumnInfo] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let type = String(cString: sqlite3_column_text(stmt, 2))
            let isPrimaryKey = sqlite3_column_int(stmt, 5) == 1
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

    private func makeCreateTableSQL(
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
        return String(cString: textPtr)
    }

    /* LEGACY
    func applyUpdates(from indexURL: URL, authIndexURL: URL?) async throws
        -> [BookUpdateResult]
    {
        let entries = try await fetchIndexEntries(from: indexURL)
        let authEntries = try await fetchAuthIndexEntriesIfNeeded(
            from: authIndexURL
        )
        let authIndexMap = Dictionary(
            uniqueKeysWithValues: authEntries.map { ($0.authId, $0) }
        )
        var results: [BookUpdateResult] = []
    
        for entry in entries {
            do {
                if let result = try await process(
                    entry,
                    authIndex: authIndexMap
                ) {
                    results.append(result)
                }
            } catch {
                print(
                    "Gagal memproses bkid \(entry.bkid): \(error.localizedDescription)"
                )
                // Lanjut ke baris berikutnya, jangan berhenti
                continue
            }
        }
    
        return results
    }
     */
}

private struct TableColumnInfo {
    let name: String
    let type: String
    let isPrimaryKey: Bool
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
