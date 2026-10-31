//
//  DatabaseMigrationTests.swift
//  MaktabahTests
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("Database Migration & Collision Resolution Suite", .serialized)
@MainActor
struct DatabaseMigrationTests {
    private func createTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaktabahMigrationTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func createDummyFiles(at dir: URL, filenames: [String]) throws {
        for name in filenames {
            let fileURL = dir.appendingPathComponent(name)
            let dummyData = Data("test-data-\(name)".utf8)
            try dummyData.write(to: fileURL)
        }
    }

    @Test("checkDatabaseFileCollisions: tidak melempar error saat folder tujuan bersih")
    func testCheckCollisions_noCollision() throws {
        let sourceDir = try createTempDirectory()
        let destDir = try createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }

        try createDummyFiles(at: sourceDir, filenames: [
            "Annotations.sqlite",
            "Annotations.sqlite-wal",
            "History.sqlite"
        ])

        #expect(throws: Never.self) {
            try SettingsActions.checkDatabaseFileCollisions(from: sourceDir, to: destDir)
        }
    }

    @Test("checkDatabaseFileCollisions: melempar StorageError.collision saat file tujuan sudah ada")
    func testCheckCollisions_detectsCollision() throws {
        let sourceDir = try createTempDirectory()
        let destDir = try createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }

        try createDummyFiles(at: sourceDir, filenames: ["History.sqlite"])
        try createDummyFiles(at: destDir, filenames: ["History.sqlite"])

        #expect {
            try SettingsActions.checkDatabaseFileCollisions(from: sourceDir, to: destDir)
        } throws: { error in
            guard let storageError = error as? StorageError,
                  case let .collision(url) = storageError else { return false }
            return url?.standardizedFileURL == destDir.standardizedFileURL
        }
    }

    @Test("migrateDatabaseFiles: resolusi .ask melempar collision error sebelum memindahkan file")
    func testMigrateDatabaseFiles_askThrowsCollision() throws {
        let sourceDir = try createTempDirectory()
        let destDir = try createTempDirectory()
        let fm = FileManager.default
        defer {
            try? fm.removeItem(at: sourceDir)
            try? fm.removeItem(at: destDir)
        }

        try createDummyFiles(at: sourceDir, filenames: ["SearchResults.sqlite", "Annotations.sqlite"])
        try createDummyFiles(at: destDir, filenames: ["SearchResults.sqlite"])

        #expect {
            try SettingsActions.migrateDatabaseFiles(from: sourceDir, to: destDir, resolution: .ask)
        } throws: { error in
            guard let storageError = error as? StorageError,
                  case .collision = storageError else { return false }
            return true
        }

        #expect(fm.fileExists(atPath: sourceDir.appendingPathComponent("Annotations.sqlite").path))
        #expect(fm.fileExists(atPath: sourceDir.appendingPathComponent("SearchResults.sqlite").path))
    }

    @Test("migrateDatabaseFiles: resolusi .overwriteDestination menimpa file di tujuan dan memindahkan sidecars")
    func testMigrateDatabaseFiles_overwriteDestination() throws {
        let sourceDir = try createTempDirectory()
        let destDir = try createTempDirectory()
        let fm = FileManager.default
        defer {
            try? fm.removeItem(at: sourceDir)
            try? fm.removeItem(at: destDir)
        }

        let sourceFiles = [
            "Annotations.sqlite",
            "Annotations.sqlite-wal",
            "Annotations.sqlite-shm",
            "History.sqlite"
        ]
        try createDummyFiles(at: sourceDir, filenames: sourceFiles)

        let destConflict = destDir.appendingPathComponent("Annotations.sqlite")
        try Data("old-content".utf8).write(to: destConflict)

        try SettingsActions.migrateDatabaseFiles(
            from: sourceDir,
            to: destDir,
            resolution: .overwriteDestination
        )

        for name in sourceFiles {
            let destFile = destDir.appendingPathComponent(name)
            #expect(fm.fileExists(atPath: destFile.path))
            #expect(!fm.fileExists(atPath: sourceDir.appendingPathComponent(name).path))
        }

        let overwrittenData = try Data(contentsOf: destConflict)
        #expect(String(data: overwrittenData, encoding: .utf8) == "test-data-Annotations.sqlite")
    }

    @Test("migrateDatabaseFiles: resolusi .keepDestination mempertahankan file di tujuan dan menghapus file konflik di source")
    func testMigrateDatabaseFiles_keepDestination() throws {
        let sourceDir = try createTempDirectory()
        let destDir = try createTempDirectory()
        let fm = FileManager.default
        defer {
            try? fm.removeItem(at: sourceDir)
            try? fm.removeItem(at: destDir)
        }

        try createDummyFiles(at: sourceDir, filenames: ["History.sqlite", "SearchResults.sqlite"])
        let destHistory = destDir.appendingPathComponent("History.sqlite")
        try Data("original-dest-history".utf8).write(to: destHistory)

        try SettingsActions.migrateDatabaseFiles(
            from: sourceDir,
            to: destDir,
            resolution: .keepDestination
        )

        #expect(!fm.fileExists(atPath: sourceDir.appendingPathComponent("History.sqlite").path))
        let destData = try Data(contentsOf: destHistory)
        #expect(String(data: destData, encoding: .utf8) == "original-dest-history")

        #expect(fm.fileExists(atPath: destDir.appendingPathComponent("SearchResults.sqlite").path))
        #expect(!fm.fileExists(atPath: sourceDir.appendingPathComponent("SearchResults.sqlite").path))
    }

    @Test("migrateDatabaseFiles: rollback memulihkan file tujuan dan menjaga file sumber tetap utuh jika gagal di tengah proses")
    func testMigrateDatabaseFiles_rollsBackOnPartialFailure() throws {
        final class FailingCopyFileManager: FileManager {
            var copyCount = 0
            override func copyItem(at srcURL: URL, to dstURL: URL) throws {
                copyCount += 1
                if copyCount >= 2 {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
                }
                try super.copyItem(at: srcURL, to: dstURL)
            }
        }

        let sourceDir = try createTempDirectory()
        let destDir = try createTempDirectory()
        let fm = FileManager.default
        defer {
            try? fm.removeItem(at: sourceDir)
            try? fm.removeItem(at: destDir)
        }

        try createDummyFiles(at: sourceDir, filenames: ["Annotations.sqlite", "History.sqlite"])
        let existingDest = destDir.appendingPathComponent("Annotations.sqlite")
        try Data("original-dest-annotations".utf8).write(to: existingDest)

        let failingFM = FailingCopyFileManager()
        #expect(throws: (any Error).self) {
            try SettingsActions.migrateDatabaseFiles(
                from: sourceDir,
                to: destDir,
                resolution: .overwriteDestination,
                fm: failingFM
            )
        }

        // File sumber harus tetap utuh 100% di sourceDir
        #expect(fm.fileExists(atPath: sourceDir.appendingPathComponent("Annotations.sqlite").path))
        #expect(fm.fileExists(atPath: sourceDir.appendingPathComponent("History.sqlite").path))

        // File tujuan yang sempat tertimpa harus ter-rollback ke isi semula, dan file ke-2 tidak ada
        let restoredData = try Data(contentsOf: existingDest)
        #expect(String(data: restoredData, encoding: .utf8) == "original-dest-annotations")
        #expect(!fm.fileExists(atPath: destDir.appendingPathComponent("History.sqlite").path))
    }

    @Test("HistoryDatabaseManager: disconnect menutup database dan setupDatabase menyambung kembali")
    func testHistoryDatabaseManager_disconnectAndReconnect() {
        let manager = HistoryDatabaseManager.shared

        manager.setupDatabase()
        manager.disconnect()

        let testEntry = ReadingEntry(
            bookId: 999_999,
            lastContentId: 1,
            lastOpenedAt: Date(),
            favoritedAt: nil,
            positionUpdatedAt: nil,
            updatedAt: Date(),
            isFavorite: false,
            ckRecordId: "ck_dummy_999"
        )
        manager.upsertEntryAsync(testEntry)

        manager.setupDatabase()

        #expect(throws: Never.self) {
            try manager.upsertEntries([testEntry], trackPending: false)
            try manager.deleteEntries(bookIds: [999_999], trackPending: false)
        }
    }
}
