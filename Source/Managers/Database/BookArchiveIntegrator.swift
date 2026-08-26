//
//  BookArchiveIntegrator.swift
//  Maktabah
//
//  Created by Codex on 11/03/26.
//  Integrates per-book SQLite into archive (1-20.sqlite) and builds FTS.
//

import Foundation
import SQLite3

// MARK: - IntegratePhase

/// Fase-fase integrasi yang dilaporkan ke caller melalui callback `onProgress`.
enum IntegratePhase {
    /// Sedang membangun indeks FTS dari teks kitab.
    case fts
    /// Sedang menyalin tabel data utama kitab ke archive.
    case data
}

enum BookArchiveIntegrateError: LocalizedError {
    case invalidArchiveId(Int)
    case sourceTableMissing(String)
    case fileReplacementFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidArchiveId(id):
            "Invalid archive ID: \(id)."
        case let .sourceTableMissing(table):
            "Source table missing: \(table)."
        case let .fileReplacementFailed(reason):
            "Failed to replace database files: \(reason)"
        }
    }
}

actor BookArchiveSingleFlight {
    static let shared = BookArchiveSingleFlight()

    /// Per-book dedup: buku yang sama tidak perlu integrasi ulang.
    private var bookTasks: [Int: Task<Void, Error>] = [:]

    /// Per-archive serialisasi: operasi baru mengantri setelah operasi sebelumnya selesai,
    /// mencegah concurrent write ke file archive yang sama.
    private var archiveTail: [Int: Task<Void, Error>] = [:]

    private init() {}

    func run(
        archiveId: Int,
        bookId: Int,
        operation: @escaping () async throws -> Void
    ) async throws {
        // Dedup: buku yang sama sudah berjalan → cukup tunggu hasilnya.
        if let existingTask = bookTasks[bookId] {
            try await existingTask.value
            return
        }

        // Ambil task terakhir pada archive ini (jika ada) sebagai predecessor.
        let predecessor = archiveTail[archiveId]

        // Task baru menunggu predecessor selesai sebelum menjalankan operasi.
        let task = Task<Void, Error> {
            _ = try? await predecessor?.value
            try await operation()
        }

        bookTasks[bookId] = task
        archiveTail[archiveId] = task

        do {
            try await task.value
            bookTasks.removeValue(forKey: bookId)
        } catch {
            bookTasks.removeValue(forKey: bookId)
            throw error
        }
    }
}

final class BookArchiveIntegrator {
    static let shared = BookArchiveIntegrator()

