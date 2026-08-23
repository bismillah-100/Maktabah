//
//  FtsMigrationManager.swift
//  Maktabah
//

import Foundation
import SQLite3
#if canImport(UIKit)
import UIKit
#endif
import Combine

#if os(macOS)
extension FtsMigrationManager: ObservableObject {}
#endif

#if os(iOS)
@Observable
#endif
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

    private func getArchiveFtsVersion(ftsPath: String) -> Int {
        guard FileManager.default.fileExists(atPath: ftsPath) else { return 0 }
        guard let db = try? openDatabase(path: ftsPath) else { return 0 }
        defer { sqlite3_close(db) }

        let sql = "SELECT value FROM metadata WHERE key = 'fts_version';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    private init() {}

    func checkNeedsMigration() {
        var outdated: [Int] = []
        for i in 1...20 {
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
               let archiveDb = try? openDatabase(path: archivePath) {
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
    func performMigration() async throws {
        guard needsMigration, !isMigrating else { return }

        isMigrating = true
        isCancelled = false
        progress = 0.0
        completedBooksCount = 0
        activeArchiveStatuses.removeAll()

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

        let archives = archivesToMigrate
        let maxConcurrent = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount))

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                var iterator = archives.makeIterator()

                for _ in 0..<maxConcurrent {
                    if let nextId = iterator.next() {
                        group.addTask {
                            try await self.migrateSingleArchive(archiveId: nextId)
                        }
                    }
                }

                while try await group.next() != nil {
                    if self.isCancelled { break }
                    if let nextId = iterator.next() {
                        group.addTask {
                            try await self.migrateSingleArchive(archiveId: nextId)
                        }
                    }
                }
            }

            await MainActor.run {
                archivesToMigrate.removeAll()
                activeArchiveStatuses.removeAll()
                checkNeedsMigration()
                isMigrating = false
                isCancelled = false
            }
        } catch {
            await MainActor.run {
                activeArchiveStatuses.removeAll()
                isMigrating = false
                isCancelled = false
            }
            throw error
        }
    }

    private func migrateSingleArchive(archiveId: Int) async throws {
        guard let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId),
              let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
        else { return }

        let fileManager = FileManager.default
        let archiveExists = fileManager.fileExists(atPath: archivePath)
        let ftsExists = fileManager.fileExists(atPath: ftsPath)

        if !archiveExists && !ftsExists { return }

        try await rebuildArchive(archiveId: archiveId, archivePath: archivePath, ftsPath: ftsPath)
    }

    private func rebuildArchive(archiveId: Int, archivePath: String, ftsPath: String) async throws {
        let archiveWritePath = prepareWritableDatabasePath(archivePath)
        let ftsWritePath = prepareWritableDatabasePath(ftsPath)

        var isSuccess = false
        defer {
            if !isSuccess {
                let fm = FileManager.default
                if archiveWritePath != archivePath, fm.fileExists(atPath: archiveWritePath) {
                    try? fm.removeItem(atPath: archiveWritePath)
                }
                if ftsWritePath != ftsPath, fm.fileExists(atPath: ftsWritePath) {
                    try? fm.removeItem(atPath: ftsWritePath)
                }
            }
        }

        let archiveDb = try openDatabase(path: archiveWritePath)
        defer {
            try? exec(archiveDb, "DETACH DATABASE fts_db;")
            sqlite3_close(archiveDb)
        }

        // Detach if already attached from previous run
        try? exec(archiveDb, "DETACH DATABASE fts_db;")

        try attachDatabase(archiveDb, path: ftsWritePath, schema: "fts_db")

        // PRAGMA optimizations for fast bulk writing
        try? exec(archiveDb, "PRAGMA synchronous = OFF;")
        try? exec(archiveDb, "PRAGMA journal_mode = MEMORY;")
        try? exec(archiveDb, "PRAGMA temp_store = MEMORY;")

        let tables = listTables(
            db: archiveDb,
            schemaName: "main"
        ).filter { $0.hasPrefix("b") && Int($0.dropFirst()) != nil }

        for (index, table) in tables.enumerated() {
            if isCancelled {
                try? exec(archiveDb, "DETACH DATABASE fts_db;")
                sqlite3_close(archiveDb)
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

            try? exec(archiveDb, "DROP TABLE IF EXISTS main.\(table)_fts;")

            await MainActor.run {
                self.completedBooksCount += 1
                if self.totalBooksToMigrate > 0 {
                    self.progress = min(1.0, Double(self.completedBooksCount) / Double(self.totalBooksToMigrate))
                }
            }
        }

        try? exec(archiveDb, "CREATE TABLE IF NOT EXISTS fts_db.metadata (key TEXT PRIMARY KEY, value INTEGER);")
        try? exec(archiveDb, "INSERT OR REPLACE INTO fts_db.metadata (key, value) VALUES ('fts_version', 2);")

        try? exec(archiveDb, "DETACH DATABASE fts_db;")
        sqlite3_close(archiveDb)

        await MainActor.run {
            _ = activeArchiveStatuses.removeValue(forKey: archiveId)
        }

        // Atomic Replace
        try replaceDatabaseIfNeeded(tempPath: archiveWritePath, originalPath: archivePath)
        try replaceDatabaseIfNeeded(tempPath: ftsWritePath, originalPath: ftsPath)

        isSuccess = true
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

        do {
            guard let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId),
                  let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
            else {
                isMigrating = false
                return
            }

            let fileManager = FileManager.default
            let archiveExists = fileManager.fileExists(atPath: archivePath)
            let ftsExists = fileManager.fileExists(atPath: ftsPath)

            if archiveExists || ftsExists {
                try await rebuildArchive(archiveId: archiveId, archivePath: archivePath, ftsPath: ftsPath)
                currentArchiveIndex = 1
                progress = 1.0
            }

            isMigrating = false
        } catch {
            isMigrating = false
            throw error
        }
    }

    // MARK: - SQLite Helpers

    private func openDatabase(path: String) throws -> OpaquePointer {
        var db: OpaquePointer?
        if sqlite3_open_v2(
            path, &db,
            SQLITE_OPEN_READWRITE |
            SQLITE_OPEN_CREATE |
            SQLITE_OPEN_NOMUTEX,
            nil
        ) != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw NSError(domain: "FtsMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Open failed: \(errorMsg)"])
        }
        return db!
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
        let sql = "SELECT name FROM \(schemaName).sqlite_master WHERE type='table' ORDER BY name;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var tables: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(stmt, 0) {
                let bytes = sqlite3_column_bytes(stmt, 0)
                let buffer = UnsafeBufferPointer(start: namePtr, count: Int(bytes))
                tables.append(String(decoding: buffer, as: UTF8.self))
            }
        }
        return tables
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
