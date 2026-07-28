//
//  DatabaseManager.swift
//  Maktabah
//
//  Created by MacBook on 27/07/26.
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
    var currentBookTable: String = ""
    var booksInCurrentArchive: Int = 0
    var currentBookInArchive: Int = 0
    var archivesToMigrate: [Int] = []
    #elseif os(macOS)
    @Published var isMigrating = false
    @Published var isCancelled = false
    @Published var progress: Double = 0.0
    @Published var totalArchivesToMigrate: Int = 0
    @Published var currentArchiveIndex: Int = 0
    @Published var needsMigration: Bool = false
    @Published var currentBookTable: String = ""
    @Published var booksInCurrentArchive: Int = 0
    @Published var currentBookInArchive: Int = 0
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
        var count = 0
        var outdated: [Int] = []
        for i in 1...20 {
            if let path = AppConfig.archiveDatabasePath(archiveId: i),
               let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64, size > 4096
            {
                count += 1
                if let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: i) {
                    if getArchiveFtsVersion(ftsPath: ftsPath) < 2 {
                        outdated.append(i)
                    }
                }
            } else if let path = AppConfig.archiveFtsDatabasePath(archiveId: i),
                      let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let size = attrs[.size] as? Int64, size > 4096
            {
                count += 1
                if getArchiveFtsVersion(ftsPath: path) < 2 {
                    outdated.append(i)
                }
            }
        }

        archivesToMigrate = outdated
        totalArchivesToMigrate = outdated.count
        needsMigration = totalArchivesToMigrate > 0
    }

    func cancelMigration() {
        isCancelled = true
    }

    @MainActor
    func performMigration() async throws {
        guard needsMigration, !isMigrating else { return }

        await MainActor.run {
            isMigrating = true
            isCancelled = false
            progress = 0.0
            currentArchiveIndex = 0
        }

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
            for i in archivesToMigrate {
                guard let archivePath = AppConfig.archiveDatabasePath(archiveId: i),
                      let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: i)
                else {
                    continue
                }

                let fileManager = FileManager.default
                let archiveExists = fileManager.fileExists(atPath: archivePath)
                let ftsExists = fileManager.fileExists(atPath: ftsPath)

                if !archiveExists, !ftsExists { continue }

                try await rebuildArchive(archivePath: archivePath, ftsPath: ftsPath)

                await MainActor.run {
                    currentArchiveIndex += 1
                    progress = Double(currentArchiveIndex) / Double(totalArchivesToMigrate)
                }
            }

            await MainActor.run {
                archivesToMigrate.removeAll()
                checkNeedsMigration()
                isMigrating = false
                isCancelled = false
            }
        } catch {
            await MainActor.run {
                isMigrating = false
                isCancelled = false
            }
            throw error
        }
    }

    private func rebuildArchive(archivePath: String, ftsPath: String) async throws {
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

        let tables = listTables(
            db: archiveDb,
            schemaName: "main"
        ).filter { $0.hasPrefix("b") && Int($0.dropFirst()) != nil }

        await MainActor.run {
            self.booksInCurrentArchive = tables.count
            self.currentBookInArchive = 0
        }

        for table in tables {
            if isCancelled {
                try? exec(archiveDb, "DETACH DATABASE fts_db;")
                sqlite3_close(archiveDb)
                throw CancellationError()
            }

            await MainActor.run {
                self.currentBookInArchive += 1
                self.currentBookTable = table

                let archiveBase = Double(self.currentArchiveIndex) / Double(self.totalArchivesToMigrate)
                let bookFraction = Double(self.currentBookInArchive) / Double(self.booksInCurrentArchive * self.totalArchivesToMigrate)
                self.progress = archiveBase + bookFraction
            }

            try ArchiveDatabaseTools.buildFTS(
                db: archiveDb,
                ftsSchema: "fts_db",
                ftsTable: "\(table)_fts",
                sourceSchema: "main",
                sourceTable: table,
                isNassCompressed: true
            )

            // Drop old FTS table from main schema so SQLite doesn't resolve to it
            try? exec(archiveDb, "DROP TABLE IF EXISTS main.\(table)_fts;")
        }

        try? exec(archiveDb, "CREATE TABLE IF NOT EXISTS fts_db.metadata (key TEXT PRIMARY KEY, value INTEGER);")
        try? exec(archiveDb, "INSERT OR REPLACE INTO fts_db.metadata (key, value) VALUES ('fts_version', 2);")

        try? exec(archiveDb, "DETACH DATABASE fts_db;")
        sqlite3_close(archiveDb)

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
                try await rebuildArchive(archivePath: archivePath, ftsPath: ftsPath)
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
        let sql = "ATTACH DATABASE '\(path)' AS \(schema);"
        try exec(db, sql)
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
                tables.append(String(cString: namePtr))
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
