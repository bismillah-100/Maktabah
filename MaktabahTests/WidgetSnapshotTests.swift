//
//  WidgetSnapshotTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 08/11/26.
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("Widget Snapshot & Local-First Resilience Suite", .serialized)
struct WidgetSnapshotTests {
    // MARK: - Helper Data Creators

    private func makeHistoryItem(id: String, bookId: Int, title: String) -> HistorySnapshotItem {
        HistorySnapshotItem(
            id: id,
            bookId: bookId,
            bookTitle: title,
            contentId: 1,
            date: Date()
        )
    }

    private func makeAnnotationItem(id: String, bookId: Int, content: String) -> AnnotationSnapshotItem {
        AnnotationSnapshotItem(
            id: id,
            bookId: bookId,
            contentId: 1,
            bookTitle: "Kitab Test",
            content: content,
            colorHex: "#FF9300",
            type: 0,
            date: Date()
        )
    }

    // MARK: - 1. Resolve & Empty Remote Protection Tests

    @Test("Resolve: Mencegah remote kosong menimpa snapshot lokal yang sudah terisi (History)")
    func testResolve_protectsLocalHistoryFromEmptyRemote() async {
        let localItem1 = makeHistoryItem(id: "h1", bookId: 101, title: "Kitab Al-Umm")
        let localItem2 = makeHistoryItem(id: "h2", bookId: 102, title: "Sahih Al-Bukhari")

        var localSnapshot = HistorySnapshot(items: [localItem1, localItem2])
        localSnapshot.generation = 1
        localSnapshot.lastUpdated = Date(timeIntervalSince1970: 1000)

        // Remote lebih baru (generasi 2) namun items kosong (misal perangkat baru atau sync glitch)
        var remoteSnapshot = HistorySnapshot(items: [])
        remoteSnapshot.generation = 2
        remoteSnapshot.lastUpdated = Date(timeIntervalSince1970: 2000)

        let (resolved, didChange) = await HistorySnapshot.resolve(
            remote: remoteSnapshot,
            local: localSnapshot
        )

        // Snapshot tidak boleh menjadi kosong
        #expect(resolved != nil)
        #expect(resolved?.items.count == 2)
        #expect(resolved?.items.first?.id == "h1")
        #expect(didChange == false)
    }

    @Test("Resolve: Mencegah remote kosong menimpa snapshot lokal yang sudah terisi (Annotation)")
    func testResolve_protectsLocalAnnotationFromEmptyRemote() async {
        let localAnno = makeAnnotationItem(id: "a1", bookId: 201, content: "Kutipan Penting")

        var localSnapshot = AnnotationSnapshot(items: [localAnno])
        localSnapshot.generation = 2
        localSnapshot.lastUpdated = Date(timeIntervalSince1970: 5000)

        var remoteSnapshot = AnnotationSnapshot(items: [])
        remoteSnapshot.generation = 5
        remoteSnapshot.lastUpdated = Date(timeIntervalSince1970: 8000)

        let (resolved, didChange) = await AnnotationSnapshot.resolve(
            remote: remoteSnapshot,
            local: localSnapshot
        )

        #expect(resolved != nil)
        #expect(resolved?.items.count == 1)
        #expect(resolved?.items.first?.content == "Kutipan Penting")
        #expect(didChange == false)
    }

    @Test("Resolve: Menerapkan remote jika memiliki data baru yang valid dan generasi lebih tinggi")
    func testResolve_appliesNewerRemoteWhenPopulated() async {
        let localItem = makeHistoryItem(id: "h1", bookId: 101, title: "Kitab Lama")
        var localSnapshot = HistorySnapshot(items: [localItem])
        localSnapshot.generation = 1
        localSnapshot.lastUpdated = Date(timeIntervalSince1970: 1000)

        let remoteItem1 = makeHistoryItem(id: "h1", bookId: 101, title: "Kitab Lama")
        let remoteItem2 = makeHistoryItem(id: "h2", bookId: 102, title: "Kitab Baru")
        var remoteSnapshot = HistorySnapshot(items: [remoteItem1, remoteItem2])
        remoteSnapshot.generation = 2
        remoteSnapshot.lastUpdated = Date(timeIntervalSince1970: 2000)

        let (resolved, didChange) = await HistorySnapshot.resolve(
            remote: remoteSnapshot,
            local: localSnapshot
        )

        #expect(resolved != nil)
        #expect(resolved?.items.count == 2)
        #expect(didChange == true)
    }

    @Test("Resolve: Mengabaikan snapshot remote yang lebih usang")
    func testResolve_ignoresStaleRemote() async {
        let localItem = makeHistoryItem(id: "h1", bookId: 101, title: "Kitab Terkini")
        var localSnapshot = HistorySnapshot(items: [localItem])
        localSnapshot.generation = 10
        localSnapshot.lastUpdated = Date(timeIntervalSince1970: 5000)

        let remoteItem = makeHistoryItem(id: "h0", bookId: 100, title: "Kitab Usang")
        var remoteSnapshot = HistorySnapshot(items: [remoteItem])
        remoteSnapshot.generation = 5
        remoteSnapshot.lastUpdated = Date(timeIntervalSince1970: 2000)

        let (resolved, didChange) = await HistorySnapshot.resolve(
            remote: remoteSnapshot,
            local: localSnapshot
        )

        #expect(resolved?.items.first?.id == "h1")
        #expect(didChange == false)
    }

    @Test("Resolve: Mengizinkan remote kosong jika snapshot lokal memang belum memiliki data")
    func testResolve_allowsEmptyRemoteWhenLocalIsAlsoEmpty() async {
        var localSnapshot = HistorySnapshot(items: [])
        localSnapshot.generation = 1
        localSnapshot.lastUpdated = Date(timeIntervalSince1970: 1000)

        var remoteSnapshot = HistorySnapshot(items: [])
        remoteSnapshot.generation = 2
        remoteSnapshot.lastUpdated = Date(timeIntervalSince1970: 2000)

        let (resolved, didChange) = await HistorySnapshot.resolve(
            remote: remoteSnapshot,
            local: localSnapshot
        )

        #expect(resolved?.items.isEmpty == true)
        #expect(didChange == false)
    }

    // MARK: - 2. FileCoordinator Tests

    @Test("FileCoordinator: Mampu membaca berkas langsung sebagai fallback yang tangguh")
    func testFileCoordinator_readsCoordinatedOrDirect() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetFileCoordinatorTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fileURL = tempDir.appendingPathComponent("TestSnapshot.json")
        let dummyPayload = Data("{\"test\": true}".utf8)

        // Tulis data menggunakan FileCoordinator
        await FileCoordinator.shared.write(data: dummyPayload, to: fileURL)

        // Baca kembali
        let readData = await FileCoordinator.shared.read(url: fileURL)
        #expect(readData != nil)
        #expect(readData == dummyPayload)
    }
}
