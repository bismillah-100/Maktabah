//
//  IntegrationCacheTests.swift
//  MaktabahTests
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("IntegrationCache Tests", .serialized)
final class IntegrationCacheTests {
    let cache = IntegrationCache.shared
    let updateManager = BookUpdateManager.shared
    let archiveIntegrator = BookArchiveIntegrator.shared
    private let previousBundleMode: Bool

    init() {
        previousBundleMode = AppConfig.isUsingBundleMode
        // Simulasikan bundle mode aktif untuk menguji cache integrasi
        AppConfig.isUsingBundleMode = true
    }

    deinit {
        AppConfig.isUsingBundleMode = previousBundleMode
    }

    @Test("Tandai dan batalkan status integrasi buku di IntegrationCache")
    func testMarkAndUnmarkIntegrated() {
        let testArchiveId = 987
        let testBookId = 12345

        // Reset state awal
        cache.unmarkIntegrated(bookId: testBookId, archiveId: testArchiveId)
        #expect(cache.isIntegrated(bookId: testBookId, archiveId: testArchiveId) == false)

        // Mark as integrated
        cache.markIntegrated(bookId: testBookId, archiveId: testArchiveId)
        #expect(cache.isIntegrated(bookId: testBookId, archiveId: testArchiveId) == true)

        // Unmark
        cache.unmarkIntegrated(bookId: testBookId, archiveId: testArchiveId)
        #expect(cache.isIntegrated(bookId: testBookId, archiveId: testArchiveId) == false)
    }

    @Test("BookArchiveIntegrator.isBookIntegrated memetakan lookup O(1) ke IntegrationCache")
    func testBookArchiveIntegrator_isBookIntegrated() {
        let testBook = BooksData(id: 54321, book: "كتاب تجريبي", archive: 988, muallif: 1)

        cache.unmarkIntegrated(bookId: testBook.id, archiveId: testBook.archive)
        #expect(archiveIntegrator.isBookIntegrated(testBook) == false)

        cache.markIntegrated(bookId: testBook.id, archiveId: testBook.archive)
        #expect(archiveIntegrator.isBookIntegrated(testBook) == true)

        // Cleanup
        cache.unmarkIntegrated(bookId: testBook.id, archiveId: testBook.archive)
    }

    @Test("BookUpdateManager.integrateBooks menandai kitab terintegrasi di IntegrationCache")
    @MainActor
    func testBookUpdateManager_integrateBooks() {
        let metadata = BookMetadata(
            bkid: 77701,
            cat: 1,
            bk: "صحيح البخاري",
            archive: 989,
            betaka: nil,
            authno: 1,
            inf: nil,
            tafseerNam: nil,
            bVer: 1,
            link: nil,
            pdfCs: 0
        )

        cache.unmarkIntegrated(bookId: metadata.bkid, archiveId: metadata.archive)
        #expect(cache.isIntegrated(bookId: metadata.bkid, archiveId: metadata.archive) == false)

        // Panggil integrateBooks dari BookUpdateManager
        updateManager.integrateBooks(metadata: metadata)

        // Verifikasi terintegrasi
        #expect(cache.isIntegrated(bookId: metadata.bkid, archiveId: metadata.archive) == true)

        // Cleanup
        cache.unmarkIntegrated(bookId: metadata.bkid, archiveId: metadata.archive)
    }

    @Test("Race Condition & Concurrency: Multi-book concurrent mark/unmark pada archive yang sama")
    func testConcurrentIntegration_sameArchive() async {
        let archiveId = 991
        let bookCount = 50
        let bookIds = (1 ... bookCount).map { 10000 + $0 }

        // Pastikan bersih
        for id in bookIds {
            cache.unmarkIntegrated(bookId: id, archiveId: archiveId)
        }

        // Jalankan operasi mark concurrently dengan TaskGroup
        await withTaskGroup(of: Void.self) { group in
            for id in bookIds {
                group.addTask {
                    self.cache.markIntegrated(bookId: id, archiveId: archiveId)
                }
            }
        }

        // Verifikasi bahwa seluruh 50 buku terdaftar tanpa ada yang tertimpa/hilang karena race condition
        for id in bookIds {
            #expect(cache.isIntegrated(bookId: id, archiveId: archiveId) == true)
        }

        // Jalankan unmark concurrently untuk separuh buku
        let unmarkGroup = Array(bookIds.prefix(25))
        let retainGroup = Array(bookIds.suffix(25))

        await withTaskGroup(of: Void.self) { group in
            for id in unmarkGroup {
                group.addTask {
                    self.cache.unmarkIntegrated(bookId: id, archiveId: archiveId)
                }
            }
        }

        // Verifikasi state akhir setelah operasi concurrent
        for id in unmarkGroup {
            #expect(cache.isIntegrated(bookId: id, archiveId: archiveId) == false)
        }
        for id in retainGroup {
            #expect(cache.isIntegrated(bookId: id, archiveId: archiveId) == true)
        }

        // Cleanup
        for id in retainGroup {
            cache.unmarkIntegrated(bookId: id, archiveId: archiveId)
        }
    }

    @Test("Race Condition: Integrasi paralel multi-buku lintas archive berbeda secara bersamaan")
    func testConcurrentIntegration_multipleArchives() async {
        let archives = [992, 993, 994, 995]
        let booksPerArchive = 20

        // Buat pasangan (archiveId, bookId)
        var tasks: [(archiveId: Int, bookId: Int)] = []
        for arch in archives {
            for b in 1 ... booksPerArchive {
                tasks.append((archiveId: arch, bookId: arch * 1000 + b))
            }
        }

        // Eksekusi concurrent mark
        await withTaskGroup(of: Void.self) { group in
            for task in tasks {
                group.addTask {
                    self.cache.markIntegrated(bookId: task.bookId, archiveId: task.archiveId)
                }
            }
        }

        // Verifikasi semua tercatat di archive masing-masing
        for task in tasks {
            let isDone = cache.isIntegrated(bookId: task.bookId, archiveId: task.archiveId)
            #expect(isDone == true)
        }

        // Cleanup
        for task in tasks {
            cache.unmarkIntegrated(bookId: task.bookId, archiveId: task.archiveId)
        }
    }

    // MARK: - Integration Progress State Tests

    @Test("BundleArchiveDownloadProgressState: Pembaruan fase integrasi (.fts -> 0.5, .data -> 0.9)")
    @MainActor
    func testBundleArchiveDownloadProgressState_integrationPhases() {
        let state = BundleArchiveDownloadProgressState(
            title: "كتاب تجريبي",
            message: "Sedang mengunduh",
            mode: .downloading,
            totalSizeString: "10 MB"
        )

        // Transisi ke integrating
        state.transitionToIntegrating()
        #expect(state.mode == .integrating)
        #expect(state.progress == 0)

        // Fase FTS (50%)
        state.updateIntegrationPhase(.fts)
        #expect(state.progress == 0.5)

        // Fase Data (90%)
        state.updateIntegrationPhase(.data)
        #expect(state.progress == 0.9)
    }
}
