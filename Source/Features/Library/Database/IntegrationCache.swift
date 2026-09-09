//
//  IntegrationCache.swift
//  Maktabah
//
//  Cache untuk status integrasi kitab.
//
//  Strategi:
//  • Satu file JSON per archive: `<archiveBasePath>/integration_cache/<archiveId>.json`
//    Format: { "bookIds": [1, 2, 3, …] }
//  • Di-load ke Set<Int> saat pertama kali dipakai (lazy per-archive).
//  • Setelah integrasi berhasil, update Set + tulis ulang JSON yang bersangkutan.
//  • isBookIntegrated() jadi O(1) lookup — tidak ada SQLite open/close sama sekali.
//
//  Jika cache file untuk suatu archive belum ada (fresh install / pertama kali),
//  IntegrationCache.build(for:) akan melakukan satu kali SQLite scan ke archive
//  tersebut, lalu menyimpan hasilnya — setelah itu semua operasi berikutnya O(1).
//

import Foundation
import SQLite3
import Synchronization

// MARK: - IntegrationCache

final class IntegrationCache: Sendable {
    static let shared = IntegrationCache()

    private struct IntegrationState: Sendable {
        var integrated: [Int: Set<Int>] = [:] // [archiveId: Set<bookId>]
        var loadedArchives: Set<Int> = [] // archive yang sudah di-load ke RAM
    }

    private let state = Mutex(IntegrationState())
    nonisolated(unsafe) private let fm = FileManager.default

    private init() {}

    // MARK: - Cache directory

    private var cacheDir: URL? {
        guard let base = AppConfig.archiveFilesPath else { return nil }
        return URL(fileURLWithPath: base).appendingPathComponent("integration_cache")
    }

    private func cacheFile(for archiveId: Int) -> URL? {
        cacheDir?.appendingPathComponent("\(archiveId).json")
    }

    // MARK: - Public API

    /// `true` jika kitab sudah terintegrasi — O(1) setelah cache di-load.
    func isIntegrated(bookId: Int, archiveId: Int) -> Bool {
        // Pastikan cache archive ini sudah di-load
        ensureLoaded(archiveId: archiveId)
        return state.withLock {
            $0.integrated[archiveId]?.contains(bookId) ?? false
        }
    }

    /// Tandai kitab sebagai terintegrasi dan persist ke JSON.
    func markIntegrated(bookId: Int, archiveId: Int) {
        guard AppConfig.isUsingBundleMode else { return }

        // Pastikan cache archive ini sudah di-load di luar lock agar tidak deadlock
        ensureLoaded(archiveId: archiveId)

        state.withLock { state in
            if state.integrated[archiveId] == nil {
                state.integrated[archiveId] = []
            }
            state.integrated[archiveId]?.insert(bookId)
        }
        persistCache(for: archiveId)
    }

    /// Hapus tanda kitab sebagai terintegrasi dan persist ke JSON.
    func unmarkIntegrated(bookId: Int, archiveId: Int) {
        guard AppConfig.isUsingBundleMode else { return }

        ensureLoaded(archiveId: archiveId)

        state.withLock { state in
            if var books = state.integrated[archiveId] {
                books.remove(bookId)
                state.integrated[archiveId] = books
            }
        }
        persistCache(for: archiveId)
    }

    /// Bangun cache untuk archive tertentu dengan scan SQLite sekali.
    /// Hanya perlu dipanggil bila cache file belum ada.
    func build(for archiveId: Int) {
        guard AppConfig.isUsingBundleMode else { return }
        guard let file = cacheFile(for: archiveId) else { return }
        guard !fm.fileExists(atPath: file.path) else { return }

        guard let archivePath = AppConfig.archiveDatabasePath(archiveId: archiveId),
              let ftsPath = AppConfig.archiveFtsDatabasePath(archiveId: archiveId)
        else { return }

        guard fm.fileExists(atPath: archivePath),
              fm.fileExists(atPath: ftsPath)
        else {
            // Archive belum ada → cache kosong, simpan supaya kita tahu sudah di-scan
            let shouldSave = state.withLock { state -> Bool in
                if state.loadedArchives.contains(archiveId) { return false }
                state.integrated[archiveId] = []
                state.loadedArchives.insert(archiveId)
                return true
            }
            if shouldSave {
                saveJSON(bookIds: [], for: archiveId)
            }
            return
        }

        let bookIds = scanIntegratedBookIds(archivePath: archivePath, ftsPath: ftsPath)

        let shouldSave = state.withLock { state -> Bool in
            if state.loadedArchives.contains(archiveId) { return false }
            state.integrated[archiveId] = Set(bookIds)
            state.loadedArchives.insert(archiveId)
            return true
        }
        if shouldSave {
            saveJSON(bookIds: bookIds, for: archiveId)
        }
    }

