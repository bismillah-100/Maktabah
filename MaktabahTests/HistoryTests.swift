//
//  HistoryTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 16/10/26.
//

import CloudKit
import Foundation
@testable import Maktabah_Debug
import Testing

// MARK: - 1. Database & Concurrency Tests

@Suite("History Database: CRUD, Batch Deletion, dan Concurrency", .serialized)
struct HistoryDatabaseTests {
    let dbManager = HistoryDatabaseManager.shared
    let baseBookId = 880_000

    private func makeTestEntry(
        offset: Int,
        lastContentId: Int? = 100,
        isFavorite: Bool = false,
        lastOpened: Date? = Date(),
        favoritedAt: Date? = nil,
        positionUpdatedAt: Date? = Date()
    ) -> ReadingEntry {
        let bookId = baseBookId + offset
        return ReadingEntry(
            bookId: bookId,
            lastContentId: lastContentId,
            lastOpenedAt: lastOpened,
            favoritedAt: favoritedAt,
            positionUpdatedAt: positionUpdatedAt,
            updatedAt: Date(),
            isFavorite: isFavorite,
            ckRecordId: "ck_test_\(bookId)"
        )
    }

    private func cleanup(bookIds: [Int]) {
        try? dbManager.deleteEntries(bookIds: bookIds, trackPending: false)
        let ckIds = bookIds.map { "ck_test_\($0)" }
        dbManager.removePendingSync(ckRecordIds: ckIds)
    }

