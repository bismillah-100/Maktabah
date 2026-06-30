//
//  AppConfig.swift
//  Maktabah
//
//  Created by MacBook on 25/12/25.
//

import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(iOS)
import UIKit
#endif

struct AppConfig {
    static let storageKey = "selected_shamela_bookmark" // Ubah key agar fresh
    static let annotationsAndResultsFolder = "annotations_FolderPath"
    static let bundleModeKey = "use_bundle_database_mode"
    static let customDatabaseFolderKey = "custom_database_folder_bookmark"
    static let bookDownloadBaseURLKey = "book_download_base_url"
    static let bookReleaseBaseURLKey = "book_release_base_url"
    static let bookIndexURLKey = "book_index_url"
    static let appcastURLKey = "appcast_url"

    // MARK: - Archive Cache Path (untuk Bundle Mode)
    /// Path untuk archive files saat menggunakan Bundle Mode
    /// Located at: ~/Library/Application Support/Maktabah/Caches/
    static var archiveCachePath: String? {
        guard let appSupport = appSupportDir else { return nil }
        let cachePath = appSupport.appendingPathComponent("Caches", isDirectory: true)

        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: cachePath.path) {
                try fm.createDirectory(at: cachePath, withIntermediateDirectories: true)
            }
            return cachePath.path
        } catch {
            print("Error creating archive cache directory:", error)
            return nil
        }
    }

    // MARK: - Custom Database Path
    /// Path ke custom folder yang dipilih user
    /// Ketika user memilih folder, SEMUA files (main, special, archives) di sini
    static var customDatabasePath: String? {
        guard let folderUrl = resolvedPath(for: customDatabaseFolderKey) else { return nil }
        return folderUrl.path
    }

    // MARK: - Bundle Mode Flag
    /// True jika aplikasi sedang menggunakan Bundle Mode (database dari bundle)
    static var isUsingBundleMode: Bool {
        get {
            UserDefaults.standard.bool(forKey: bundleModeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: bundleModeKey)
        }
    }

    // MARK: - Helper: Get appropriate path untuk database files (main.sqlite, special.sqlite)
    /// Return path untuk main.sqlite dan special.sqlite
    /// - Bundle Mode: ~/Library/Application Support/Maktabah/Caches/
    ///   (diunduh saat first launch, bukan di-bundle ke .app)
    /// - Custom Mode: {custom_folder}/Files/
    static var databaseFilesPath: String? {
        // 1. Jika custom folder ada, gunakan itu
        if let customPath = customDatabasePath {
            return "\(customPath)/Files"
        }

        // 2. Bundle Mode → Caches/ (downloaded)
        if isUsingBundleMode {
            return coreDatabasePath
        }

        // 3. Fallback tidak ada
        return nil
    }

    // MARK: - Core Release Config

    static let coreReleaseTagKey = "core_release_tag"
    static let coreReleaseBaseURLKey = "core_release_base_url"

    /// Tag release GitHub untuk core database (main.sqlite + special.sqlite).
    /// Default: "v0-core". Override via UserDefaults key: core_release_tag
    static var coreReleaseTag: String? {
        if let raw = UserDefaults.standard.string(forKey: coreReleaseTagKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }
        return "v1.0-core"
    }

    /// Base URL GitHub Releases untuk core database.
    /// Default: https://github.com/bismillah-100/Kitab/releases/download
    /// Override via UserDefaults key: core_release_base_url
    static var coreReleaseBaseURL: URL? {
        if let raw = UserDefaults.standard.string(forKey: coreReleaseBaseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://github.com/bismillah-100/Kitab/releases/download")
    }

    // MARK: - Core Database Path (Caches/)

    /// Folder untuk menyimpan main.sqlite + special.sqlite yang diunduh.
    /// Hanya relevan untuk Bundle Mode.
    /// Path: ~/Library/Application Support/Maktabah/Caches/
    static var coreDatabasePath: String? {
        guard !hasCustomDatabaseFolder() else { return nil }
        return archiveCachePath
    }

    // MARK: - Helper: Database File Paths
    static var mainDatabasePath: String? {
        guard let base = databaseFilesPath else { return nil }
        return "\(base)/main.sqlite"
    }

    static var specialDatabasePath: String? {
        guard let base = databaseFilesPath else { return nil }
        return "\(base)/special.sqlite"
    }

    // MARK: - Helper: Get appropriate path untuk archive files (1-20.sqlite)
    /// Return path untuk archive files
    /// - Bundle Mode: ~/Library/Application Support/Maktabah/Caches/
    /// - Custom Mode: {custom_folder}/
    static var archiveFilesPath: String? {
        // 1. Jika custom folder ada, gunakan itu (archives di root folder custom)
        if let customPath = customDatabasePath {
            return customPath
        }

        // 2. Jika Bundle Mode, gunakan cache path
        if isUsingBundleMode, let cachePath = archiveCachePath {
            return cachePath
        }

        // 3. Fallback tidak ada
        return nil
    }

    static func archiveDatabasePath(archiveId: Int) -> String? {
        guard let base = archiveFilesPath else { return nil }
        return "\(base)/\(archiveId).sqlite"
    }

    static func archiveFtsDatabasePath(archiveId: Int) -> String? {
        guard let base = archiveFilesPath else { return nil }
        return "\(base)/\(archiveId)_fts.sqlite"
    }

    // MARK: - Helper: Get appropriate path untuk buku hasil split (per-kitab)
    /// Return path untuk file kitab tunggal (bkid.sqlite)
    /// - Bundle Mode: ~/Library/Application Support/Maktabah/Caches/Books/
    /// - Custom Mode: {custom_folder}/Books/
    static var bookFilesPath: String? {
        if let customPath = customDatabasePath {
            let path = "\(customPath)/Books"
            return ensureDirectoryExists(at: path)
        }

        if isUsingBundleMode, let cachePath = archiveCachePath {
            let path = "\(cachePath)/Books"
            return ensureDirectoryExists(at: path)
        }

        return nil
    }

    // MARK: - Download Base URL (per-kitab)
    /// Legacy fallback base URL (direct file hosting).
    /// Jika tidak diset, fallback ini tidak digunakan.
    /// Override via UserDefaults key: book_download_base_url
    static var bookDownloadBaseURL: URL? {
        if let raw = UserDefaults.standard.string(forKey: bookDownloadBaseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return nil
    }

    static var hasCustomBookDownloadBaseURL: Bool {
        if let raw = UserDefaults.standard.string(forKey: bookDownloadBaseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            return !raw.isEmpty
        }
        return false
    }

    // MARK: - GitHub Releases (per-kitab)
    /// Base URL untuk download asset GitHub Releases.
    /// Default: https://github.com/bismillah-100/Kitab/releases/download
    /// Override via UserDefaults key: book_release_base_url
    static var bookReleaseBaseURL: URL? {
        if let raw = UserDefaults.standard.string(forKey: bookReleaseBaseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://github.com/bismillah-100/Kitab/releases/download")
    }

    /// URL index.json (mapping bkid -> release tag + filename).
    /// Default: https://raw.githubusercontent.com/bismillah-100/Kitab/main/index.json
    /// Override via UserDefaults key: book_index_url
    static var bookIndexURL: URL? {
        if let raw = UserDefaults.standard.string(forKey: bookIndexURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://raw.githubusercontent.com/bismillah-100/Kitab/main/index.json")
    }

    // MARK: - Core Database Update Check (version.txt based, cached 6 months)

    static let coreVersionURLKey = "core_version_url"
    static let lastCoreVersionCheckKey = "last_core_version_check"
    static let cachedCoreVersionKey = "cached_core_version"

    /// URL untuk version.txt di GitHub
    /// Default: https://raw.githubusercontent.com/bismillah-100/Kitab/main/version.txt
    static var coreVersionURL: URL? {
        if let raw = UserDefaults.standard.string(forKey: coreVersionURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://raw.githubusercontent.com/bismillah-100/Kitab/main/version.txt")
    }

    /// Interval cache: 6 bulan dalam detik
    private static let coreVersionCacheInterval: TimeInterval = 180 * 24 * 60 * 60 // ~6 bulan

    /// Cek apakah perlu check versi terbaru (throttle 6 bulan, dinonaktifkan jika auto-check off)
    static var shouldCheckCoreVersion: Bool {
        if !UserDefaults.standard.enableAutoCoreVersionCheck {
            return false
        }

        guard let lastCheck = UserDefaults.standard.object(forKey: lastCoreVersionCheckKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) >= coreVersionCacheInterval
    }

    /// Versi core yang di-cache (tag)
    static var cachedCoreVersion: String? {
        get { UserDefaults.standard.string(forKey: cachedCoreVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: cachedCoreVersionKey) }
    }

    /// Versi core dalam bentuk Double (e.g., 1.1) untuk kemudahan komparasi angka
    static var cachedCoreVersionDouble: Double? {
        // 1. Pastikan string versi tidak nil
        guard let versionString = cachedCoreVersion else { return nil }

        // 2. Ambil hanya pola angka dan titik (misal: "1.1" dari "v1.1-core")
        let regex = /[0-9]+\.[0-9]+/
        if let match = versionString.firstMatch(of: regex) {
            return Double(match.output)
        }

        // Jika format string tidak sesuai pola angka desimal
        return nil
    }

    /// Tandai telah selesai check versi
    static func markCoreVersionCheckDone(newVersion: String?) {
        if let v = newVersion {
            UserDefaults.standard.set(Date(), forKey: lastCoreVersionCheckKey)
            UserDefaults.standard.set(v, forKey: cachedCoreVersionKey)
        }
    }

    /// Force refresh: hapus cache dan check ulang
    static func forceRefreshCoreVersion() {
        UserDefaults.standard.removeObject(forKey: lastCoreVersionCheckKey)
        UserDefaults.standard.removeObject(forKey: cachedCoreVersionKey)
    }

    // MARK: - App Updates
    static var appcastURL: URL? {
        if let raw = UserDefaults.standard.string(forKey: appcastURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }

        return URL(
            string: "https://bismillah-100.github.io/Maktabah/appcast.xml"
        )
    }

    static var appSupportDir: URL? {
        do {
            let fm = FileManager.default
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let maktabahDir = appSupport.appendingPathComponent("Maktabah", isDirectory: true)

            // Buat folder Maktabah kalau belum ada
            if !fm.fileExists(atPath: maktabahDir.path) {
                try fm.createDirectory(
                    at: maktabahDir,
                    withIntermediateDirectories: true
                )
            }

            return maktabahDir
        } catch {
            print("Failed to create Maktabah folder:", error)
            return nil
        }
    }

    static func resolvedPath(for key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }

        var isStale = false
        do {
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif

            let url = try URL(
                resolvingBookmarkData: data,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            let startAccess = url.startAccessingSecurityScopedResource()
            if startAccess {
                return url
            }
        } catch {
            print("Bookmark resolve error:", error)
        }
        return nil
    }

    static func saveBookmark(url: URL, key: String) {
        do {
            #if os(macOS)
            let options: URL.BookmarkCreationOptions = .withSecurityScope
            #else
            let options: URL.BookmarkCreationOptions = []
            #endif
            let bookmarkData = try url.bookmarkData(options: options,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: key)
        } catch {
            print("Gagal membuat bookmark: \(error)")
        }
    }

    static let useICloudKey = "use_icloud_for_annotations"
    static let useCrossPlatformSyncKey = "use_cross_platform_sync"

    // MARK: - iCloud Support
    static var useICloud: Bool {
        get { UserDefaults.standard.bool(forKey: useICloudKey) }
        set { UserDefaults.standard.set(newValue, forKey: useICloudKey) }
    }

    static var useCrossPlatformSync: Bool {
        get { UserDefaults.standard.bool(forKey: useCrossPlatformSyncKey) }
        set { UserDefaults.standard.set(newValue, forKey: useCrossPlatformSyncKey) }
    }

    static var customWorkerURL: String {
        get { UserDefaults.standard.string(forKey: "custom_worker_url") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "custom_worker_url") }
    }

    static var iCloudFolderURL: URL? {
        guard let url = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true) else {
            return nil
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        return url
    }

    static func folder(for key: String) -> URL? {
        if let custom = resolvedPath(for: key) {
            return custom
        }

        return appSupportDir
    }

    private static func ensureDirectoryExists(at path: String) -> String? {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: path) {
                try fm.createDirectory(
                    atPath: path,
                    withIntermediateDirectories: true
                )
            }
            return path
        } catch {
            print("Error creating directory:", error)
            return nil
        }
    }

    // MARK: - Database Initialization with Dual-Mode Support

    /// Hanya menetapkan mode (custom/bundle), tanpa menyentuh DatabaseManager.
    /// Dipanggil dari AppDelegate.init() sebelum CoreDatabaseBootstrap berjalan.
    static func initializeMode() {
        if hasCustomDatabaseFolder() {
            // Custom mode sudah set, tidak perlu perubahan
        } else if isUsingBundleMode {
            // Bundle mode sudah aktif
        } else {
            // First launch: aktifkan bundle mode
            migrateToBundleMode()
        }
    }

    // MARK: - Bundle Initialization & Migration Methods

    /// Setup Bundle Mode: Initialize untuk menggunakan database dari Bundle
    /// Untuk Bundle Mode:
    /// - main.sqlite, special.sqlite berada di: .app/Contents/Resources/Files/
    /// - Archive files akan berada di: ~/Library/Application Support/Maktabah/Caches/
    static func setupBundleMode() -> Bool {
        // Ensure archive cache folder exists
        let fm = FileManager.default
        guard let cachePath = archiveCachePath else {
            print("Archive cache path tidak tersedia")
            return false
        }

        do {
            // Create cache folder jika belum ada (untuk future archive downloads)
            if !fm.fileExists(atPath: cachePath) {
                try fm.createDirectory(
                    atPath: cachePath,
                    withIntermediateDirectories: true
                )
                #if DEBUG
                    print("Created archive cache directory")
                #endif
            }

            // Set Bundle Mode flag
            isUsingBundleMode = true
            #if DEBUG
                print("Bundle Mode setup selesai")
                print("Archive cache: \(cachePath)")
            #endif
            return true
        } catch {
            print("Error setup Bundle Mode:", error)
            return false
        }
    }

    /// Migrate ke Bundle Mode pada first launch
    static func migrateToBundleMode() {
        // Clear custom folder setting jika ada
        resetCustomModeKey()

        // Setup bundle mode
        _ = setupBundleMode()
    }

    /// Reset semua key custom database di UserDefaults
    static func resetCustomModeKey() {
        isUsingBundleMode = true
        UserDefaults.standard.removeObject(forKey: AppConfig.customDatabaseFolderKey)
        UserDefaults.standard.removeObject(forKey: AppConfig.storageKey)
    }

    /// Migrate ke Custom Mode: Switch dari Bundle ke user-selected folder
    /// - Parameter folderUrl: URL folder yang dipilih user
    /// - Returns: True jika migration berhasil
    static func migrateToCustomMode(folderUrl: URL) -> Bool {
        do {
            // 1. Save custom folder bookmark
            saveBookmark(url: folderUrl, key: customDatabaseFolderKey)

            // 2. Create Files subdirectory structure di custom folder
            let fm = FileManager.default
            let filesDir = folderUrl.appendingPathComponent("Files", isDirectory: true)

            if !fm.fileExists(atPath: filesDir.path) {
                try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
            }

            // 3. Copy bundle databases ke custom folder jika belum ada
            if let bundlePath = archiveCachePath {
                let mainSqFile = "main.sqlite"
                let specialSqFile = "special.sqlite"
                // let specialFtsSqFile = "special_fts.sqlite"

                for fileName in [mainSqFile, specialSqFile] {
                    let sourcePath = "\(bundlePath)/\(fileName)"
                    let destPath = filesDir.appendingPathComponent(fileName).path

                    // Copy hanya jika destination belum ada (respect existing user files)
                    if !fm.fileExists(atPath: destPath) && fm.fileExists(atPath: sourcePath) {
                        try fm.copyItem(atPath: sourcePath, toPath: destPath)
                        #if DEBUG
                            print("Copied \(fileName) ke custom folder")
                        #endif
                    }
                }
            }

            // 4. Disable Bundle Mode
            isUsingBundleMode = false
            #if DEBUG
                print("Migrated to Custom Mode: \(folderUrl.path)")
            #endif
            return true
        } catch {
            #if DEBUG
                print("Error migrating to Custom Mode:", error)
            #endif
            return false
        }
    }

    /// Check jika user sudah setup custom database folder
    static func hasCustomDatabaseFolder() -> Bool {
        return UserDefaults.standard.data(forKey: customDatabaseFolderKey) != nil
    }

    static func setupAnnotationsAndResults() {
        let activeFolder = AppConfig.folder(for: AppConfig.annotationsAndResultsFolder)

        // Migrasi dari iCloud Drive ke folder aktif jika aktif
        if useICloud, let iCloud = iCloudFolderURL, let dest = activeFolder,
           iCloud.standardized != dest.standardized {
            AnnotationManager.shared.disconnect()
            ResultsHandler.shared.disconnect()
            migrateFiles(from: iCloud, to: dest)
        }

        do {
            if let annotationsFolder = activeFolder {
                try AnnotationManager.shared.setupAnnotations(at: annotationsFolder)
            }
        } catch {
            ReusableFunc.showAlert(
                title: String(localized: "errorFolderAnnotations"),
                message: error.localizedDescription
            )
        }

        do {
            if let resultsFolder = activeFolder {
                try ResultsHandler.shared.setupResultDatabase(at: resultsFolder)
            }
        } catch {
            ReusableFunc.showAlert(
                title: String(localized: "errorFolderSearchResults"),
                message: error.localizedDescription
            )
        }
    }

    private static func migrateFiles(from sourceURL: URL, to destURL: URL) {
        let fm = FileManager.default
        let files = ["Annotations.sqlite", "SearchResults.sqlite"]
        let exts = ["", "-wal", "-shm"]

        for file in files {
            for ext in exts {
                let fullFile = file + ext
                let source = sourceURL.appendingPathComponent(fullFile)
                let destination = destURL.appendingPathComponent(fullFile)

                if fm.fileExists(atPath: source.path), !fm.fileExists(atPath: destination.path) {
                    try? fm.moveItem(at: source, to: destination)
                }
            }
        }
    }

    enum MigrationResolution {
        case ask
        case keepDestination
        case overwriteDestination
    }

    /// Toggle iCloud support for annotations dan migrate files.
    /// Dipanggil dari Settings toggle (main thread). Operasi file dijalankan di background.
    /// - Parameters:
    ///   - use: true = aktifkan iCloud, false = nonaktifkan
    ///   - resolution: resolusi konflik file jika ada di tujuan
    ///   - completion: dipanggil di main thread setelah selesai, berisi error jika gagal
    static func setUseICloud(_ use: Bool, resolution: MigrationResolution = .ask, completion: @escaping (Error?) -> Void) {
        let oldFolder = AppConfig.folder(for: annotationsAndResultsFolder)
        useICloud = use

        if use {
            // 1. Move files from CURRENT folder (could be custom or old iCloud Drive) to appSupportDir
            if let source = oldFolder, let dest = appSupportDir, source.standardized != dest.standardized {
                migrateFiles(from: source, to: dest)
            }

            // 2. Reset bookmark to default local storage to avoid iCloud Drive conflicts
            UserDefaults.standard.removeObject(forKey: annotationsAndResultsFolder)

            // 3. Re-initialize databases at the default location
            setupAnnotationsAndResults()

            CloudKitSyncManager.shared.setupAndInitialSync()
        }
        DispatchQueue.main.async { completion(nil) }
    }
}

extension Notification.Name {
    static let libraryFolderChanged = Notification.Name("libraryFolderChanged")
    static let requireCoreDownload = Notification.Name("requireCoreDownload")
}
