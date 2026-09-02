//
//  FtsMigrationManager.swift
//  Maktabah
//

import Foundation
import Observation
import SQLite3
#if canImport(UIKit)
import UIKit
#endif

@Observable
final class FtsMigrationManager {
    static let shared = FtsMigrationManager()

    var isMigrating = false
    var isCancelled = false
    var progress: Double = 0.0
    var totalArchivesToMigrate: Int = 0
    var currentArchiveIndex: Int = 0
    var needsMigration: Bool = false
    var totalBooksToMigrate: Int = 0
    var completedBooksCount: Int = 0
    var activeArchiveStatuses: [Int: String] = [:]
    var archivesToMigrate: [Int] = []

    private enum SQL {
        static let getFtsVersion = "SELECT value FROM metadata WHERE key = 'fts_version';"
        static let detachFtsDb = "DETACH DATABASE fts_db;"
        static let pragmaSyncOff = "PRAGMA synchronous = OFF;"
        static let pragmaJournalMemory = "PRAGMA journal_mode = MEMORY;"
        static let pragmaTempStoreMemory = "PRAGMA temp_store = MEMORY;"
        static let createFtsMetadata = "CREATE TABLE IF NOT EXISTS fts_db.metadata (key TEXT PRIMARY KEY, value INTEGER);"
        static let insertFtsVersion = "INSERT OR REPLACE INTO fts_db.metadata (key, value) VALUES ('fts_version', 2);"
        static func dropFtsTable(_ table: String) -> String {
            "DROP TABLE IF EXISTS main.\(table)_fts;"
        }
    }

    private func getArchiveFtsVersion(ftsPath: String) -> Int {
        guard FileManager.default.fileExists(atPath: ftsPath) else { return 0 }
        guard let db = try? openDatabase(path: ftsPath) else { return 0 }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQL.getFtsVersion, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    private init() {}

    func checkNeedsMigration() {
        var outdated: [Int] = []
        for i in 1 ... 20 {
            if let path = AppConfig.archiveDatabasePath(archiveId: i),
               let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64, size > 4096
            {
                if let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: i) {
                    if getArchiveFtsVersion(ftsPath: ftsPath) < 2 {
                        outdated.append(i)
                    }
                }
            } else if let path = AppConfig.archiveFtsDatabasePath(archiveId: i),
                      let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let size = attrs[.size] as? Int64, size > 4096
            {
                if getArchiveFtsVersion(ftsPath: path) < 2 {
                    outdated.append(i)
                }
            }
        }

        var totalBooks = 0
        for archiveId in outdated {
            if let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId),
               let archiveDb = try? openDatabase(path: archivePath)
            {
                let tables = listTables(db: archiveDb, schemaName: "main")
                    .filter { $0.hasPrefix("b") && Int($0.dropFirst()) != nil }
                totalBooks += tables.count
                sqlite3_close(archiveDb)
            }
        }

