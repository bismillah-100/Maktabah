//
//  FtsMigrationManager.swift
//  Maktabah
//

import Combine
import Foundation
import SQLite3
#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
extension FtsMigrationManager: ObservableObject {}
#endif

#if os(iOS)
@Observable
#endif
@MainActor
final class FtsMigrationManager {
    static let shared = FtsMigrationManager()

    #if os(iOS)
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
    #elseif os(macOS)
    @Published var isMigrating = false
    @Published var isCancelled = false
    @Published var progress: Double = 0.0
    @Published var totalArchivesToMigrate: Int = 0
    @Published var currentArchiveIndex: Int = 0
    @Published var needsMigration: Bool = false
    @Published var totalBooksToMigrate: Int = 0
    @Published var completedBooksCount: Int = 0
    @Published var activeArchiveStatuses: [Int: String] = [:]
    @Published var archivesToMigrate: [Int] = []
    #endif

    private enum SQL {
        static let getFtsVersion = "SELECT value FROM metadata WHERE key = 'fts_version';"
        static let detachArchiveDb = "DETACH DATABASE archive_db;"
        static let pragmaSyncOff = "PRAGMA synchronous = OFF;"
        static let pragmaJournalMemory = "PRAGMA journal_mode = MEMORY;"
        static let pragmaTempStoreMemory = "PRAGMA temp_store = MEMORY;"
        #if os(iOS)
        static let pragmaFtsCacheSize = "PRAGMA cache_size = -32000;"
        static let pragmaArchiveMmapSize = "PRAGMA archive_db.mmap_size = 67108864;"
        #else
        static let pragmaFtsCacheSize = "PRAGMA cache_size = -64000;"
        static let pragmaArchiveMmapSize = "PRAGMA archive_db.mmap_size = 268435456;"
        #endif
        static let beginTx = "BEGIN TRANSACTION;"
        static let commitTx = "COMMIT;"
        static let rollbackTx = "ROLLBACK;"
        static let createFtsMetadata = "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value INTEGER);"
        static let insertFtsVersion = "INSERT OR REPLACE INTO metadata (key, value) VALUES ('fts_version', \(AppConfig.currentFtsVersion));"
        static let optimizeFts = "INSERT INTO archive_fts(archive_fts) VALUES('optimize');"
        static let vacuum = "VACUUM;"
    }

    private init() {}

    func checkNeedsMigration() {
        guard !isMigrating else { return }
        let (outdated, totalBooks) = Self.scanDatabasesForMigration()
        archivesToMigrate = outdated
        totalArchivesToMigrate = outdated.count
        totalBooksToMigrate = totalBooks
        needsMigration = outdated.count > 0
    }

    private nonisolated static func scanDatabasesForMigration() -> (outdated: [Int], totalBooks: Int) {
        var outdated: [Int] = []
        for i in 1 ... 20 {
            if let path = AppConfig.archiveDatabasePath(archiveId: i),
               let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64, size > 4096
            {
                if let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: i) {
                    if getArchiveFtsVersion(ftsPath: ftsPath) < AppConfig.currentFtsVersion {
                        outdated.append(i)
                    }
                }
            } else if let path = AppConfig.archiveFtsDatabasePath(archiveId: i),
                      let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let size = attrs[.size] as? Int64, size > 4096
            {
                if getArchiveFtsVersion(ftsPath: path) < AppConfig.currentFtsVersion {
                    outdated.append(i)
                }
            }
        }

