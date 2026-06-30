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
import SQLite3

struct ShortsMapping {
    let map: [String: String]
    let sortedKeys: [String]
    var isEmpty: Bool { map.isEmpty }
}

// DatabaseManager.swift
class DatabaseManager {
    static var shared: DatabaseManager = .init()

    private(set) var db: SQLiteDatabase?
    private(set) var dbSpecial: SQLiteDatabase?
    private let lock = NSLock()

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

    var shortsCache: [String: ShortsMapping] = [:]

    // MARK: - Archive Availability

    private var archiveAvailabilityCache: [Int: Bool] = [:]

    private init() {
        setupFolders()
    }

    func setupFolders() {
        lock.lock()
        defer { lock.unlock() }

        // Tutup koneksi lama jika ada
        db = nil
        dbSpecial = nil

        // Database files path (main.sqlite, special.sqlite)
        guard let mainPath = AppConfig.mainDatabasePath,
              let specialPath = AppConfig.specialDatabasePath
        else {
            print("databaseFilesPath is nil - database will not be initialized")
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
            print("\(error). Continue to ReadOnly Mode...")
        }

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX

        do {
            db = try SQLiteDatabase(path: mainPath, flags: flags)
        } catch {
            handleSetupError()
            return
        }

        do {
            dbSpecial = try SQLiteDatabase(path: specialPath, flags: flags)
        } catch {
            handleSetupError()
            return
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
        ReusableFunc.showAlert(
            title: NSLocalizedString("Folder Not Found", comment: ""),
            message: NSLocalizedString(
                "Application Will Terminate because Folder Location Not Found on \(AppConfig.databaseFilesPath ?? "N/A")",
                comment: ""
            )
        )
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        #if os(macOS)
        NSApp.terminate(nil)
        #else
        fatalError("Application Terminated: Folder Location Not Found")
        #endif
    }

    func fetchAllCategories() throws -> [CategoryData] {
        lock.lock()
        defer { lock.unlock() }

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

    func fetchAllBooksGroupedByCategory() throws -> [Int: [BooksData]] {
        lock.lock()
        defer { lock.unlock() }

        guard let db else { return [:] }

        var groupedBooks: [Int: [BooksData]] = [:]
        let sql = "SELECT \(colBokId), \(colBokName), \(colBokArchive), \(colBokMuallif), \(colBokCat), \(colTafseerNam), \(colBokPdfCs) FROM \(booksTableName) ORDER BY \(colBokName) ASC"

        let books = try db.fetch(query: sql) { row -> BooksData in
            let id = row.int(at: 0)
            let name = row.string(at: 1) ?? ""
            let archive = row.int(at: 2)
            let muallif = row.int(at: 3)
            let catId = row.int(at: 4)

            let tafseer = row.string(at: 5)
            let pdfCs = !row.isNull(at: 6) ? row.int(at: 6) : nil

            let book = BooksData(id: id, book: name, archive: archive, muallif: muallif)
            book.catId = catId
            book.tafseerNam = (tafseer?.isEmpty == true) ? nil : tafseer
            book.pdfCs = pdfCs
            return book
        }

        for book in books {
            if let catId = book.catId {
                groupedBooks[catId, default: []].append(book)
            }
        }

        return groupedBooks
    }

    func getMaxBookId() -> Int {
        lock.lock()
        defer { lock.unlock() }

        guard let db else { return 0 }
        let sql = "SELECT MAX(\(colBokId)) FROM \(booksTableName)"

        return (try? db.fetch(query: sql) { row in
            row.int(at: 0)
        }.first) ?? 0
    }

    func getMaxAuthId() -> Int {
        lock.lock()
        defer { lock.unlock() }

        guard let dbSpecial = dbSpecial else { return 0 }
        let sql = "SELECT MAX(\(colAuthId)) FROM \(authTableName)"

        return (try? dbSpecial.fetch(query: sql) { row in
            row.int(at: 0)
        }.first) ?? 0
    }

    func fetchAllAuthors() -> [(id: Int, muallif: Muallif)] {
        lock.lock()
        defer { lock.unlock() }

        guard let dbSpecial = dbSpecial else { return [] }
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
        lock.lock()
        defer { lock.unlock() }

        guard let db else {
            throw NSError(domain: "No database connection", code: 1)
        }

        let sql = "SELECT \(colBokId), \(colBokName), \(colBokArchive), \(colBokMuallif), \(colTafseerNam), \(colBokPdfCs) FROM \(booksTableName) WHERE \(colBokId) = ? LIMIT 1"

        let books = try db.fetch(query: sql, parameters: [bookId]) { row -> BooksData in
            let id = row.int(at: 0)
            let name = row.string(at: 1) ?? ""
            let archive = row.int(at: 2)
            let muallif = row.int(at: 3)
            let tafseer = row.string(at: 4)
            let pdfCs = !row.isNull(at: 5) ? row.int(at: 5) : nil

            let book = BooksData(id: id, book: name, archive: archive, muallif: muallif)
            book.tafseerNam = (tafseer?.isEmpty == true) ? nil : tafseer
            book.pdfCs = pdfCs
            return book
        }

        if let book = books.first {
            return book
        } else {
            throw NSError(domain: "Book not found", code: 1)
        }
    }

    func bookExists(id: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return false }

        let sql = "SELECT 1 FROM `0bok` WHERE `bkid` = ? LIMIT 1;"
        return (try? db.fetch(query: sql, parameters: [id]) { _ in true }.first) ?? false
    }

    func isAuthorUsed(authorId: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return false }

        let sql = "SELECT 1 FROM \(booksTableName) WHERE \(colBokMuallif) = ? LIMIT 1;"
        return (try? db.fetch(query: sql, parameters: [authorId]) { _ in true }.first) ?? false
    }

    func fetchBooksInfo(for bookData: BooksData) {
        lock.lock()
        defer { lock.unlock() }

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
        lock.lock()
        defer { lock.unlock() }

        if let cached = shortsCache[bkid] {
            return cached
        }

        guard let dbSpecial = dbSpecial else {
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
        shortsCache[bkid] = mapping
        return mapping
    }

    func getAuthor(_ id: Int) -> Muallif? {
        if let cached = LibraryDataManager.shared.getAuthorFromCache(id: id) {
            return cached
        }

        lock.lock()
        defer { lock.unlock() }

        guard let dbSpecial = dbSpecial else {
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
        lock.lock()
        if let cached = archiveAvailabilityCache[archiveId] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let fm = FileManager.default
        guard let archiveFile = AppConfig.archiveDatabasePath(archiveId: archiveId),
              let ftsFtsFile = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
        else {
            return false
        }

        let archiveExists = fm.fileExists(atPath: archiveFile)
        let ftsExists = fm.fileExists(atPath: ftsFtsFile)
        let isAvailable: Bool

        if archiveExists && ftsExists {
            let archiveSize = (try? fm.attributesOfItem(atPath: archiveFile)[.size] as? NSNumber)?.int64Value ?? 0
            let ftsSize = (try? fm.attributesOfItem(atPath: ftsFtsFile)[.size] as? NSNumber)?.int64Value ?? 0
            isAvailable = archiveSize > 0 && ftsSize > 0
        } else {
            isAvailable = false
        }

        lock.lock()
        archiveAvailabilityCache[archiveId] = isAvailable
        lock.unlock()
        return isAvailable
    }

    func invalidateArchiveCache(archiveId: Int) {
        lock.lock()
        archiveAvailabilityCache.removeValue(forKey: archiveId)
        lock.unlock()
        IntegrationCache.shared.invalidate(archiveId: archiveId)
    }
}
