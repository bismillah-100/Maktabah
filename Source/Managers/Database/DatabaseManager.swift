//
//  DatabaseManager.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

import Cocoa
import Foundation
import SQLite

// DatabaseManager.swift
class DatabaseManager {
    static var shared: DatabaseManager = .init()

    private(set) var db: Connection?
    private(set) var dbSpecial: Connection?

    let booksTable = Table("0bok")
    let categoryTable = Table("0cat")

    // Column definitions untuk 0bok
    let bokId = Expression<Int>("bkid")
    let bokCat = Expression<Int>("cat")
    let bokName = Expression<String>("bk")
    let bokArchive = Expression<Int>("Archive")
    let bokBithoqoh = Expression<String>("betaka")
    let bokMuallif = Expression<Int>("authno")
    let bokInf = Expression<String>("inf")
    let tafseerNam = Expression<String?>("TafseerNam")

    // Column definitions untuk 0cat
    let catId = Expression<Int>("id")
    let catName = Expression<String>("name")
    let catLevel = Expression<Int>("Lvl")
    let catOrder = Expression<Int>("catord")

    // Column definitions untuk Auth (dari getAuthor)
    let authTable = Table("Auth")
    let authId = Expression<Int>("authid")
    let authName = Expression<String>("auth")
    let authInf = Expression<String>("inf")
    let authLng = Expression<String>("Lng")

    var basePath: String?
    var specialPath: String?

    var shortsCache: [String: [String: String]] = [:]

    private init() {
        guard let base = AppConfig.basePath else {
            return
        }

        do {
            let mainPath = "\(base)/Files/main.sqlite"
            let specialPath = "\(base)/Files/special.sqlite"

            db = try Connection(mainPath)
            dbSpecial = try Connection(specialPath)
            basePath = base
            self.specialPath = specialPath
        } catch {
            UserDefaults.standard.removeObject(forKey: AppConfig.storageKey)
            ReusableFunc.showAlert(
                title: NSLocalizedString("Folder Not Found", comment: ""),
                message: NSLocalizedString(
                    "Application Will Terminate because Folder Location Not Found on \(base)",
                    comment: ""
                )
            )
            #if DEBUG
                print(error.localizedDescription)
            #endif
            NSApp.terminate(nil)
        }
    }

    func fetchAllCategories() throws -> [CategoryData] {
        guard let db = db else { return [] }

        var categories: [CategoryData] = []

        // Urutkan berdasarkan catord untuk menjaga hierarki yang benar
        for row in try db.prepare(categoryTable.order(catOrder, catId)) {
            let category = CategoryData(
                id: row[catId],
                name: row[catName],
                level: row[catLevel],
                order: row[catOrder]
            )
            categories.append(category)
        }

        return categories
    }

    func fetchBooks(forCategory catId: Int) throws -> [BooksData] {
        guard let db = db else { return [] }

        var books: [BooksData] = []

        let query = booksTable.filter(bokCat == catId)

        for row in try db.prepare(query) {
            let book = BooksData(
                id: row[bokId],
                book: row[bokName],
                archive: row[bokArchive],
                muallif: row[bokMuallif]
            )
            book.tafseerNam =
                row[tafseerNam]?.isEmpty == true ? nil : row[tafseerNam]
            books.append(book)
        }

        return books
    }

    func fetchBooksInfo(for bookData: BooksData) {
        guard let db = DatabaseManager.shared.db else {
            #if DEBUG
                print("Database connection is nil.")
            #endif
            return
        }

        do {
            // 1. Definisikan query: Cari baris di tabel "0bok"
            //    di mana bkid (bokId) sama dengan ID buku yang diberikan.
            let query = booksTable.filter(bokId == bookData.id)

            // 2. Eksekusi query dan ambil baris pertama
            if let row = try db.pluck(query) {

                // 3. Ekstrak data menggunakan Expression objects
                let betaka = try row.get(bokBithoqoh)
                let inf = try row.get(bokInf)

                // 4. Modifikasi objek BooksData yang shared (in-place)
                // didSet pada properti BooksData akan memicu pemrosesan string.
                bookData.bithoqoh = betaka
                bookData.info = inf

                #if DEBUG
                    print("Successfully loaded info for book \(bookData.id).")
                #endif
            }
        } catch {
            #if DEBUG
                print("Error fetching book info using SQLite.swift: \(error)")
            #endif
        }
    }

    func loadShortsForBook(_ bkid: String) -> [String: String] {
        // cek cache dulu
        if let cached = DatabaseManager.shared.shortsCache[bkid] {
            return cached
        }

        guard let dbSpecial = DatabaseManager.shared.dbSpecial else {
            return [:]
        }

        var dict: [String: String] = [:]

        do {
            let sql = "SELECT Ramz, Nass FROM shorts WHERE Bk = ?"
            let stmt = try dbSpecial.prepare(sql, bkid)

            for row in stmt {
                if let code = row[0] as? String,
                    let text = row[1] as? String
                {
                    dict[code] = text
                }
            }

            // simpan ke cache untuk pemakaian berikutnya
            DatabaseManager.shared.shortsCache[bkid] = dict

        } catch {
            #if DEBUG
                print("Error loading shorts mapping for book \(bkid): \(error)")
            #endif
        }

        return dict
    }

    func getAuthor(_ id: Int) -> Muallif? {
        if let cached = LibraryDataManager.shared.authorsCache[id] {
            return cached
        }

        guard let dbSpecial = DatabaseManager.shared.dbSpecial else {
            return nil
        }
        var resultAuthor: Muallif? = nil

        do {
            // Menggunakan Expression dan Table untuk kueri
            let query = authTable.filter(authId == id)

            if let row = try dbSpecial.pluck(query) {
                let auth = try row.get(authName)
                let inf = try row.get(authInf)
                let lng = try row.get(authLng)

                let author = Muallif(
                    nama: auth,
                    info: inf,
                    namaLengkap: lng
                )

                resultAuthor = author
                LibraryDataManager.shared.authorsCache[id] = author
            }
        } catch {
            #if DEBUG
                print(
                    "Error fetching author \(id): \(error.localizedDescription)"
                )
            #endif
        }

        return resultAuthor
    }
}