    /// Build cache untuk semua archive yang ada di disk (panggil saat app launch di background).
    func buildAllIfNeeded() {
        guard AppConfig.isUsingBundleMode,
              let basePath = AppConfig.archiveFilesPath
        else { return }
        let baseURL = URL(fileURLWithPath: basePath)

        // Temukan semua file `N.sqlite` (archive, bukan _fts)
        let candidates = (try? fm.contentsOfDirectory(at: baseURL,
                                                      includingPropertiesForKeys: nil)) ?? []
        let archiveIds = candidates.compactMap { url -> Int? in
            let name = url.lastPathComponent
            guard name.hasSuffix(".sqlite"),
                  !name.contains("_fts"),
                  !name.contains(".tmp."),
                  let id = Int(name.dropLast(".sqlite".count))
            else { return nil }
            return id
        }

        for id in archiveIds {
            build(for: id)
        }
    }

    // periphery:ignore
    /// Invalidasi cache untuk archive tertentu (misal setelah rollback / manual fix).
    func invalidate(archiveId: Int) {
        state.withLock { state in
            state.integrated.removeValue(forKey: archiveId)
            state.loadedArchives.remove(archiveId)
        }
        if let file = cacheFile(for: archiveId) {
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - Internal: load from JSON

    private func ensureLoaded(archiveId: Int) {
        guard AppConfig.isUsingBundleMode else { return }
        let alreadyLoaded = state.withLock { $0.loadedArchives.contains(archiveId) }
        if alreadyLoaded { return }

        guard let file = cacheFile(for: archiveId),
              fm.fileExists(atPath: file.path)
        else {
            // Belum ada cache → build sekarang (sekali saja)
            build(for: archiveId)
            return
        }

        guard let data = try? Data(contentsOf: file),
              let json = try? JSONDecoder().decode(CacheFile.self, from: data)
        else {
            // File corrupt → rebuild
            build(for: archiveId)
            return
        }

        state.withLock { state in
            if state.loadedArchives.contains(archiveId) { return }
            state.integrated[archiveId] = Set(json.bookIds)
            state.loadedArchives.insert(archiveId)
        }
    }

    // MARK: - Internal: persist

    private func persistCache(for archiveId: Int) {
        guard AppConfig.isUsingBundleMode else { return }
        let ids = state.withLock { Array($0.integrated[archiveId] ?? []) }
        saveJSON(bookIds: ids, for: archiveId)
    }

    private func saveJSON(bookIds: [Int], for archiveId: Int) {
        guard AppConfig.isUsingBundleMode else { return }
        guard let dir = cacheDir else { return }

        // Pastikan direktori ada
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        guard let file = cacheFile(for: archiveId) else { return }
        let payload = CacheFile(bookIds: bookIds)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: file, options: [.atomic])
        }
    }

    // MARK: - SQLite scan (sekali saja per archive)

    /// Kembalikan semua bookId yang sudah ada di archive **dan** di FTS.
    private func scanIntegratedBookIds(archivePath: String, ftsPath: String) -> [Int] {
        guard let archiveDb = openReadOnly(path: archivePath) else { return [] }
        defer { sqlite3_close(archiveDb) }

        guard let ftsDb = openReadOnly(path: ftsPath) else { return [] }
        defer { sqlite3_close(ftsDb) }

        let archiveTables = Set(listTables(db: archiveDb))
        let ftsTables = Set(listTables(db: ftsDb))

        var result: [Int] = []
        for table in archiveTables {
            // Tabel kitab di archive: "bN", pasangannya di FTS: "bN_fts"
            guard table.hasPrefix("b"),
                  let id = Int(table.dropFirst()),
                  ftsTables.contains("\(table)_fts")
            else { continue }
            result.append(id)
        }
        return result
    }

    private func openReadOnly(path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    private func listTables(db: OpaquePointer) -> [String] {
        db.listTableNames()
    }

    // MARK: - Codable DTO

    private struct CacheFile: Codable {
        let bookIds: [Int]
    }
}
