//
//  BookConnectionTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 18/10/26.
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("BookConnection State & Idempotency Tests")
struct BookConnectionTests {
    private func createTempDatabase() throws -> (SQLiteDatabase, String) {
        let tempPath = NSTemporaryDirectory().appending("test_book_connection_\(UUID().uuidString).sqlite")
        let db = try SQLiteDatabase(path: tempPath)
        return (db, tempPath)
    }

    @Test("setDatabase mencatat archiveId dan membersihkannya saat disconnect")
    func testArchiveIdTracking() throws {
        let connection = BookConnection()
        #expect(connection.currentArchiveId == nil)
        #expect(connection.db == nil)

        let (mockDb, tempPath) = try createTempDatabase()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        connection.setDatabase(mockDb, archiveId: 7)
        #expect(connection.currentArchiveId == 7)
        #expect(connection.db != nil)

        // Disconnect
        connection.setDatabase(nil)
        #expect(connection.currentArchiveId == nil)
        #expect(connection.db == nil)
    }

    @Test("Idempotent connect keluar lebih awal tanpa error jika archiveId sama dan db aktif")
    func testIdempotentConnect() throws {
        let connection = BookConnection()
        let (mockDb, tempPath) = try createTempDatabase()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        connection.setDatabase(mockDb, archiveId: 3)
        #expect(connection.currentArchiveId == 3)

        // Menghubungkan ke archive 3 dengan force: false tidak mencoba membuka ulang file
        #expect(throws: Never.self) {
            try connection.connect(archive: 3, force: false)
        }
        #expect(connection.currentArchiveId == 3)
    }
}