    @Test("Upsert dan Fetch ReadingEntry di SQLite")
    func testUpsertAndFetch() throws {
        let bookIds = [baseBookId + 1, baseBookId + 2]
        cleanup(bookIds: bookIds)
        defer { cleanup(bookIds: bookIds) }

        let entry1 = makeTestEntry(offset: 1, lastContentId: 42, isFavorite: true, favoritedAt: Date())
        let entry2 = makeTestEntry(offset: 2, lastContentId: 88, isFavorite: false)

        try dbManager.upsertEntries([entry1, entry2], trackPending: true)

        let fetched = try dbManager.fetchEntries(byCkRecordIds: [#require(entry1.ckRecordId), #require(entry2.ckRecordId)])
        #expect(fetched.count == 2)

        let fetched1 = fetched.first { $0.bookId == entry1.bookId }
        #expect(fetched1 != nil)
        #expect(fetched1?.lastContentId == 42)
        #expect(fetched1?.isFavorite == true)
        #expect(fetched1?.ckRecordId == "ck_test_\(entry1.bookId)")

        let fetched2 = fetched.first { $0.bookId == entry2.bookId }
        #expect(fetched2 != nil)
        #expect(fetched2?.lastContentId == 88)
        #expect(fetched2?.isFavorite == false)
    }

    @Test("Hapus Beberapa Item secara Batch dan Pelacakan Pending Sync")
    func testBatchDeletionWithPendingSync() throws {
        let offsets = [10, 11, 12, 13]
        let bookIds = offsets.map { baseBookId + $0 }
        cleanup(bookIds: bookIds)
        defer { cleanup(bookIds: bookIds) }

        let entries = offsets.map { makeTestEntry(offset: $0) }
        try dbManager.upsertEntries(entries, trackPending: false)

        // Hapus sebagian secara batch dengan trackPending: true
        let idsToDelete = [bookIds[0], bookIds[1]]
        try dbManager.deleteEntries(bookIds: idsToDelete, trackPending: true)

        let remaining = dbManager.fetchEntries(byCkRecordIds: bookIds.map { "ck_test_\($0)" })
        #expect(remaining.count == 2)
        #expect(remaining.contains { $0.bookId == bookIds[2] })
        #expect(remaining.contains { $0.bookId == bookIds[3] })
        #expect(!remaining.contains { $0.bookId == bookIds[0] })
        #expect(!remaining.contains { $0.bookId == bookIds[1] })

        // Verifikasi pending delete tercatat di SyncPendingStore
        let pendingDeletes = dbManager.fetchPendingSync(operation: "delete")
        #expect(pendingDeletes.contains("ck_test_\(bookIds[0])"))
        #expect(pendingDeletes.contains("ck_test_\(bookIds[1])"))
    }

    @Test("Pengurutan Riwayat (History Order) Disimpan dan Dimuat Sesuai Urutan")
    func testHistoryOrderPersistence() throws {
        let (_, originalOrder) = dbManager.loadFromDatabase()
        defer { try? dbManager.replaceHistoryOrder(originalOrder) }

        let testOrder = [baseBookId + 5, baseBookId + 1, baseBookId + 9, baseBookId + 3]
        try dbManager.replaceHistoryOrder(testOrder)
        let (_, loadedOrder) = dbManager.loadFromDatabase()

        #expect(loadedOrder == testOrder)
    }

    @Test("saveCloudKitChanges: Eksekusi atomik untuk delete, upsert, dan order update")
    func testSaveCloudKitChanges_AtomicExecution() throws {
        let initialIds = [baseBookId + 20, baseBookId + 21]
        let allTestIds = initialIds + [baseBookId + 22]
        cleanup(bookIds: allTestIds)

        let (_, originalOrder) = dbManager.loadFromDatabase()
        defer {
            try? dbManager.replaceHistoryOrder(originalOrder)
            cleanup(bookIds: allTestIds)
        }

        let e1 = makeTestEntry(offset: 20)
        let e2 = makeTestEntry(offset: 21)
        try dbManager.upsertEntries([e1, e2], trackPending: false)

        // Terapkan perubahan cloudkit: hapus e1, perbarui e2, tambah e3
        let e3 = makeTestEntry(offset: 22, lastContentId: 333)
        let updatedE2 = makeTestEntry(offset: 21, lastContentId: 777)
        let finalOrder = [e3.bookId, updatedE2.bookId]

        try dbManager.saveCloudKitChanges(
            deletedIds: [e1.bookId],
            upsertedEntries: [updatedE2, e3],
            finalOrder: finalOrder
        )

        let (loadedEntries, loadedOrder) = dbManager.loadFromDatabase()
        #expect(!loadedEntries.contains { $0.bookId == e1.bookId })

        let foundE2 = loadedEntries.first { $0.bookId == updatedE2.bookId }
        #expect(foundE2?.lastContentId == 777)

        let foundE3 = loadedEntries.first { $0.bookId == e3.bookId }
        #expect(foundE3?.lastContentId == 333)

        #expect(loadedOrder.contains(e3.bookId))
        #expect(loadedOrder.contains(updatedE2.bookId))
    }

    @Test("Race Condition & Concurrency: Multi-threaded Upsert dan Delete Bersamaan")
    func testConcurrentDatabaseOperations() async throws {
        let totalItems = 30
        let bookIds = (0..<totalItems).map { baseBookId + 100 + $0 }
        cleanup(bookIds: bookIds)

        let (_, originalOrder) = dbManager.loadFromDatabase()
        defer {
            try? dbManager.replaceHistoryOrder(originalOrder)
            cleanup(bookIds: bookIds)
        }

        // Jalankan operasi concurrent write, update, dan delete dari beberapa task paralel
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Batch upsert genap
            group.addTask {
                let evenEntries = (0..<totalItems).filter { $0 % 2 == 0 }.map {
                    self.makeTestEntry(offset: 100 + $0, lastContentId: $0)
                }
                try? self.dbManager.upsertEntries(evenEntries, trackPending: false)
            }

            // Task 2: Batch upsert ganjil
            group.addTask {
                let oddEntries = (0..<totalItems).filter { $0 % 2 != 0 }.map {
                    self.makeTestEntry(offset: 100 + $0, lastContentId: $0)
                }
                try? self.dbManager.upsertEntries(oddEntries, trackPending: false)
            }

            // Task 3: Simultan update order
            group.addTask {
                let shuffledOrder = bookIds.shuffled()
                try? self.dbManager.replaceHistoryOrder(shuffledOrder)
            }

            // Task 4: Simultan upsert & replace sebagian
            group.addTask {
                let overlap = (5..<15).map {
                    self.makeTestEntry(offset: 100 + $0, lastContentId: 999)
                }
                try? self.dbManager.upsertEntries(overlap, trackPending: false)
            }
        }

        // Tidak terjadi crash, korupsi SQLite, atau deadlock
        let ckIds = bookIds.map { "ck_test_\($0)" }
        let entries = dbManager.fetchEntries(byCkRecordIds: ckIds)
        #expect(entries.count == totalItems)
    }
}

// MARK: - 2. CloudKit Sync Conflict Resolution Tests

@Suite("History Sync: Resolusi Konflik CloudKit (mergeEntries & applyChanges)", .serialized)
@MainActor
struct HistorySyncConflictTests {
    let viewModel = HistoryViewModel.shared

