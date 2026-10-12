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

@Observable @MainActor
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
    var archivesToOptimize: [Int] = []
    var isOptimizationOnly: Bool = false

    func isArchiveOptimizationOnly(_ archiveId: Int) -> Bool {
        !archivesToMigrate.contains(archiveId) && archivesToOptimize.contains(archiveId)
    }

    func doesArchiveNeedAction(_ archiveId: Int) -> Bool {
        archivesToMigrate.contains(archiveId) || archivesToOptimize.contains(archiveId)
    }

    private init() {}

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

    // MARK: - Migration Checks

    func checkNeedsMigration() {
        guard !isMigrating else { return }
        let result = Self.scanDatabasesForMigration()
        archivesToMigrate = result.outdated
        archivesToOptimize = result.toOptimize
        totalBooksToMigrate = result.totalBooks

        if !result.outdated.isEmpty {
            totalArchivesToMigrate = result.outdated.count + result.toOptimize.count
            needsMigration = true
            isOptimizationOnly = false
        } else if !result.toOptimize.isEmpty {
            totalArchivesToMigrate = result.toOptimize.count
            needsMigration = true
            isOptimizationOnly = true
        } else {
            totalArchivesToMigrate = 0
            needsMigration = false
            isOptimizationOnly = false
        }
    }

    private struct MigrationScanResult: Sendable {
        let outdated: [Int]
        let toOptimize: [Int]
        let totalBooks: Int
    }

    private nonisolated static func scanDatabasesForMigration() -> MigrationScanResult {
        var outdated: [Int] = []
        var toOptimize: [Int] = []

        for i in 1 ... 20 {
            if let path = AppConfig.archiveDatabasePath(archiveId: i),
               let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64, size > 4096
            {
                if let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: i) {
                    let version = getArchiveFtsVersion(ftsPath: ftsPath)
                    if version < AppConfig.currentFtsVersion {
                        outdated.append(i)
                    } else if version == AppConfig.currentFtsVersion, hasLegacyFtsTables(ftsPath: ftsPath) {
                        toOptimize.append(i)
                    }
                }
            } else if let path = AppConfig.archiveFtsDatabasePath(archiveId: i),
                      let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let size = attrs[.size] as? Int64, size > 4096
            {
                let version = getArchiveFtsVersion(ftsPath: path)
                if version < AppConfig.currentFtsVersion {
                    outdated.append(i)
                } else if version == AppConfig.currentFtsVersion, hasLegacyFtsTables(ftsPath: path) {
                    toOptimize.append(i)
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

        return MigrationScanResult(outdated: outdated, toOptimize: toOptimize, totalBooks: totalBooks)
    }

    private nonisolated static func hasLegacyFtsTables(ftsPath: String) -> Bool {
        guard FileManager.default.fileExists(atPath: ftsPath),
              let db = try? openDatabase(path: ftsPath, readOnly: true)
        else { return false }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT 1 FROM sqlite_master 
        WHERE type = 'table' 
          AND name NOT IN ('archive_fts', 'archive_index', 'metadata') 
          AND name NOT LIKE 'archive_fts_%' 
          AND name NOT LIKE 'sqlite_%' 
        LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        return sqlite3_step(stmt) == SQLITE_ROW
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
        currentArchiveIndex = 0
        completedBooksCount = 0
        activeArchiveStatuses.removeAll()
    }

    private func finalizeMigration(error: Error? = nil) {
        activeArchiveStatuses.removeAll()
        isMigrating = false
        isCancelled = false
        if error == nil {
            archivesToMigrate.removeAll()
            archivesToOptimize.removeAll()
            checkNeedsMigration()
        }
    }

    func incrementArchiveProgress() {
        currentArchiveIndex += 1
        if totalArchivesToMigrate > 0 {
            if isOptimizationOnly {
                progress = min(1.0, Double(currentArchiveIndex) / Double(totalArchivesToMigrate))
            }
        }
    }

    func updateBookProgress(archiveId: Int, statusText: String? = nil, incrementBy: Int = 0) {
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
            LibraryDataManager.shared.closeAllArchiveConnections()
            let maxConcurrent = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount))

            do {
                if !self.archivesToMigrate.isEmpty {
                    try await self.processMigrationTasks(archives: self.archivesToMigrate, maxConcurrent: maxConcurrent)
                }
                if !self.archivesToOptimize.isEmpty {
                    try await self.processOptimizationTasks(archives: self.archivesToOptimize, maxConcurrent: maxConcurrent)
                }
                self.finalizeMigration()
            } catch {
                self.finalizeMigration(error: error)
                throw error
            }
        }
    }

    private nonisolated func processArchiveTasks(
        archives: [Int],
        maxConcurrent: Int,
        task: @escaping @Sendable (Int) async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = archives.makeIterator()

            for _ in 0 ..< maxConcurrent {
                if let nextId = iterator.next() {
                    group.addTask {
                        try await task(nextId)
                    }
                }
            }

            while try await group.next() != nil {
                if await self.isCancelled {
                    group.cancelAll()
                    break
                }
                if let nextId = iterator.next() {
                    group.addTask {
                        try await task(nextId)
                    }
                }
            }
        }
    }

    private nonisolated func processMigrationTasks(archives: [Int], maxConcurrent: Int) async throws {
        try await processArchiveTasks(archives: archives, maxConcurrent: maxConcurrent) { archiveId in
            try await self.migrateSingleArchive(archiveId: archiveId)
        }
    }

    private nonisolated func processOptimizationTasks(archives: [Int], maxConcurrent: Int) async throws {
        try await processArchiveTasks(archives: archives, maxConcurrent: maxConcurrent) { archiveId in
            try await self.optimizeSingleArchive(archiveId: archiveId)
            await self.incrementArchiveProgress()
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
        try? Self.exec(db, SQL.pragmaArchiveMmapSize)

        let tables = Self.listTables(
            db: db,
            schemaName: "archive_db"
        ).filter { $0.hasPrefix("b") && Int($0.dropFirst()) != nil }

        try? Self.exec(db, "DROP TABLE IF EXISTS archive_index;")
        try? Self.exec(db, "DROP TABLE IF EXISTS archive_fts;")

        try Self.exec(db, SQL.beginTx)
        do {
            try ArchiveDatabaseTools.createUnifiedFTS(db: db, ftsSchema: "main")
            try await buildFtsForTables(tables, ftsDb: db, archiveId: archiveId)
            Self.dropLegacyTables(db: db)
            try? Self.exec(db, SQL.createFtsMetadata)
            try? Self.exec(db, SQL.insertFtsVersion)
            try Self.exec(db, SQL.commitTx)
        } catch {
            try? Self.exec(db, SQL.rollbackTx)
            throw error
        }

        try await checkCancellation()

        await updateBookProgress(
            archiveId: archiveId,
            statusText: .init(localized: .ftsMigrationOptimize(archive: archiveId))
        )
        try? Self.exec(db, SQL.optimizeFts)
        try? Self.exec(db, SQL.detachArchiveDb)
        try? Self.exec(db, SQL.vacuum)
    }

    private nonisolated func withWritableFtsDatabase(
        archiveId: Int,
        detachOnClose: Bool = false,
        perform: (OpaquePointer, MigrationPaths) async throws -> Void
    ) async throws {
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
                if detachOnClose {
                    try? Self.exec(db, SQL.detachArchiveDb)
                }
                sqlite3_close(db)
            }
        }

        guard let db = ftsDb else { return }

        Self.applyPerformancePragmas(db: db)

        try await perform(db, paths)

        if detachOnClose {
            try? Self.exec(db, SQL.detachArchiveDb)
        }
        sqlite3_close(db)
        ftsDb = nil

        await updateBookProgress(archiveId: archiveId, statusText: nil)
        try Self.replaceDatabaseIfNeeded(tempPath: paths.ftsWrite, originalPath: paths.ftsOrig)
        isSuccess = true
    }

    private nonisolated static func applyPerformancePragmas(db: OpaquePointer) {
        try? exec(db, SQL.pragmaSyncOff)
        try? exec(db, SQL.pragmaJournalMemory)
        try? exec(db, SQL.pragmaTempStoreMemory)
        try? exec(db, SQL.pragmaFtsCacheSize)
    }

    private nonisolated func checkCancellation() async throws {
        if Task.isCancelled {
            throw CancellationError()
        }
        if await isCancelled {
            throw CancellationError()
        }
    }

    private nonisolated func migrateSingleArchive(archiveId: Int) async throws {
        try await withWritableFtsDatabase(archiveId: archiveId, detachOnClose: true) { db, paths in
            try Self.attachDatabase(db, path: paths.archivePath, schema: "archive_db")
            try await executeMigrationSteps(db: db, archiveId: archiveId)
        }
    }

    private nonisolated func executeOptimizationSteps(db: OpaquePointer, archiveId: Int) async throws {
        await updateBookProgress(archiveId: archiveId, statusText: "Arsip \(archiveId): Membersihkan...")
        Self.dropLegacyTables(db: db)

        try await checkCancellation()

        await updateBookProgress(archiveId: archiveId, statusText: "Arsip \(archiveId): Mengoptimasi...")
        try? Self.exec(db, SQL.optimizeFts)

        try await checkCancellation()

        await updateBookProgress(archiveId: archiveId, statusText: "Arsip \(archiveId): Memadatkan...")
        try? Self.exec(db, SQL.vacuum)
    }

    private nonisolated func optimizeSingleArchive(archiveId: Int) async throws {
        try await withWritableFtsDatabase(archiveId: archiveId) { db, _ in
            try await executeOptimizationSteps(db: db, archiveId: archiveId)
        }
    }

    private nonisolated static func dropLegacyTables(db: OpaquePointer) {
        let virtualTablesSql = """
        SELECT name FROM sqlite_master 
        WHERE type = 'table' 
          AND sql LIKE '%VIRTUAL%' 
          AND name != 'archive_fts';
        """
        for vt in queryTableNames(db: db, sql: virtualTablesSql) {
            try? exec(db, "DROP TABLE IF EXISTS \"\(vt)\";")
        }

        let remainingLegacySql = """
        SELECT name FROM sqlite_master 
        WHERE type = 'table' 
          AND name NOT IN ('archive_fts', 'archive_index', 'metadata') 
          AND name NOT LIKE 'archive_fts_%' 
          AND name NOT LIKE 'sqlite_%';
        """
        for t in queryTableNames(db: db, sql: remainingLegacySql) {
            try? exec(db, "DROP TABLE IF EXISTS \"\(t)\";")
        }
    }

    private nonisolated static func queryTableNames(db: OpaquePointer, sql: String) -> [String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var tables: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                tables.append(String(cString: cStr))
            }
        }
        return tables
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
                statusText: .init(localized: .ftsMigrationStatusArchiveBook(archiveId, 1, tables.count))
            )
        }

        var pendingCompletedBooks = 0
        var lastUpdateTime = ContinuousClock.now

        for (index, table) in tables.enumerated() {
            if Task.isCancelled {
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
                if await isCancelled {
                    throw CancellationError()
                }

                let statusText = String(localized: .ftsMigrationStatusArchiveBook(archiveId, index + 1, tables.count))
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

        let isOptimizeOnly = isArchiveOptimizationOnly(archiveId)
        let archiveBookCount = isOptimizeOnly ? 0 : await Task.detached {
            Self.countArchiveBooks(archiveId: archiveId)
        }.value

        resetStateForArchive(archiveBookCount: archiveBookCount)

        try await withBackgroundTask {
            do {
                guard let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId) else {
                    isMigrating = false
                    return
                }

                let fileManager = FileManager.default
                let ftsExists = fileManager.fileExists(atPath: ftsPath)

                if ftsExists {
                    LibraryDataManager.shared.closeAllArchiveConnections()
                    if isOptimizeOnly {
                        try await self.optimizeSingleArchive(archiveId: archiveId)
                    } else {
                        try await self.migrateSingleArchive(archiveId: archiveId)
                    }
                    currentArchiveIndex = 1
                    progress = 1.0
                }

                isMigrating = false
                checkNeedsMigration()
            } catch {
                isMigrating = false
                checkNeedsMigration()
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
            .count(where: { $0.hasPrefix("b") && Int($0.dropFirst()) != nil })
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