        var totalBooks = 0
        for archiveId in outdated {
            if let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId),
               let archiveDb = try? openDatabase(path: archivePath, readOnly: true)
            {
                let tables = listTables(db: archiveDb, schemaName: "main")
                    .filter { $0.hasPrefix("b") && Int($0.dropFirst()) != nil }
                totalBooks += tables.count
                sqlite3_close(archiveDb)
            }
        }

        return (outdated, totalBooks)
    }

    private nonisolated static func getArchiveFtsVersion(ftsPath: String) -> Int {
        guard FileManager.default.fileExists(atPath: ftsPath) else { return 0 }
        guard let db = try? openDatabase(path: ftsPath, readOnly: true) else { return 0 }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQL.getFtsVersion, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    // MARK: - Actions

    func cancelMigration() {
        isCancelled = true
        isMigrating = false
    }

    private func resetMigrationState() {
        isMigrating = true
        isCancelled = false
        progress = 0.0
        completedBooksCount = 0
        activeArchiveStatuses.removeAll()
    }

    private func finalizeMigration(error: Error? = nil) {
        activeArchiveStatuses.removeAll()
        isMigrating = false
        isCancelled = false
        if error == nil {
            archivesToMigrate.removeAll()
            checkNeedsMigration()
        }
    }

    func updateBookProgress(
        archiveId: Int,
        statusText: String? = nil,
        incrementBy: Int = 0
    ) {
        if let statusText {
            activeArchiveStatuses[archiveId] = statusText
        } else {
            activeArchiveStatuses.removeValue(forKey: archiveId)
        }

        if incrementBy > 0 {
            completedBooksCount += incrementBy
            if totalBooksToMigrate > 0 {
                progress = min(1.0, Double(completedBooksCount) / Double(totalBooksToMigrate))
            }
        }
    }

    // MARK: - Execution

    func performMigration() async throws {
        guard !isMigrating else { return }

        checkNeedsMigration()
        guard needsMigration else { return }

        resetMigrationState()

        try await withBackgroundTask {
            let archives = self.archivesToMigrate
            let maxConcurrent = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount))

            do {
                try await self.processMigrationTasks(archives: archives, maxConcurrent: maxConcurrent)
                self.finalizeMigration()
            } catch {
                self.finalizeMigration(error: error)
                throw error
            }
        }
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

    private struct MigrationPaths: Sendable {
        let archivePath: String
        let ftsOrig: String
        let ftsWrite: String
    }

    private nonisolated static func getMigrationPaths(archiveId: Int) -> MigrationPaths? {
        guard let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId),
              let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
        else { return nil }

        let ftsWritePath = prepareWritableDatabasePath(ftsPath)

        return MigrationPaths(
            archivePath: archivePath,
            ftsOrig: ftsPath,
            ftsWrite: ftsWritePath
        )
    }

    private nonisolated func executeMigrationSteps(db: OpaquePointer, archiveId: Int) async throws {
        try? Self.exec(db, SQL.pragmaSyncOff)
        try? Self.exec(db, SQL.pragmaJournalMemory)
        try? Self.exec(db, SQL.pragmaTempStoreMemory)
        try? Self.exec(db, SQL.pragmaFtsCacheSize)
        try? Self.exec(db, SQL.pragmaArchiveMmapSize)

        let tables = Self.listTables(
            db: db,
            schemaName: "archive_db"
        ).filter { $0.hasPrefix("b") && Int($0.dropFirst()) != nil }

        try? Self.exec(db, "DROP TABLE IF EXISTS archive_index;")
        try? Self.exec(db, "DROP TABLE IF EXISTS archive_fts;")
        try ArchiveDatabaseTools.createUnifiedFTS(db: db, ftsSchema: "main")

        try Self.exec(db, SQL.beginTx)
        do {
            try await buildFtsForTables(tables, ftsDb: db, archiveId: archiveId)
            try? Self.exec(db, SQL.createFtsMetadata)
            try? Self.exec(db, SQL.insertFtsVersion)
            try Self.exec(db, SQL.commitTx)
        } catch {
            try? Self.exec(db, SQL.rollbackTx)
            throw error
        }

        if Task.isCancelled {
            throw CancellationError()
        }
        if await isCancelled {
            throw CancellationError()
        }

        await updateBookProgress(archiveId: archiveId, statusText: "Arsip \(archiveId): Mengoptimasi...")
        try? Self.exec(db, SQL.optimizeFts)
        try? Self.exec(db, SQL.detachArchiveDb)
        try? Self.exec(db, SQL.vacuum)
    }

    private nonisolated func migrateSingleArchive(archiveId: Int) async throws {
        guard let paths = Self.getMigrationPaths(archiveId: archiveId) else { return }

        var isSuccess = false
        defer {
            if !isSuccess {
                Self.cleanupTempDatabases(
                    ftsWritePath: paths.ftsWrite,
                    originalFtsPath: paths.ftsOrig
                )
            }
        }

        var ftsDb: OpaquePointer? = try Self.openDatabase(path: paths.ftsWrite, readOnly: false)
        defer {
            if let db = ftsDb {
                try? Self.exec(db, SQL.detachArchiveDb)
                sqlite3_close(db)
            }
        }

        guard let db = ftsDb else { return }

        try Self.attachDatabase(db, path: paths.archivePath, schema: "archive_db")

        try await executeMigrationSteps(db: db, archiveId: archiveId)

        try? Self.exec(db, SQL.detachArchiveDb)
        sqlite3_close(db)
        ftsDb = nil

        await updateBookProgress(archiveId: archiveId, statusText: nil)

        try Self.replaceDatabaseIfNeeded(tempPath: paths.ftsWrite, originalPath: paths.ftsOrig)

        isSuccess = true
    }

    private nonisolated func buildFtsForTables(_ tables: [String], ftsDb: OpaquePointer, archiveId: Int) async throws {
        let (indexStmt, ftsStmt) = try Self.prepareBulkInsertStatements(ftsDb: ftsDb)
        defer {
            sqlite3_finalize(indexStmt)
            sqlite3_finalize(ftsStmt)
        }

        if !tables.isEmpty {
            await updateBookProgress(
                archiveId: archiveId,
                statusText: "Arsip \(archiveId): Buku 1/\(tables.count)"
            )
        }

        var pendingCompletedBooks = 0
        var lastUpdateTime = ContinuousClock.now

        for (index, table) in tables.enumerated() {
            if Task.isCancelled {
                throw CancellationError()
            }
            if await isCancelled {
                throw CancellationError()
            }

            guard let bookId = Int(table.dropFirst()) else { continue }

            try ArchiveDatabaseTools.appendBookFast(
                db: ftsDb,
                sourceSchema: "archive_db",
                sourceTable: table,
                bookId: bookId,
                insertIndexStmt: indexStmt,
                insertFtsStmt: ftsStmt,
                isNassCompressed: true
            )

            pendingCompletedBooks += 1

            let now = ContinuousClock.now
            let isLast = (index == tables.count - 1)

            if isLast || now - lastUpdateTime >= .milliseconds(250) || pendingCompletedBooks >= 10 {
                if Task.isCancelled {
                    throw CancellationError()
                }
                if await isCancelled {
                    throw CancellationError()
                }

                let statusText = "Arsip \(archiveId): Buku \(index + 1)/\(tables.count)"
                await updateBookProgress(
                    archiveId: archiveId,
                    statusText: statusText,
                    incrementBy: pendingCompletedBooks
                )
                pendingCompletedBooks = 0
                lastUpdateTime = now
            }
        }
    }

    private nonisolated static func prepareBulkInsertStatements(
        ftsDb: OpaquePointer
    ) throws -> (indexStmt: OpaquePointer, ftsStmt: OpaquePointer) {
        let insertIndexSQL = "INSERT OR REPLACE INTO archive_index(rowid, book_id, page, id, part) VALUES (?, ?, ?, ?, ?);"
        let insertFtsSQL = "INSERT INTO archive_fts(rowid, nass_clean) VALUES (?, ?);"

        var insertIndexStmt: OpaquePointer?
        var insertFtsStmt: OpaquePointer?
        guard sqlite3_prepare_v2(ftsDb, insertIndexSQL, -1, &insertIndexStmt, nil) == SQLITE_OK,
              sqlite3_prepare_v2(ftsDb, insertFtsSQL, -1, &insertFtsStmt, nil) == SQLITE_OK,
              let indexStmt = insertIndexStmt,
              let ftsStmt = insertFtsStmt
        else {
            if let insertIndexStmt { sqlite3_finalize(insertIndexStmt) }
            if let insertFtsStmt { sqlite3_finalize(insertFtsStmt) }
            throw NSError(domain: "FtsMigration", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare bulk INSERT statements."])
        }
        return (indexStmt, ftsStmt)
    }

    private nonisolated static func cleanupTempDatabases(ftsWritePath: String, originalFtsPath: String) {
        let fm = FileManager.default
        if ftsWritePath != originalFtsPath, fm.fileExists(atPath: ftsWritePath) {
            try? fm.removeItem(atPath: ftsWritePath)
        }
    }

    func migrateArchive(archiveId: Int) async throws {
        guard !isMigrating else { return }

        let archiveBookCount = await Task.detached {
            Self.countArchiveBooks(archiveId: archiveId)
        }.value

        resetStateForArchive(archiveBookCount: archiveBookCount)

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
                    LibraryDataManager.shared.closeAllArchiveConnections()
                    try await self.migrateSingleArchive(archiveId: archiveId)
                    self.currentArchiveIndex = 1
                    self.progress = 1.0
                }

                self.isMigrating = false
                self.checkNeedsMigration()
            } catch {
                self.isMigrating = false
                self.checkNeedsMigration()
                throw error
            }
        }
    }

    private nonisolated static func countArchiveBooks(archiveId: Int) -> Int {
        guard let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId),
              let db = try? openDatabase(path: archivePath, readOnly: true)
        else { return 0 }
        defer { sqlite3_close(db) }
        return listTables(db: db, schemaName: "main")
            .filter { $0.hasPrefix("b") && Int($0.dropFirst()) != nil }
            .count
    }

    private func resetStateForArchive(archiveBookCount: Int) {
        isMigrating = true
        isCancelled = false
        progress = 0.0
        totalArchivesToMigrate = 1
        totalBooksToMigrate = archiveBookCount
        currentArchiveIndex = 0
        completedBooksCount = 0
        activeArchiveStatuses.removeAll()
    }

    // MARK: - SQLite Helpers

    private nonisolated static func openDatabase(path: String, readOnly: Bool = false) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = readOnly
            ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX)
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX)
        guard sqlite3_open_v2(
            path, &db,
            flags,
            nil
        ) == SQLITE_OK, let validDb = db else {
            let errorMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let db {
                sqlite3_close(db)
            }
            throw NSError(domain: "FtsMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Open failed: \(errorMsg)"])
        }
        sqlite3_busy_timeout(validDb, 5000)
        return validDb
    }

    private nonisolated static func attachDatabase(_ db: OpaquePointer, path: String, schema: String) throws {
        try db.safeAttachDatabase(path: path, schema: schema)
    }

    private nonisolated static func exec(_ db: OpaquePointer, _ sql: String) throws {
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

    private nonisolated static func listTables(db: OpaquePointer, schemaName: String) -> [String] {
        db.listTableNames(schemaName: schemaName)
    }

    private nonisolated static func prepareWritableDatabasePath(_ dbPath: String) -> String {
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

    private nonisolated static func replaceDatabaseIfNeeded(tempPath: String, originalPath: String) throws {
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