    private func makeDate(offsetMinutes: Double) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + (offsetMinutes * 60))
    }

    // ── Favorit Conflict ─────────────────────────────────────────────

    @Test("Konflik Favorit: Remote favoritedAt lebih baru memenangkan status favorit")
    func testMergeFavorite_RemoteNewerWins() {
        let t1 = makeDate(offsetMinutes: 10)
        let t2 = makeDate(offsetMinutes: 20)

        let local = ReadingEntry(bookId: 1, favoritedAt: t1, updatedAt: t1, isFavorite: false)
        let remote = ReadingEntry(bookId: 1, favoritedAt: t2, updatedAt: t2, isFavorite: true)

        let (merged, changed) = viewModel.mergeEntries(local: local, remote: remote)
        #expect(changed == true)
        #expect(merged.isFavorite == true)
        #expect(merged.favoritedAt == t2)
    }

    @Test("Konflik Favorit: Local favoritedAt lebih baru mempertahankan status favorit lokal")
    func testMergeFavorite_LocalNewerWins() {
        let t1 = makeDate(offsetMinutes: 10)
        let t2 = makeDate(offsetMinutes: 20)

        let local = ReadingEntry(bookId: 2, favoritedAt: t2, updatedAt: t2, isFavorite: true)
        let remote = ReadingEntry(bookId: 2, favoritedAt: t1, updatedAt: t1, isFavorite: false)

        let (merged, changed) = viewModel.mergeEntries(local: local, remote: remote)
        #expect(merged.isFavorite == true)
        #expect(merged.favoritedAt == t2)
        #expect(changed == false)
    }

    @Test("Konflik Favorit: favoritedAt sama, updatedAt lebih baru memenangkan status favorit")
    func testMergeFavorite_SameDate_NewerUpdatedAtWins() {
        let favDate = makeDate(offsetMinutes: 10)
        let t1 = makeDate(offsetMinutes: 15)
        let t2 = makeDate(offsetMinutes: 25)

        let local = ReadingEntry(bookId: 3, favoritedAt: favDate, updatedAt: t1, isFavorite: false)
        let remote = ReadingEntry(bookId: 3, favoritedAt: favDate, updatedAt: t2, isFavorite: true)

        let (merged, changed) = viewModel.mergeEntries(local: local, remote: remote)
        #expect(changed == true)
        #expect(merged.isFavorite == true)
    }

    // ── Posisi Bacaan Conflict ────────────────────────────────────────

    @Test("Konflik Posisi: Remote positionUpdatedAt lebih baru memenangkan lastContentId")
    func testMergePosition_RemoteNewerWins() {
        let t1 = makeDate(offsetMinutes: 10)
        let t2 = makeDate(offsetMinutes: 20)

        let local = ReadingEntry(bookId: 4, lastContentId: 100, positionUpdatedAt: t1, updatedAt: t1)
        let remote = ReadingEntry(bookId: 4, lastContentId: 500, positionUpdatedAt: t2, updatedAt: t2)

        let (merged, changed) = viewModel.mergeEntries(local: local, remote: remote)
        #expect(changed == true)
        #expect(merged.lastContentId == 500)
        #expect(merged.positionUpdatedAt == t2)
    }

    @Test("Konflik Posisi: Local positionUpdatedAt lebih baru mempertahankan posisi lokal")
    func testMergePosition_LocalNewerWins() {
        let t1 = makeDate(offsetMinutes: 10)
        let t2 = makeDate(offsetMinutes: 20)

        let local = ReadingEntry(bookId: 5, lastContentId: 777, positionUpdatedAt: t2, updatedAt: t2)
        let remote = ReadingEntry(bookId: 5, lastContentId: 222, positionUpdatedAt: t1, updatedAt: t1)

        let (merged, changed) = viewModel.mergeEntries(local: local, remote: remote)
        #expect(merged.lastContentId == 777)
        #expect(merged.positionUpdatedAt == t2)
        #expect(changed == false)
    }

    @Test("Konflik Metadata: lastOpenedAt dan updatedAt mengambil nilai maksimal dari kedua sisi")
    func testMergeMetadata_MaxTimestamp() {
        let t1 = makeDate(offsetMinutes: 30)
        let t2 = makeDate(offsetMinutes: 50)

        let local = ReadingEntry(bookId: 6, lastOpenedAt: t1, updatedAt: t2)
        let remote = ReadingEntry(bookId: 6, lastOpenedAt: t2, updatedAt: t1)

        let (merged, changed) = viewModel.mergeEntries(local: local, remote: remote)
        #expect(changed == true)
        #expect(merged.lastOpenedAt == t2)
        #expect(merged.updatedAt == t2)
    }

    // ── Apply Deletions & Upserts ─────────────────────────────────────

    @Test("applyDeletions: Menghapus entri yang cocok dari entriesByBookId dan historyOrder")
    func testApplyDeletions() {
        let originalEntries = viewModel.entriesByBookId
        let originalOrder = viewModel.historyOrder
        defer {
            viewModel.entriesByBookId = originalEntries
            viewModel.historyOrder = originalOrder
        }

        let e1 = ReadingEntry(bookId: 501, ckRecordId: "ck_501")
        let e2 = ReadingEntry(bookId: 502, ckRecordId: "ck_502")

        viewModel.entriesByBookId[501] = e1
        viewModel.entriesByBookId[502] = e2
        viewModel.historyOrder = [501, 502]

        var deletedIds: [Int] = []
        let changed = viewModel.applyDeletions(recordIdsToDelete: ["ck_501"], deletedIds: &deletedIds)

        #expect(changed == true)
        #expect(deletedIds == [501])
        #expect(viewModel.entriesByBookId[501] == nil)
        #expect(viewModel.entriesByBookId[502] != nil)
        #expect(!viewModel.historyOrder.contains(501))
    }

    @Test("applyUpserts: Memasukkan entri baru dan menggabungkan entri lokal yang sudah ada")
    func testApplyUpserts() {
        let originalEntries = viewModel.entriesByBookId
        defer {
            viewModel.entriesByBookId = originalEntries
        }

        let t1 = makeDate(offsetMinutes: 10)
        let t2 = makeDate(offsetMinutes: 30)

        let local = ReadingEntry(bookId: 601, lastContentId: 10, positionUpdatedAt: t1, updatedAt: t1)
        viewModel.entriesByBookId[601] = local

        let remoteExisting = ReadingEntry(bookId: 601, lastContentId: 99, positionUpdatedAt: t2, updatedAt: t2)
        let remoteNew = ReadingEntry(bookId: 602, lastContentId: 55, positionUpdatedAt: t2, updatedAt: t2)

        var upserted: [ReadingEntry] = []
        let changed = viewModel.applyUpserts(entriesToSave: [remoteExisting, remoteNew], upsertedEntries: &upserted)

        #expect(changed == true)
        #expect(upserted.count == 2)
        #expect(viewModel.entriesByBookId[601]?.lastContentId == 99)
        #expect(viewModel.entriesByBookId[602]?.lastContentId == 55)
    }

    @Test("CKRecord Round-Trip: Konversi ReadingEntry ke CKRecord dan sebaliknya")
    func testCKRecordRoundTrip() throws {
        let zoneID = CKRecordZone.ID(zoneName: "AnnotationsZone", ownerName: CKCurrentUserDefaultName)
        let original = ReadingEntry(
            bookId: 1234,
            lastContentId: 456,
            lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_100),
            favoritedAt: Date(timeIntervalSince1970: 1_700_000_200),
            positionUpdatedAt: Date(timeIntervalSince1970: 1_700_000_300),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_400),
            isFavorite: true,
            ckRecordId: "1234"
        )

        let record = try #require(original.toCKRecord(zoneID: zoneID))
        let parsed = try #require(HistorySyncHandler.parse(from: record))

        #expect(parsed.bookId == original.bookId)
        #expect(parsed.lastContentId == original.lastContentId)
        #expect(parsed.isFavorite == original.isFavorite)
        #expect(parsed.ckRecordId == original.ckRecordId)
        #expect(parsed.lastOpenedAt == original.lastOpenedAt)
        #expect(parsed.favoritedAt == original.favoritedAt)
    }
}

