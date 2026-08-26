//
//  BookUpdateManager.swift
//  Maktabah
//
//  Created by MacBook on 06/02/26.
//

import Foundation
import SQLite3

private struct BookDownloadArtifacts: Sendable {
    let workingDirectory: URL
    let downloadedBookURL: URL
    let ftsSourceURL: URL
}

final class BookUpdateManager {
    static let shared = BookUpdateManager()

    let versionColumnCandidates = [
        "bver", "bVer",
    ]
    var cachedVersionColumn: String?
    let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private init() {}

    struct StagedBookUpdate {
        let entry: BookIndexEntry
        let metadata: BookMetadata
        let downloadedBookURL: URL
        let ftsSourceURL: URL
        let authorContext: AuthorContext?
        let workingDirectory: URL
    }

    struct AuthorContext {
        let authId: Int
        let versionName: Int64
        let downloadURL: URL
    }

    enum BookVersionState {
        case notInLibrary
        case unknownVersion
        case version(Int64)

        var existsInLibrary: Bool {
            switch self {
            case .notInLibrary:
                false
            case .unknownVersion, .version:
                true
            }
        }

        var currentVersion: Int64? {
            switch self {
            case let .version(value):
                value
            case .notInLibrary, .unknownVersion:
                nil
            }
        }
    }

    func stageBookDownload(
        _ entry: BookIndexEntry,
        authIndex: [Int: AuthIndexEntry]
    ) async throws -> StagedBookUpdate {
        let (metadata, workingDirectory) = try await downloadAndReadMetadata(entry: entry)
        let bookArtifacts = try await downloadBookAndFtsSource(metadata: metadata, entry: entry)
        let authorContext = resolveAuthorContext(metadata: metadata, authIndex: authIndex)

        return StagedBookUpdate(
            entry: entry,
            metadata: metadata,
            downloadedBookURL: bookArtifacts.downloadedBookURL,
            ftsSourceURL: bookArtifacts.ftsSourceURL,
            authorContext: authorContext,
            workingDirectory: workingDirectory
        )
    }
    private func downloadAndReadMetadata(
        entry: BookIndexEntry
    ) async throws -> (metadata: BookMetadata, workingDirectory: URL) {
        guard let downloadURL = URL(string: entry.downloadURL) else {
            throw NSError(
                domain: "BookUpdate",
                code: -8,
                userInfo: [NSLocalizedDescriptionKey: "Download URL metadata tidak valid untuk buku \(entry.bkid)."]
            )
        }

        let workingDirectory = try makeWorkingDirectory()
        let downloadedMetadataURL = try await downloadFile(
            from: downloadURL,
            to: workingDirectory,
            SQLite: true,
            filePrefix: "metadata_\(entry.bkid)"
        )
        defer {
            FileManager.default.removeDatabaseAndSidecars(at: downloadedMetadataURL)
        }

        guard let metadata = try readBookMetadata(from: downloadedMetadataURL, fallbackBookId: entry.bkid) else {
            throw NSError(
                domain: "BookUpdate",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "Metadata kitab tidak ditemukan di book sqlite."]
            )
        }

        return (metadata, workingDirectory)
    }

    private func downloadBookAndFtsSource(
        metadata: BookMetadata,
        entry: BookIndexEntry
    ) async throws -> BookDownloadArtifacts {
        guard let link = metadata.link,
              let bookURL = URL(string: BookUpdateViewModel.driveLink + link)
        else {
            throw NSError(
                domain: "BookUpdate",
                code: -9,
                userInfo: [NSLocalizedDescriptionKey: "Link download buku tidak tersedia untuk buku \(entry.bkid)."]
            )
        }

        let newWorkingDirectory = try makeWorkingDirectory()
        let downloadedBookURL = try await downloadFile(
            from: bookURL,
            to: newWorkingDirectory,
            SQLite: true,
            filePrefix: "book_\(metadata.bkid)"
        )

        let ftsSourceURL = try prepareFtsSourceAndRename(
            downloadedBookURL: downloadedBookURL,
            bookId: metadata.bkid,
            workingDirectory: newWorkingDirectory
        )

        return BookDownloadArtifacts(
            workingDirectory: newWorkingDirectory,
            downloadedBookURL: downloadedBookURL,
            ftsSourceURL: ftsSourceURL
        )
    }

    func prepareFtsSourceAndRename(
        downloadedBookURL: URL,
        bookId: Int,
        workingDirectory: URL
    ) throws -> URL {
        let ftsSourceURL = workingDirectory.appendingPathComponent(
            "b\(bookId)_fts_source_\(UUID().uuidString).sqlite"
        )
        do {
            if FileManager.default.fileExists(atPath: ftsSourceURL.path) {
                try FileManager.default.removeItem(at: ftsSourceURL)
            }
            try FileManager.default.copyItem(at: downloadedBookURL, to: ftsSourceURL)
        } catch {
            FileManager.default.removeDatabaseAndSidecars(at: ftsSourceURL)
            FileManager.default.removeDatabaseAndSidecars(at: downloadedBookURL)
            throw error
        }

        try renameTablesIfNeeded(at: downloadedBookURL, to: bookId)
        try renameTablesIfNeeded(at: ftsSourceURL, to: bookId)
        return ftsSourceURL
    }

    private func resolveAuthorContext(
        metadata: BookMetadata,
        authIndex: [Int: AuthIndexEntry]
    ) -> AuthorContext? {
        guard let authId = metadata.authno,
              let authEntry = authIndex[authId],
              let authDownloadURL = URL(string: authEntry.downloadURL)
        else {
            return nil
        }
        return AuthorContext(
            authId: authId,
            versionName: authEntry.versionName,
            downloadURL: authDownloadURL
        )
    }

    @MainActor
    func integrateBooks(metadata: BookMetadata) {
        // Mark as integrated since the tables are already copied to the archive
        IntegrationCache.shared.markIntegrated(
            bookId: metadata.bkid,
            archiveId: metadata.archive
        )

        NotificationCenter.default.post(
            name: .bookIntegrated,
            object: metadata.bkid
        )
    }

    func makeWorkingDirectory() throws -> URL {
        guard let filesPath = AppConfig.databaseFilesPath else {
            throw NSError(
                domain: "BookUpdate",
                code: -4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Base path tidak tersedia.",
                ]
            )
        }

        let directory = URL(fileURLWithPath: filesPath)
            .appendingPathComponent("Updates", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        return directory
    }

    func cleanupWorkingDirectory() {
        guard let filesPath = AppConfig.databaseFilesPath else { return }
        let directory = URL(fileURLWithPath: filesPath).appendingPathComponent("Updates", isDirectory: true)
        FileManager.default.cleanupDirectory(at: directory)
    }

    func downloadFile(
        from url: URL,
        to directory: URL,
        SQLite: Bool = false,
        filePrefix: String? = nil
    ) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        let defaultName =
            url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let cleanedPrefix = filePrefix?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let nameSeed = cleanedPrefix.flatMap { $0.isEmpty ? nil : $0 } ?? defaultName
        var destination = directory.appendingPathComponent(
            "\(nameSeed)_\(UUID().uuidString)"
        )

        if SQLite {
            destination.appendPathExtension("sqlite")
        }

        #if DEBUG
        print("destination:", destination)
        #endif

        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
