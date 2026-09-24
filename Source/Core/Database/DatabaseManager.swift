//
//  DatabaseManager.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation
import OSLog
import SQLite3
import Synchronization

struct ShortsMapping: Sendable {
    let map: [String: String]
    let sortedKeys: [String]
    var isEmpty: Bool {
        map.isEmpty
    }
}

/// DatabaseManager.swift
final class DatabaseManager: Sendable {
    static let shared: DatabaseManager = .init()

    private struct DatabaseState: Sendable {
        var db: SQLiteDatabase?
        var dbSpecial: SQLiteDatabase?
        var shortsCache: [String: ShortsMapping] = [:]
        var archiveAvailabilityCache: [Int: Bool] = [:]
    }

    private let state: Mutex<DatabaseState> = .init(DatabaseState())

    var db: SQLiteDatabase? {
        state.withLock { $0.db }
    }

    var dbSpecial: SQLiteDatabase? {
        state.withLock { $0.dbSpecial }
    }

    // Table names
    private let booksTableName = "\"0bok\""
    private let categoryTableName = "\"0cat\""
    private let authTableName = "Auth"

    // Column names untuk 0bok
    private let colBokId = "bkid"
    private let colBokCat = "cat"
    private let colBokName = "bk"
    private let colBokArchive = "Archive"
    private let colBokBithoqoh = "betaka"
    private let colBokMuallif = "authno"
    private let colBokInf = "inf"
    private let colBokPdfCs = "PdfCs"
    private let colTafseerNam = "TafseerNam"

    // Column names untuk 0cat
    private let colCatId = "id"
    private let colCatName = "name"
    private let colCatLevel = "Lvl"
    private let colCatOrder = "catord"

    // Column names untuk Auth
    private let colAuthId = "authid"
    private let colAuthName = "auth"
    private let colAuthInf = "inf"
    private let colAuthLng = "Lng"

    private init() {
        setupFolders()
    }

    func setupFolders() {
        state.withLock { s in
            s.db = nil
            s.dbSpecial = nil
        }

        // Database files path (main.sqlite, special.sqlite)
        guard let mainPath = AppConfig.mainDatabasePath,
              let specialPath = AppConfig.specialDatabasePath
        else {
            Logger.db.error("databaseFilesPath is nil - database will not be initialized")
            return
        }

        do {
            let tempWriteDb = try SQLiteDatabase(path: specialPath)

            let sqlIndex = """
            CREATE INDEX IF NOT EXISTS idx_auth_covering
            ON "Auth" ("auth" ASC, "authid", "inf", "Lng");
            """
            try tempWriteDb.execute(query: sqlIndex)
        } catch {
            Logger.db.error("\(error.localizedDescription, privacy: .public). Continue to ReadOnly Mode...")
        }

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        let newDb: SQLiteDatabase
        do {
            newDb = try SQLiteDatabase(path: mainPath, flags: flags, queryOnly: true)
        } catch {
            handleSetupError()
            return
        }

        let newDbSpecial: SQLiteDatabase
        do {
            newDbSpecial = try SQLiteDatabase(path: specialPath, flags: flags, queryOnly: true)
        } catch {
            handleSetupError()
            return
        }

        state.withLock { s in
            s.db = newDb
            s.dbSpecial = newDbSpecial
        }
    }

    /// Reopen database connections dan reset cache library
    /// serta mengirim notifikasi.
    func reloadConnectionAndLibrary() {
        LibraryDataManager.shared.resetState()
        DatabaseManager.shared.setupFolders()
        TarjamahGlobalManager.shared.setupConnection()
        BookPageCache.shared.removeAll()
        NotificationCenter.default.post(
            name: .libraryFolderChanged,
            object: nil
        )
    }

    /// Read version from table 'v' in main.sqlite
    /// Returns nil if table doesn't exist or query fails
    func getLocalVersionDisplay() -> String? {
        // Check if table 'v' exists
        let checkQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name='v'"

        var tableExists = false
        do {
            try db?.fetch(query: checkQuery) { _ in
                tableExists = true
            }
        } catch {
            return nil
        }

        guard tableExists else {
            return nil // Table 'v' doesn't exist
        }

        // Get version from table 'v'
        let query = "SELECT version FROM v LIMIT 1"

        var version: String?
        do {
            try db?.fetch(query: query) { row in
                version = row.string(at: 0)
            }
        } catch {
            return nil
        }

        return version
    }

    private func handleSetupError() {
        AppConfig.resetCustomModeKey()
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        #if os(macOS)
        ReusableFunc.showAlert(
            title: NSLocalizedString("Folder Not Found", comment: ""),
            message: NSLocalizedString(
                "Application Will Terminate because Folder Location Not Found on \(AppConfig.databaseFilesPath ?? "N/A")",
                comment: ""
            )
        )
        Task { @MainActor in
            NSApp.terminate(nil)
        }
        #else
        return
        #endif
    }

