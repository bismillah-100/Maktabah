//
//  AppConfig.swift
//  Maktabah
//
//  Created by MacBook on 25/12/25.
//

import Foundation

struct AppConfig {
    static let storageKey = "selected_shamela_bookmark" // Ubah key agar fresh
    static let annotationsAndResultsFolder = "annotations_FolderPath"
    
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

    static var basePath: String? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: storageKey) else { return nil }

        var isStale = false
        do {
            // Mengambil kembali URL dari bookmark data
            let url = try URL(resolvingBookmarkData: bookmarkData,
                             options: .withSecurityScope,
                             relativeTo: nil,
                             bookmarkDataIsStale: &isStale)

            // Jika data usang, Anda bisa memperbaruinya di sini jika perlu
            if isStale {
                // handle stale bookmark
            }

            // StartAccessingSecurityScopedResource memberikan izin akses ke sandbox
            if url.startAccessingSecurityScopedResource() {
                return url.path
            }
        } catch {
            print("Error resolving bookmark: \(error)")
        }
        return nil
    }
    
    static func resolvedPath(for key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if url.startAccessingSecurityScopedResource() {
                return url
            }
        } catch {
            print("Bookmark resolve error:", error)
        }
        return nil
    }
    
    static func saveBookmark(url: URL, key: String) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: key)
        } catch {
            print("Gagal membuat bookmark: \(error)")
        }
    }
    
    static func folder(for key: String) -> URL? {
        if let custom = resolvedPath(for: key) {
            return custom
        }

        return appSupportDir
    }
}