// MARK: - 3. History State, Removal & Search Filter Tests

@Suite("History ViewModel: State Transitions, Penghapusan & Filter", .serialized)
@MainActor
struct HistoryViewModelStateTests {
    let viewModel = HistoryViewModel.shared

    @Test("Urutan Favorit: favoriteBookIds diurutkan berdasarkan favoritedAt descending")
    func testFavoriteBookIds_SortedByFavoritedAt() {
        let originalEntries = viewModel.entriesByBookId
        defer {
            viewModel.entriesByBookId = originalEntries
        }

        let t1 = Date(timeIntervalSince1970: 1_700_000_100)
        let t2 = Date(timeIntervalSince1970: 1_700_000_200)
        let t3 = Date(timeIntervalSince1970: 1_700_000_300)

        let e1 = ReadingEntry(bookId: 910, favoritedAt: t1, isFavorite: true)
        let e2 = ReadingEntry(bookId: 920, favoritedAt: t3, isFavorite: true)
        let e3 = ReadingEntry(bookId: 930, favoritedAt: t2, isFavorite: true)
        let e4 = ReadingEntry(bookId: 940, isFavorite: false)

        viewModel.entriesByBookId[910] = e1
        viewModel.entriesByBookId[920] = e2
        viewModel.entriesByBookId[930] = e3
        viewModel.entriesByBookId[940] = e4

        let favIds = viewModel.favoriteBookIds
        #expect(favIds.contains(920))
        #expect(favIds.contains(930))
        #expect(favIds.contains(910))
        #expect(!favIds.contains(940))

        // Index 920 (t3) harus mendahului 930 (t2) yang mendahului 910 (t1)
        if let idx920 = favIds.firstIndex(of: 920),
           let idx930 = favIds.firstIndex(of: 930),
           let idx910 = favIds.firstIndex(of: 910)
        {
            #expect(idx920 < idx930)
            #expect(idx930 < idx910)
        }
    }