    func fetchAllCategories() throws -> [CategoryData] {
        guard let db else { return [] }

        let sql = "SELECT \(colCatId), \(colCatName), \(colCatLevel), \(colCatOrder) FROM \(categoryTableName) ORDER BY \(colCatOrder), \(colCatId)"

        return try db.fetch(query: sql) { row in
            let id = row.int(at: 0)
            let name = row.string(at: 1) ?? ""
            let level = row.int(at: 2)
            let order = row.int(at: 3)
            return CategoryData(id: id, name: name, level: level, order: order)
        }
    }

    private var bookSelectColumns: String {
        "\(colBokId), \(colBokName), \(colBokArchive), \(colBokMuallif), \(colBokCat), \(colTafseerNam), \(colBokPdfCs)"
    }

    private func parseBookData(from row: SQLiteRow) -> BooksData {
        let id = row.int(at: 0)
        let name = row.string(at: 1) ?? ""
        let archive = row.int(at: 2)
        let muallif = row.int(at: 3)
        let catId = !row.isNull(at: 4) ? row.int(at: 4) : nil
        let tafseer = row.string(at: 5)
        let pdfCs = !row.isNull(at: 6) ? row.int(at: 6) : nil

        let book = BooksData(id: id, book: name, archive: archive, muallif: muallif)
        book.catId = catId
        book.tafseerNam = (tafseer?.isEmpty == true) ? nil : tafseer
        book.pdfCs = pdfCs
        return book
    }

    func fetchAllBooksGroupedByCategory() throws -> [Int: [BooksData]] {
        guard let db else { return [:] }

        var groupedBooks: [Int: [BooksData]] = [:]
        let sql = "SELECT \(bookSelectColumns) FROM \(booksTableName) ORDER BY \(colBokName) ASC"
        let books = try db.fetch(query: sql, mapping: parseBookData(from:))

        for book in books {
            if let catId = book.catId {
                groupedBooks[catId, default: []].append(book)
            }
        }

        return groupedBooks
    }

    func getMaxBookId() -> Int {
        guard let db else { return 0 }
        let sql = "SELECT MAX(\(colBokId)) FROM \(booksTableName)"

        return (try? db.fetch(query: sql) { row in
            row.int(at: 0)
        }.first) ?? 0
    }

    func getMaxAuthId() -> Int {
        guard let dbSpecial else { return 0 }
        let sql = "SELECT MAX(\(colAuthId)) FROM \(authTableName)"

        return (try? dbSpecial.fetch(query: sql) { row in
            row.int(at: 0)
        }.first) ?? 0
    }

    func fetchAllAuthors() -> [(id: Int, muallif: Muallif)] {
        guard let dbSpecial else { return [] }
        let sql = "SELECT \(colAuthId), \(colAuthName), \(colAuthInf), \(colAuthLng) FROM \(authTableName) ORDER BY \(colAuthName)"

        return (try? dbSpecial.fetch(query: sql) { row in
            let id = row.int(at: 0)
            let auth = row.string(at: 1) ?? ""
            let inf = row.string(at: 2) ?? ""
            let lng = row.string(at: 3) ?? ""
            return (id: id, muallif: Muallif(nama: auth, info: inf, namaLengkap: lng))
        }) ?? []
    }

    func fetchBook(byId bookId: Int) throws -> BooksData? {
        guard let db else {
            throw NSError(domain: "No database connection", code: 1)
        }

        let sql = "SELECT \(bookSelectColumns) FROM \(booksTableName) WHERE \(colBokId) = ? LIMIT 1"
        let books = try db.fetch(query: sql, parameters: [bookId], mapping: parseBookData(from:))

        if let book = books.first {
            return book
        } else {
            throw NSError(domain: "Book not found", code: 1)
        }
    }

    func bookExists(id: Int) -> Bool {
        guard let db else { return false }

        let sql = "SELECT 1 FROM `0bok` WHERE `bkid` = ? LIMIT 1;"
        return (try? db.fetch(query: sql, parameters: [id]) { _ in true }.first) ?? false
    }

    func isAuthorUsed(authorId: Int) -> Bool {
        guard let db else { return false }

        let sql = "SELECT 1 FROM \(booksTableName) WHERE \(colBokMuallif) = ? LIMIT 1;"
        return (try? db.fetch(query: sql, parameters: [authorId]) { _ in true }.first) ?? false
    }

    func fetchBooksInfo(for bookData: BooksData) {
        guard let db else { return }

        let sql = "SELECT \(colBokBithoqoh), \(colBokInf) FROM \(booksTableName) WHERE \(colBokId) = ?"

        if let info = try? db.fetch(query: sql, parameters: [bookData.id], mapping: { row -> (String, String) in
            return (row.string(at: 0) ?? "", row.string(at: 1) ?? "")
        }).first {
            bookData.bithoqoh = info.0
            bookData.info = info.1
        }
    }

