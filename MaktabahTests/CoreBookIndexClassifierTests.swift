//
//  CoreBookIndexClassifierTests.swift
//  MaktabahTests
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("Core Book Index Classifier Tests", .serialized)
final class CoreBookIndexClassifierTests {
    private let previousBundleMode: Bool

    init() {
        previousBundleMode = AppConfig.isUsingBundleMode
    }

    deinit {
        AppConfig.isUsingBundleMode = previousBundleMode
        BookDownloadIndexCache.shared.setCoreIndexIdsForTesting(nil)
    }

    @Test("BundleBookIndexEntry decodes authno when present, null, or omitted")
    func testDecodeBundleBookIndexEntryAuthno() throws {
        let json = """
        [
          {"bkid": 1, "filename": "1.sqlite.zst", "release": "v1.0", "size_zst": 53829, "authno": 513},
          {"bkid": 2, "filename": "2.sqlite.zst", "release": "v1.7", "size_zst": null, "authno": null},
          {"bkid": 3, "filename": "3.sqlite.zst", "release": "v1.0"}
        ]
        """
        let data = try #require(json.data(using: .utf8))
        let entries = try JSONDecoder().decode([BundleBookIndexEntry].self, from: data)

        #expect(entries.count == 3)
        #expect(entries[0].bkid == 1)
        #expect(entries[0].authno == 513)
        #expect(entries[1].authno == nil)
        #expect(entries[2].authno == nil)
    }

    @Test("Bundle Mode classifies books and authors using index.json snapshot including gap IDs")
    func testBundleModeIndexSnapshotClassification() {
        AppConfig.isUsingBundleMode = true
        BookDownloadIndexCache.shared.setCoreIndexIdsForTesting(
            (books: [1, 147_062, 151_203], authors: [513, 3169])
        )

        #expect(LibraryDataManager.isCoreBook(id: 1))
        #expect(!LibraryDataManager.shouldRemoveBook(id: 1))
        #expect(LibraryDataManager.isCoreBook(id: 147_062))
        #expect(LibraryDataManager.isCoreBook(id: 151_203))

        // Gap ID <= 151_203 (e.g. 32793 / 32794) and new ID > 151_203 are non-core
        #expect(!LibraryDataManager.isCoreBook(id: 32793))
        #expect(LibraryDataManager.shouldRemoveBook(id: 32793))
        #expect(LibraryDataManager.shouldRemoveBook(id: 32794))
        #expect(LibraryDataManager.shouldRemoveBook(id: 151_233))

        // Authors
        #expect(!LibraryDataManager.shouldRemoveAuthor(muallifId: 513))
        #expect(!LibraryDataManager.shouldRemoveAuthor(muallifId: 3169))
        #expect(LibraryDataManager.shouldRemoveAuthor(muallifId: 3181))
        #expect(LibraryDataManager.shouldRemoveAuthor(muallifId: 2514))
    }

    @Test("Full Mode classifies books offline via oNum without index.json")
    func testFullModeONumClassification() {
        AppConfig.isUsingBundleMode = false
        BookDownloadIndexCache.shared.setCoreIndexIdsForTesting(nil)

        let coreBook = BooksData(id: 147_062, book: "Core Book", archive: 19, muallif: 513)
        coreBook.oNum = 147_062
        coreBook.pdfCs = 3

        let gapImportedBook = BooksData(id: 32794, book: "Imported Gap Book", archive: 20, muallif: 3181)
        gapImportedBook.oNum = nil

        let newUpdateBook = BooksData(id: 151_233, book: "New Update Book", archive: 20, muallif: 3180)
        newUpdateBook.oNum = nil

        LibraryDataManager.shared.setBookForTesting(coreBook, forId: coreBook.id)
        LibraryDataManager.shared.setBookForTesting(gapImportedBook, forId: gapImportedBook.id)
        LibraryDataManager.shared.setBookForTesting(newUpdateBook, forId: newUpdateBook.id)
        defer {
            LibraryDataManager.shared.setBookForTesting(nil, forId: coreBook.id)
            LibraryDataManager.shared.setBookForTesting(nil, forId: gapImportedBook.id)
            LibraryDataManager.shared.setBookForTesting(nil, forId: newUpdateBook.id)
        }

        #expect(LibraryDataManager.isCoreBook(id: 147_062))
        #expect(!LibraryDataManager.shouldRemoveBook(id: 147_062))
        #expect(!LibraryDataManager.isCoreBook(id: 32794))
        #expect(LibraryDataManager.shouldRemoveBook(id: 32794))
        #expect(LibraryDataManager.shouldRemoveBook(id: 151_233))
    }

    @Test("Delete confirmation message formats single, uniform bulk, and mixed selections (Option 1)")
    func testDeleteConfirmationMessages() {
        AppConfig.isUsingBundleMode = true
        BookDownloadIndexCache.shared.setCoreIndexIdsForTesting(
            (books: [1, 2], authors: [513])
        )

        let core1 = BooksData(id: 1, book: "Kitab Inti 1", archive: 1, muallif: 513)
        let core2 = BooksData(id: 2, book: "Kitab Inti 2", archive: 1, muallif: 513)
        let custom1 = BooksData(id: 32793, book: "Kitab Import 1", archive: 20, muallif: 3181)
        let custom2 = BooksData(id: 151_233, book: "Kitab Update 2", archive: 20, muallif: 3180)

        let singleCore = LibraryViewModel.deleteConfirmationMessage(for: [core1])
        let singleCustom = LibraryViewModel.deleteConfirmationMessage(for: [custom1])
        let multiCore = LibraryViewModel.deleteConfirmationMessage(for: [core1, core2])
        let multiCustom = LibraryViewModel.deleteConfirmationMessage(for: [custom1, custom2])
        let mixed = LibraryViewModel.deleteConfirmationMessage(for: [core1, custom1])

        #expect(singleCore == String(localized: .Library.deleteDownloadedSingleConfirmation(core1.book)))
        #expect(singleCustom == String(localized: .Library.deleteCustomSingleConfirmation(custom1.book)))
        #expect(multiCore == String(localized: .Library.deleteDownloadedMultipleConfirmation(2)))
        #expect(multiCustom == String(localized: .Library.deleteCustomMultipleConfirmation(2)))
        #expect(mixed.contains("• " + String(localized: .Library.deleteCustomMultipleConfirmation(1))))
        #expect(mixed.contains("• " + String(localized: .Library.deleteDownloadedMultipleConfirmation(1))))
    }
}