    private let sqliteTransient = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )

    private let vacuumKey = "PendingVacuumArchiveIds"
    private var pendingVacuumArchiveIds: Set<Int> = []

    private init() {
        let saved = UserDefaults.standard.array(forKey: vacuumKey) as? [Int] ?? []
        pendingVacuumArchiveIds = Set(saved)
    }

    private func savePendingVacuumIds() {
        UserDefaults.standard.set(Array(pendingVacuumArchiveIds), forKey: vacuumKey)
    }

    var hasPendingVacuum: Bool {
        !pendingVacuumArchiveIds.isEmpty
    }

    func isBookIntegrated(_ book: BooksData) -> Bool {
        guard AppConfig.isUsingBundleMode else { return true }
        // O(1) lookup melalui IntegrationCache — tidak membuka SQLite sama sekali.
        return IntegrationCache.shared.isIntegrated(bookId: book.id, archiveId: book.archive)
    }

    /// Memastikan kitab sudah terintegrasi ke archive dan FTS.
    ///
    /// - Parameters:
    ///   - book: Data kitab yang akan diintegrasikan.
    ///   - onIntegrating: Dipanggil sekali saat proses integrasi dimulai (sebelum masuk fase detail).
    ///   - onProgress: Dipanggil setiap pergantian fase integrasi — `.fts` saat build FTS dimulai,
    ///     `.data` saat copy tabel data dimulai.
    func ensureBookIntegrated(
        _ book: BooksData,
        onIntegrating: (@Sendable () async -> Void)? = nil,
        onProgress: (@Sendable (IntegratePhase) async -> Void)? = nil
    ) async throws {
        guard AppConfig.isUsingBundleMode else { return }
        guard book.archive > 0 else { throw BookArchiveIntegrateError.invalidArchiveId(book.archive) }
        guard let archiveDbPath = AppConfig.archiveDatabasePath(archiveId: book.archive),
              let ftsDbPath = AppConfig.archiveFtsDatabasePath(archiveId: book.archive)
        else {
            throw ArchiveError.databasePathNotAvailable
        }

        // Notifikasi fase integrasi untuk caller (sekali per request).
        await onIntegrating?()

        try await BookArchiveSingleFlight.shared.run(archiveId: book.archive, bookId: book.id) { [weak self] in
            guard let self else { return }
            if hasIntegratedBook(
                archiveDbPath: archiveDbPath,
                ftsDbPath: ftsDbPath,
                bookId: book.id
            ) {
                finalizeIntegration(book: book)
                return
            }

            let sourceURL = try await resolveValidSourceURL(for: book.id)

            do {
                #if DEBUG
                let sourceTables = listTables(path: sourceURL.path)
                print("[BookIntegrate] source:", sourceURL.path)
                print("[BookIntegrate] source tables:", sourceTables.joined(separator: ", "))
                print("[BookIntegrate] archive:", archiveDbPath)
                print("[BookIntegrate] fts:", ftsDbPath)
                #endif
                // Jalankan pekerjaan CPU-intensif di background, tetapi tetap bisa
                // mengawait callback onProgress ke MainActor.
                try await Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else { return }
                    try await integrate(
                        sourceURL: sourceURL,
                        archiveDbPath: archiveDbPath,
                        ftsDbPath: ftsDbPath,
                        bookId: book.id,
                        onProgress: onProgress
                    )
                }.value

                finalizeIntegration(book: book)
            } catch {
                throw error
            }
        }
    }

    /// Menghapus kitab dari archive dan FTS.
    func removeBookFromArchive(_ book: BooksData) async throws {
        guard AppConfig.isUsingBundleMode, book.archive > 0,
              let archiveDbPath = AppConfig.archiveDatabasePath(archiveId: book.archive),
              let ftsDbPath = AppConfig.archiveFtsDatabasePath(archiveId: book.archive)
        else {
            return
        }

        try await BookArchiveSingleFlight.shared.run(archiveId: book.archive, bookId: book.id) { [weak self] in
            guard let self else { return }
            try executeBookRemoval(
                book: book,
                archiveDbPath: archiveDbPath,
                ftsDbPath: ftsDbPath
            )
        }
    }

    private func executeBookRemoval(
        book: BooksData,
        archiveDbPath: String,
        ftsDbPath: String
    ) throws {
        let archiveWritePath = try prepareWritableDatabasePath(archiveDbPath)
        let ftsWritePath = try prepareWritableDatabasePath(ftsDbPath)

        var archiveDb: OpaquePointer? = try openDatabase(path: archiveWritePath)
        var ftsDb: OpaquePointer? = try openDatabase(path: ftsWritePath)

        defer {
            if let db = archiveDb { sqlite3_close(db) }
            if let db = ftsDb { sqlite3_close(db) }
        }

        dropTablesForBookRemoval(bookId: book.id, archiveDb: archiveDb, ftsDb: ftsDb)

        // Close databases explicitly BEFORE replacing the files to prevent lock issues and resource leaks.
        if let db = archiveDb {
            sqlite3_close(db)
            archiveDb = nil
        }
        if let db = ftsDb {
            sqlite3_close(db)
            ftsDb = nil
        }

        var fileReplacementFailedError: Error?
        do {
            try replaceDatabaseIfNeeded(tempPath: archiveWritePath, originalPath: archiveDbPath)
            try replaceDatabaseIfNeeded(tempPath: ftsWritePath, originalPath: ftsDbPath)
        } catch {
            #if DEBUG
            print("Error replacing databases during removal: \(error)")
            #endif
            fileReplacementFailedError = error
        }

        removeBookFromMainDbIfNeeded(bookId: book.id)
        removeAuthorFromSpecialDbIfNeeded(muallifId: book.muallif)

        pendingVacuumArchiveIds.insert(book.archive)
        savePendingVacuumIds()

        finalizeRemoval(book: book)

        if let error = fileReplacementFailedError {
            throw BookArchiveIntegrateError.fileReplacementFailed(error.localizedDescription)
        }
    }

    private func dropTablesForBookRemoval(bookId: Int, archiveDb: OpaquePointer?, ftsDb: OpaquePointer?) {
        let bookTable = "b\(bookId)"
        let tocTable = "t\(bookId)"
        let ftsTable = "\(bookTable)_fts"

        do {
            try exec(archiveDb, SQL.dropTable(name: bookTable))
            try exec(archiveDb, SQL.dropTable(name: tocTable))
            try exec(ftsDb, SQL.dropTable(name: ftsTable))
        } catch {
            #if DEBUG
            print("Error dropping tables during removal: \(error)")
            #endif
        }
    }

    private func removeBookFromMainDbIfNeeded(bookId: Int) {
        guard LibraryDataManager.shouldRemoveBook(id: bookId),
              let mainDbPath = AppConfig.mainDatabasePath else { return }
        do {
            let mainDb = try openDatabase(path: mainDbPath, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
            let query = #"DELETE FROM "0bok" WHERE bkid = \#(bookId);"#
            try exec(mainDb, query)
            mainDb.truncateAndClose()
        } catch {
            #if DEBUG
            print("Error deleting book from main database: \(error)")
            #endif
        }
    }

    private func removeAuthorFromSpecialDbIfNeeded(muallifId: Int) {
        guard LibraryDataManager.shouldRemoveAuthor(muallifId: muallifId),
              let specialDbPath = AppConfig.specialDatabasePath,
              !DatabaseManager.shared.isAuthorUsed(authorId: muallifId) else { return }
        do {
            let specialDb = try openDatabase(path: specialDbPath, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
            try exec(specialDb, "DELETE FROM Auth WHERE authid = \(muallifId);")
            specialDb.truncateAndClose()
        } catch {
            #if DEBUG
            print("Error deleting author from special database: \(error)")
            #endif
        }
    }

    /// Menjalankan VACUUM pada semua archive yang tertunda.
    /// Dipanggil secara manual dari menu Settings (iOS).
    func vacuumPendingArchives() {
        guard AppConfig.isUsingBundleMode, !pendingVacuumArchiveIds.isEmpty else { return }

        for archiveId in pendingVacuumArchiveIds {
            guard let archiveDbPath = AppConfig.archiveDatabasePath(archiveId: archiveId),
                  let ftsDbPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
            else {
                continue
            }

            #if DEBUG
            print("[Vacuum] Attempting archive: \(archiveId)")
            #endif

            // Mencoba vacuum. Jika buku sedang dibuka, ini mungkin gagal (Busy),
            // namun sesuai instruksi, kita akan tetap membersihkan daftar ID setelah proses selesai.
            vacuum(path: archiveDbPath)
            vacuum(path: ftsDbPath)
        }

        // Sesuai instruksi: setelah vacuum selesai (percobaan dilakukan), hapus semua IDs.
        pendingVacuumArchiveIds.removeAll()
        savePendingVacuumIds()
    }

    @discardableResult
    private func vacuum(path: String) -> Bool {
        var db: OpaquePointer?
        var success = false

        // Gunakan OPEN_READWRITE tanpa CREATE agar tidak membuat file baru jika tidak ada.
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK {
            // Jika database sedang digunakan, ini akan mengembalikan SQLITE_BUSY
            if sqlite3_exec(db, "VACUUM;", nil, nil, nil) == SQLITE_OK {
                success = true
            }
        }
        sqlite3_close(db)
        return success
    }

    /// Invalidasi cache DB, hapus file sementara, update IntegrationCache,
    /// lalu beri tahu LibraryViewManager agar refresh parent row.
    private func finalizeIntegration(book: BooksData) {
        DatabaseManager.shared.invalidateArchiveCache(archiveId: book.archive)
        BookDownloadManager.shared.removeCachedBook(bookId: book.id)
        IntegrationCache.shared.markIntegrated(bookId: book.id, archiveId: book.archive)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .bookIntegrated, object: book.id)
        }
    }

    private func finalizeRemoval(book: BooksData) {
        DatabaseManager.shared.invalidateArchiveCache(archiveId: book.archive)
        IntegrationCache.shared.unmarkIntegrated(bookId: book.id, archiveId: book.archive)
        LibraryDataManager.shared.removeBookFromMemory(id: book.id, muallifId: book.muallif)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .bookIntegrated, object: book.id)
        }
    }

    private func hasIntegratedBook(
        archiveDbPath: String,
        ftsDbPath: String,
        bookId: Int
    ) -> Bool {
        guard FileManager.default.isNonEmptyFile(atPath: archiveDbPath),
              FileManager.default.isNonEmptyFile(atPath: ftsDbPath)
        else {
            return false
        }

        let bookTable = "b\(bookId)"
        let ftsTable = "b\(bookId)_fts"

        guard let archiveDb = try? openDatabase(path: archiveDbPath),
              let ftsDb = try? openDatabase(path: ftsDbPath)
        else {
            return false
        }
        defer {
            sqlite3_close(archiveDb)
            sqlite3_close(ftsDb)
        }

        let hasBook = tableExists(db: archiveDb, tableName: bookTable)
        let hasFts = tableExists(db: ftsDb, tableName: ftsTable)
        return hasBook && hasFts
    }

    // MARK: - Core integrate (async untuk support await onProgress)

    private func integrate(
        sourceURL: URL,
        archiveDbPath: String,
        ftsDbPath: String,
        bookId: Int,
        onProgress: (@Sendable (IntegratePhase) async -> Void)? = nil
    ) async throws {
        guard FileManager.default.isNonEmptyFile(atPath: sourceURL.path) else {
            throw ArchiveError.fileNotReadable(path: sourceURL.path)
        }

        let archiveWritePath = try prepareWritableDatabasePath(archiveDbPath)
        let ftsWritePath = try prepareWritableDatabasePath(ftsDbPath)

        #if DEBUG
        logIntegrationDiagnostics(archiveDbPath: archiveDbPath, archiveWritePath: archiveWritePath, ftsDbPath: ftsDbPath, ftsWritePath: ftsWritePath)
        #endif

        var archiveDbPtr: OpaquePointer? = try openDatabase(path: archiveWritePath)
        guard let archiveDb = archiveDbPtr else {
            throw ArchiveError.databasePathNotAvailable
        }
        defer {
            if let db = archiveDbPtr {
                try? exec(db, SQL.detachFts)
                try? exec(db, SQL.detachSource)
                sqlite3_close(db)
            }
        }

        #if DEBUG
        let isReadonly = sqlite3_db_readonly(archiveDb, "main") == 1
        print("[BookIntegrate] sqlite readonly(main):", isReadonly)
        #endif

        try await performIntegrationTasks(
            archiveDb: archiveDb,
            sourceURL: sourceURL,
            ftsWritePath: ftsWritePath,
            bookId: bookId,
            onProgress: onProgress
        )

        // Close connection explicitly before replacing database files to release locks and avoid resource leaks.
        try exec(archiveDb, SQL.detachFts)
        try exec(archiveDb, SQL.detachSource)
        sqlite3_close(archiveDb)
        archiveDbPtr = nil

        try replaceDatabaseIfNeeded(tempPath: archiveWritePath, originalPath: archiveDbPath)
        try replaceDatabaseIfNeeded(tempPath: ftsWritePath, originalPath: ftsDbPath)
    }

    private func performIntegrationTasks(
        archiveDb: OpaquePointer,
        sourceURL: URL,
        ftsWritePath: String,
        bookId: Int,
        onProgress: (@Sendable (IntegratePhase) async -> Void)?
    ) async throws {
        try attachDatabase(
            archiveDb,
            path: sourceURL.path,
            schema: "source_db"
        )
        try attachDatabase(
            archiveDb,
            path: ftsWritePath,
            schema: "fts_db"
        )

        let bookTable = "b\(bookId)"
        let tocTable = "t\(bookId)"

        guard tableExists(db: archiveDb, schemaName: "source_db", tableName: bookTable) else {
            #if DEBUG
            let tables = listTables(db: archiveDb, schemaName: "source_db")
            print("[BookIntegrate] source_db tables:", tables.joined(separator: ", "))
            #endif
            throw BookArchiveIntegrateError.sourceTableMissing(bookTable)
        }

        // ── Fase FTS ────────────────────────────────────────────────────────
        // nass masih TEXT di source → bisa dibaca langsung untuk FTS
        await onProgress?(.fts)
        try ArchiveDatabaseTools.buildFTS(
            db: archiveDb,
            ftsSchema: "fts_db",
            ftsTable: "\(bookTable)_fts",
            sourceSchema: "source_db",
            sourceTable: bookTable
        )

        // ── Fase Data ────────────────────────────────────────────────────────
        await onProgress?(.data)
        try copySourceTablesToArchive(
            archiveDb: archiveDb,
            sourceURL: sourceURL,
            bookId: bookId,
            bookTable: bookTable,
            tocTable: tocTable
        )
    }

    private func copySourceTablesToArchive(
        archiveDb: OpaquePointer,
        sourceURL: URL,
        bookId: Int,
        bookTable: String,
        tocTable: String
    ) throws {
        try exec(archiveDb, SQL.detachSource)
        try BookUpdateManager.shared.convertBookDatabase(at: sourceURL, bookId: bookId)
        try attachDatabase(archiveDb, path: sourceURL.path, schema: "source_db")
        try ArchiveDatabaseTools.copyTable(
            db: archiveDb,
            sourceSchema: "source_db",
            tableName: bookTable
        )

        if tableExists(db: archiveDb, schemaName: "source_db", tableName: tocTable) {
            try ArchiveDatabaseTools.copyTable(
                db: archiveDb,
                sourceSchema: "source_db",
                tableName: tocTable
            )
        }
    }

    #if DEBUG
    private func logIntegrationDiagnostics(archiveDbPath: String, archiveWritePath: String, ftsDbPath: String, ftsWritePath: String) {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: archiveDbPath) {
            let perms = attrs[.posixPermissions] as? NSNumber
            let immutable = attrs[.immutable] as? NSNumber
            let appendOnly = attrs[.appendOnly] as? NSNumber
            print(
                "[BookIntegrate] archive writable:",
                FileManager.default.isWritableFile(atPath: archiveDbPath),
                "perms:",
                perms ?? -1,
                "immutable:",
                immutable ?? -1,
                "appendOnly:",
                appendOnly ?? -1
            )
        }
        if archiveWritePath != archiveDbPath {
            print("[BookIntegrate] using temp archive:", archiveWritePath)
        }
        if ftsWritePath != ftsDbPath {
            print("[BookIntegrate] using temp fts:", ftsWritePath)
        }
    }
    #endif

    private func openDatabase(path: String) throws -> OpaquePointer {
        var dbPtr: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &dbPtr, flags, nil) == SQLITE_OK, let db = dbPtr else {
            let errCode = Int(sqlite3_errcode(dbPtr))
            let errMsg = if let raw = dbPtr, let cMsg = sqlite3_errmsg(raw) {
                String(cString: cMsg)
            } else {
                "Unknown error"
            }
            if let raw = dbPtr { sqlite3_close(raw) }
            throw NSError(
                domain: "BookArchiveIntegrator",
                code: errCode,
                userInfo: [NSLocalizedDescriptionKey: errMsg]
            )
        }
        sqlite3_busy_timeout(db, 5000)
        return db
    }

    private func ensureWritableSQLite(at path: String) throws {
        let fm = FileManager.default

        if !fm.fileExists(atPath: path) {
            let db = try openDatabase(path: path, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
            sqlite3_close(db)
        }

        if fm.isWritableFile(atPath: path) { return }

        do {
            try fm.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o644))],
                ofItemAtPath: path
            )
        } catch {
            throw ArchiveError.fileNotReadable(path: path)
        }

        if !fm.isWritableFile(atPath: path) {
            throw ArchiveError.fileNotReadable(path: path)
        }
    }

    private func prepareWritableDatabasePath(_ originalPath: String) throws -> String {
        let fm = FileManager.default
        let originalURL = URL(fileURLWithPath: originalPath)
        let directory = originalURL.deletingLastPathComponent()

        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: originalPath) {
            try ensureWritableSQLite(at: originalPath)
            return originalPath
        }

        if fm.isWritableFile(atPath: originalPath) {
            return originalPath
        }

        let tempURL = directory.appendingPathComponent(
            originalURL.lastPathComponent + ".tmp." + UUID().uuidString
        )

        try fm.copyItem(at: originalURL, to: tempURL)
        try fm.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o644))],
            ofItemAtPath: tempURL.path
        )

        return tempURL.path
    }

    private func replaceDatabaseIfNeeded(tempPath: String, originalPath: String) throws {
        guard tempPath != originalPath else { return }
        let fm = FileManager.default
        let tempURL = URL(fileURLWithPath: tempPath)
        let originalURL = URL(fileURLWithPath: originalPath)

        _ = try fm.replaceItemAt(originalURL, withItemAt: tempURL)
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) throws {
        guard let db else { throw ArchiveError.databasePathNotAvailable }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw sqliteError(db, message: "SQL failed: \(sql)")
        }
    }

    private func attachDatabase(
        _ db: OpaquePointer,
        path: String,
        schema: String
    ) throws {
        try db.safeAttachDatabase(path: path, schema: schema)
    }

    private func resolveValidSourceURL(for bookId: Int) async throws -> URL {
        var lastError: Error?

        for _ in 0 ..< 2 {
            let sourceURL = try await BookDownloadManager.shared.ensureBookDownloaded(
                bookId: bookId
            )

            if sourceHasBookTable(sourceURL: sourceURL, bookId: bookId) {
                return sourceURL
            }

            BookDownloadManager.shared.removeCachedBook(bookId: bookId)
            lastError = BookArchiveIntegrateError.sourceTableMissing("b\(bookId)")
        }

        throw lastError ?? BookArchiveIntegrateError.sourceTableMissing("b\(bookId)")
    }

    private func sourceHasBookTable(sourceURL: URL, bookId: Int) -> Bool {
        guard FileManager.default.isNonEmptyFile(atPath: sourceURL.path) else { return false }
        guard let db = try? openReadOnlyDatabase(path: sourceURL.path) else { return false }
        defer { sqlite3_close(db) }
        return tableExists(db: db, tableName: "b\(bookId)")
    }

    private func listTables(path: String) -> [String] {
        guard let db = try? openReadOnlyDatabase(path: path) else { return [] }
        defer { sqlite3_close(db) }
        return db.listTableNames()
    }

    private func openReadOnlyDatabase(path: String) throws -> OpaquePointer {
        let db = try openDatabase(path: path, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
        sqlite3_busy_timeout(db, 5000)
        return db
    }

    private func openDatabase(path: String, flags: Int32) throws -> OpaquePointer {
        var dbPtr: OpaquePointer?
        guard sqlite3_open_v2(path, &dbPtr, flags, nil) == SQLITE_OK, let db = dbPtr else {
            let errCode = Int(sqlite3_errcode(dbPtr))
            let errMsg = dbPtr.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let raw = dbPtr { sqlite3_close(raw) }
            throw NSError(
                domain: "BookArchiveIntegrator",
                code: errCode,
                userInfo: [NSLocalizedDescriptionKey: errMsg]
            )
        }
        return db
    }

    private func sqliteError(_ db: OpaquePointer?, message: String) -> NSError {
        let detail =
            db.flatMap { String(cString: sqlite3_errmsg($0)) }
                ?? "Unknown error"
        return NSError(
            domain: "BookArchiveIntegrator",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: "\(message) (\(detail))"]
        )
    }

    private enum SQL {
        static func checkTableExists(schema: String) -> String {
            "SELECT 1 FROM \(schema).sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        }
        static func dropTable(name: String) -> String {
            "DROP TABLE IF EXISTS \(name);"
        }
        static let detachSource = "DETACH DATABASE source_db;"
        static let detachFts = "DETACH DATABASE fts_db;"
        static let vacuum = "VACUUM;"
    }

    private func tableExists(db: OpaquePointer, schemaName: String = "main", tableName: String) -> Bool {
        let sql = SQL.checkTableExists(schema: schemaName)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        _ = tableName.withCString { ptr in
            sqlite3_bind_text(stmt, 1, ptr, -1, sqliteTransient)
        }

        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func listTables(db: OpaquePointer, schemaName: String) -> [String] {
        db.listTableNames(schemaName: schemaName)
    }
}