        archivesToMigrate = outdated
        totalArchivesToMigrate = outdated.count
        totalBooksToMigrate = totalBooks
        needsMigration = totalArchivesToMigrate > 0
    }

    func cancelMigration() {
        isCancelled = true
    }

    @MainActor
    private func resetMigrationState() {
        isMigrating = true
        isCancelled = false
        progress = 0.0
        completedBooksCount = 0
        activeArchiveStatuses.removeAll()
    }

    @MainActor
    private func finalizeMigration(error: Error? = nil) {
        if error == nil, !isCancelled {
            archivesToMigrate.removeAll()
            checkNeedsMigration()
        }
        activeArchiveStatuses.removeAll()
        isMigrating = false
        isCancelled = false
    }

    private func processMigrationTasks(archives: [Int], maxConcurrent: Int) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = archives.makeIterator()

            for _ in 0 ..< maxConcurrent {
                if let nextId = iterator.next() {
                    group.addTask {
                        try await self.migrateSingleArchive(archiveId: nextId)
                    }
                }
            }

            while try await group.next() != nil {
                if self.isCancelled {
                    break
                }
                if let nextId = iterator.next() {
                    group.addTask {
                        try await self.migrateSingleArchive(archiveId: nextId)
                    }
                }
            }
        }
    }

    @MainActor
    func performMigration() async throws {
        guard needsMigration, !isMigrating else { return }

        resetMigrationState()

        try await withBackgroundTask {
            let archives = self.archivesToMigrate
            let maxConcurrent = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount))

            do {
                try await self.processMigrationTasks(archives: archives, maxConcurrent: maxConcurrent)
                await MainActor.run {
                    self.finalizeMigration()
                }
            } catch {
                await MainActor.run {
                    self.finalizeMigration(error: error)
                }
                throw error
            }
        }
    }

    @MainActor
    private func withBackgroundTask<T>(_ work: () async throws -> T) async throws -> T {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = true
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
        #endif
        return try await work()
    }

    private func getMigrationPaths(archiveId: Int) -> (archiveOrig: String, ftsOrig: String, archiveWrite: String, ftsWrite: String)? {
        guard let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId),
              let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
        else { return nil }

        let archiveWritePath = prepareWritableDatabasePath(archivePath)
        let ftsWritePath = prepareWritableDatabasePath(ftsPath)

        return (archivePath, ftsPath, archiveWritePath, ftsWritePath)
    }

    private func executeMigrationSteps(db: OpaquePointer, ftsWritePath: String, archiveId: Int) async throws {
        // Detach if already attached from previous run
        try? exec(db, SQL.detachFtsDb)

        try attachDatabase(db, path: ftsWritePath, schema: "fts_db")

        // PRAGMA optimizations for fast bulk writing
        try? exec(db, SQL.pragmaSyncOff)
        try? exec(db, SQL.pragmaJournalMemory)
        try? exec(db, SQL.pragmaTempStoreMemory)

        let tables = listTables(
            db: db,
            schemaName: "main"
        ).filter { $0.hasPrefix("b") && Int($0.dropFirst()) != nil }

        try await buildFtsForTables(tables, archiveDb: db, archiveId: archiveId)

        try? exec(db, SQL.createFtsMetadata)
        try? exec(db, SQL.insertFtsVersion)
    }

    private func migrateSingleArchive(archiveId: Int) async throws {
        guard let paths = getMigrationPaths(archiveId: archiveId) else { return }

        var isSuccess = false
        defer {
            if !isSuccess {
                cleanupTempDatabases(
                    archiveWritePath: paths.archiveWrite,
                    originalArchivePath: paths.archiveOrig,
                    ftsWritePath: paths.ftsWrite,
                    originalFtsPath: paths.ftsOrig
                )
            }
        }

        var archiveDb: OpaquePointer? = try openDatabase(path: paths.archiveWrite)
        defer {
            if let db = archiveDb {
                try? exec(db, SQL.detachFtsDb)
                sqlite3_close(db)
            }
        }

        guard let db = archiveDb else { return }

        try await executeMigrationSteps(db: db, ftsWritePath: paths.ftsWrite, archiveId: archiveId)

        try? exec(db, SQL.detachFtsDb)
        sqlite3_close(db)
        archiveDb = nil

        await MainActor.run {
            _ = activeArchiveStatuses.removeValue(forKey: archiveId)
        }

        // Atomic Replace
        try replaceDatabaseIfNeeded(tempPath: paths.archiveWrite, originalPath: paths.archiveOrig)
        try replaceDatabaseIfNeeded(tempPath: paths.ftsWrite, originalPath: paths.ftsOrig)

        isSuccess = true
    }

    private func buildFtsForTables(_ tables: [String], archiveDb: OpaquePointer, archiveId: Int) async throws {
        for (index, table) in tables.enumerated() {
            if isCancelled {
                throw CancellationError()
            }

            let statusText = "Arsip \(archiveId): Buku \(index + 1)/\(tables.count)"
            await MainActor.run {
                self.activeArchiveStatuses[archiveId] = statusText
            }

            try ArchiveDatabaseTools.buildFTS(
                db: archiveDb,
                ftsSchema: "fts_db",
                ftsTable: "\(table)_fts",
                sourceSchema: "main",
                sourceTable: table,
                isNassCompressed: true
            )

            try? exec(archiveDb, SQL.dropFtsTable(table))

            await MainActor.run {
                self.completedBooksCount += 1
                if self.totalBooksToMigrate > 0 {
                    self.progress = min(1.0, Double(self.completedBooksCount) / Double(self.totalBooksToMigrate))
                }
            }
        }
    }

    private func cleanupTempDatabases(archiveWritePath: String, originalArchivePath: String, ftsWritePath: String, originalFtsPath: String) {
        let fm = FileManager.default
        if archiveWritePath != originalArchivePath, fm.fileExists(atPath: archiveWritePath) {
            try? fm.removeItem(atPath: archiveWritePath)
        }
        if ftsWritePath != originalFtsPath, fm.fileExists(atPath: ftsWritePath) {
            try? fm.removeItem(atPath: ftsWritePath)
        }
    }

    @MainActor
    func migrateArchive(archiveId: Int) async throws {
        guard !isMigrating else { return }

        isMigrating = true
        isCancelled = false
        progress = 0.0
        totalArchivesToMigrate = 1
        currentArchiveIndex = 0
        completedBooksCount = 0
        activeArchiveStatuses.removeAll()

        try await withBackgroundTask {
            do {
                guard let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId),
                      let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
                else {
                    self.isMigrating = false
                    return
                }

                let fileManager = FileManager.default
                let archiveExists = fileManager.fileExists(atPath: archivePath)
                let ftsExists = fileManager.fileExists(atPath: ftsPath)

                if archiveExists || ftsExists {
                    try await self.migrateSingleArchive(archiveId: archiveId)
                    self.currentArchiveIndex = 1
                    self.progress = 1.0
                }

                self.isMigrating = false
            } catch {
                self.isMigrating = false
                throw error
            }
        }
    }

    // MARK: - SQLite Helpers

    private func openDatabase(path: String) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            path, &db,
            SQLITE_OPEN_READWRITE |
                SQLITE_OPEN_CREATE |
                SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let validDb = db else {
            let errorMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let db {
                sqlite3_close(db)
            }
            throw NSError(domain: "FtsMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Open failed: \(errorMsg)"])
        }
        return validDb
    }

    private func attachDatabase(_ db: OpaquePointer, path: String, schema: String) throws {
        try db.safeAttachDatabase(path: path, schema: schema)
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let errorString = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "FtsMigration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Prepare failed: \(errorString)"])
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) != SQLITE_DONE {
            let errorString = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "FtsMigration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Step failed: \(errorString)"])
        }
    }

    private func listTables(db: OpaquePointer, schemaName: String) -> [String] {
        db.listTableNames(schemaName: schemaName)
    }

    private func prepareWritableDatabasePath(_ dbPath: String) -> String {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: dbPath)
        let isReadonly = (attrs?[.posixPermissions] as? NSNumber)?.int16Value == 0o444
        if isReadonly || !fm.isWritableFile(atPath: dbPath) {
            let tempPath = dbPath + ".tmp"
            if fm.fileExists(atPath: tempPath) {
                try? fm.removeItem(atPath: tempPath)
            }
            if fm.fileExists(atPath: dbPath) {
                try? fm.copyItem(atPath: dbPath, toPath: tempPath)
                try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tempPath)
            }
            return tempPath
        }
        return dbPath
    }

    private func replaceDatabaseIfNeeded(tempPath: String, originalPath: String) throws {
        let fm = FileManager.default
        if tempPath != originalPath, fm.fileExists(atPath: tempPath) {
            let tempURL = URL(fileURLWithPath: tempPath)
            let origURL = URL(fileURLWithPath: originalPath)
            if fm.fileExists(atPath: originalPath) {
                _ = try fm.replaceItemAt(origURL, withItemAt: tempURL)
            } else {
                try fm.moveItem(at: tempURL, to: origURL)
            }
        }
    }
}