    func loadShortsForBook(_ bkid: String) -> ShortsMapping {
        if let cached = state.withLock({ $0.shortsCache[bkid] }) {
            return cached
        }

        guard let dbSpecial else {
            return ShortsMapping(map: [:], sortedKeys: [])
        }

        var dict: [String: String] = [:]
        let sql = "SELECT Ramz, Nass FROM shorts WHERE Bk = ?"

        if let results = try? dbSpecial.fetch(query: sql, parameters: [bkid], mapping: { row -> (String, String) in
            return (row.string(at: 0) ?? "", row.string(at: 1) ?? "")
        }) {
            for res in results {
                dict[res.0] = res.1
            }
        }

        let sortedKeys = dict.keys.sorted { $0.count > $1.count }
        let mapping = ShortsMapping(map: dict, sortedKeys: sortedKeys)
        state.withLock { $0.shortsCache[bkid] = mapping }
        return mapping
    }

    func getAuthor(_ id: Int) -> Muallif? {
        if let cached = LibraryDataManager.shared.getAuthorFromCache(id: id) {
            return cached
        }

        guard let dbSpecial else {
            return nil
        }

        let sql = "SELECT \(colAuthName), \(colAuthInf), \(colAuthLng) FROM \(authTableName) WHERE \(colAuthId) = ? LIMIT 1"

        if let author = try? dbSpecial.fetch(query: sql, parameters: [id], mapping: { row -> Muallif in
            let auth = row.string(at: 0) ?? ""
            let inf = row.string(at: 1) ?? ""
            let lng = row.string(at: 2) ?? ""
            return Muallif(nama: auth, info: inf, namaLengkap: lng)
        }).first {
            LibraryDataManager.shared.updateAuthorInCache(id: id, muallif: author)
            return author
        }

        return nil
    }

    // MARK: - Archive File Management

    func checkArchiveAvailability(archiveId: Int) -> Bool {
        if let cached = state.withLock({ $0.archiveAvailabilityCache[archiveId] }) {
            return cached
        }

        let fm = FileManager.default
        guard let archiveFile = AppConfig.archiveDatabasePath(archiveId: archiveId),
              let ftsFtsFile = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
        else {
            return false
        }

        let isAvailable = fm.isNonEmptyFile(atPath: archiveFile) && fm.isNonEmptyFile(atPath: ftsFtsFile)

        state.withLock {
            $0.archiveAvailabilityCache[archiveId] = isAvailable
        }
        return isAvailable
    }

    func invalidateArchiveCache(archiveId: Int) {
        state.withLock {
            _ = $0.archiveAvailabilityCache.removeValue(forKey: archiveId)
        }
        IntegrationCache.shared.invalidate(archiveId: archiveId)
    }

    static func validateDatabaseFolder(_ url: URL) -> Error? {
        let fm = FileManager.default
        let mainFolder = url.appendingPathComponent("Files", isDirectory: true)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: mainFolder.path, isDirectory: &isDir), isDir.boolValue else {
            return NSError(domain: "Maktabah", code: 1, userInfo: [NSLocalizedDescriptionKey: "Folder 'Files' is missing."])
        }

        let mainSqlite = mainFolder.appendingPathComponent("main.sqlite")
        let specialSqlite = mainFolder.appendingPathComponent("special.sqlite")

        guard fm.isNonEmptyFile(at: mainSqlite), fm.isNonEmptyFile(at: specialSqlite) else {
            return NSError(domain: "Maktabah", code: 2, userInfo: [NSLocalizedDescriptionKey: "main.sqlite or special.sqlite is missing or empty in the 'Files' folder."])
        }

        do {
            let dbMain = try SQLiteDatabase(path: mainSqlite.path, flags: SQLITE_OPEN_READONLY)
            let dbSpecial = try SQLiteDatabase(path: specialSqlite.path, flags: SQLITE_OPEN_READONLY)

            let checkTable = { (db: SQLiteDatabase, table: String) throws in
                var exists = false
                let query = "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)'"
                try db.fetch(query: query) { _ in exists = true }
                if !exists {
                    throw NSError(domain: "Maktabah", code: 4, userInfo: [NSLocalizedDescriptionKey: "Table '\(table)' is missing in database."])
                }
            }

            try checkTable(dbMain, "0bok")
            try checkTable(dbMain, "0cat")
            try checkTable(dbMain, "v")

            try checkTable(dbSpecial, "Auth")
            try checkTable(dbSpecial, "shorts")
        } catch {
            return error
        }

        return nil
    }
}