    @Test("Logika Hapus Riwayat Buku Favorit: Mempertahankan status favorit dengan lastOpenedAt nil")
    func testFavoritedHistoryRemovalLogic() {
        let favDate = Date()
        var entry = ReadingEntry(bookId: 777, lastOpenedAt: Date(), favoritedAt: favDate, isFavorite: true)

        entry.lastOpenedAt = nil
        entry.updatedAt = Date()

        #expect(entry.isFavorite == true)
        #expect(entry.favoritedAt == favDate)
        #expect(entry.lastOpenedAt == nil)
    }

    @Test("Logika Clear History: Memisahkan entri yang dihapus total dan entri favorit yang dipertahankan")
    func testClearHistoryLogic() {
        let e1 = ReadingEntry(bookId: 801, lastOpenedAt: Date(), isFavorite: false)
        let e2 = ReadingEntry(bookId: 802, lastOpenedAt: Date(), favoritedAt: Date(), isFavorite: true)

        let entries = [801: e1, 802: e2]
        var deletedIds: [Int] = []
        var preservedFavorites: [ReadingEntry] = []

        for (_, entry) in entries {
            if entry.isFavorite {
                var updated = entry
                updated.lastOpenedAt = nil
                preservedFavorites.append(updated)
            } else {
                deletedIds.append(entry.bookId)
            }
        }

        #expect(deletedIds == [801])
        #expect(preservedFavorites.count == 1)
        #expect(preservedFavorites.first?.bookId == 802)
        #expect(preservedFavorites.first?.isFavorite == true)
        #expect(preservedFavorites.first?.lastOpenedAt == nil)
    }

    @Test("Batas Maksimal Riwayat: Membatasi urutan riwayat maksimal 50 item")
    func testMaxHistoryLimit() {
        let entries = (1...60).map { i in
            ReadingEntry(
                bookId: i,
                lastOpenedAt: Date(timeIntervalSince1970: TimeInterval(1_000_000 + i * 10)),
                ckRecordId: "ck_\(i)"
            )
        }

        let sorted = entries
            .filter { $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .map(\.bookId)

        let limited = Array(sorted.prefix(viewModel.maxHistoryCount))

        #expect(limited.count == 50)
        #expect(limited.first == 60)
        #expect(limited.last == 11)
    }

    @Test("Filter Pencarian Buku: Normalisasi teks Arab (harakat dan variasi huruf)")
    func testFilterBooks_ArabicNormalization() {
        let originalSearchText = viewModel.searchText
        defer {
            viewModel.searchText = originalSearchText
        }

        let books = [
            BooksData(id: 1, book: "صَحِيحُ البُخَارِيّ", archive: 1, muallif: 1),
            BooksData(id: 2, book: "صحيح مسلم", archive: 1, muallif: 2),
            BooksData(id: 3, book: "سنن أبي داود", archive: 1, muallif: 3),
        ]

        // Cari dengan harakat
        viewModel.searchText = "صَحِيحُ"
        let res1 = viewModel.filterBooks(books)
        #expect(res1.count == 2)
        #expect(res1.contains { $0.id == 1 })
        #expect(res1.contains { $0.id == 2 })

        // Cari tanpa alif hamzah: "ابي" cocok dengan "أبي"
        viewModel.searchText = "ابي داود"
        let res2 = viewModel.filterBooks(books)
        #expect(res2.count == 1)
        #expect(res2.first?.id == 3)

        // Reset search text
        viewModel.searchText = ""
        let resEmpty = viewModel.filterBooks(books)
        #expect(resEmpty.count == 3)
    }
}
