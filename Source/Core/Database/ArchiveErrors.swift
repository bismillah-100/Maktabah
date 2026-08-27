//
//  ArchiveErrors.swift
//  Maktabah
//
//  Created by MacBook on 26/02/26.
//  Error types untuk archive file management dan download
//

import Foundation

enum ArchiveError: LocalizedError {
    /// Archive file tidak ditemukan
    case archiveNotAvailable(archiveId: Int)

    /// FTS file tidak ditemukan untuk archive
    case ftsDatabaseNotAvailable(archiveId: Int)

    /// Keduanya (archive dan FTS) tidak ada
    case archiveIncomplete(archiveId: Int)

    /// Path database tidak tersedia
    case databasePathNotAvailable

    /// File sudah ada di tujuan
    case fileAlreadyExists(path: String)

    /// File tidak dapat dibaca
    case fileNotReadable(path: String)

    /// Path tidak ada
    case invalidPath(String)

    // Koneksi error
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .archiveNotAvailable(let archiveId):
            return "Archive \(archiveId) is not available. Please download it first."

        case .ftsDatabaseNotAvailable(let archiveId):
            return "FTS database for archive \(archiveId) is not available."

        case .archiveIncomplete(let archiveId):
            return "Archive \(archiveId) is incomplete. Both main and FTS database files are required."

        case .databasePathNotAvailable:
            return "Database path is not available. Please select a database folder."

        case .fileAlreadyExists(let path):
            return "File already exists at: \(path)"

        case .fileNotReadable(let path):
            return "Cannot read file at: \(path)"

        case .invalidPath(let path):
            return "Invalid database path: \(path)"

        case .connectionFailed(let reason):
            return "Failed to connect to database: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .archiveNotAvailable(let archiveId):
            return "Try downloading archive \(archiveId) from the Books menu."

        case .ftsDatabaseNotAvailable(let archiveId):
            return "Re-download archive \(archiveId) and ensure both files are present."

        case .archiveIncomplete(let archiveId):
            return "Download both main and FTS database files for archive \(archiveId)."

        case .databasePathNotAvailable:
            return "Go to Settings and select or create a database folder."

        case .fileAlreadyExists(let path):
            return "Choose a different location or delete the existing file at: \(path)"

        case .fileNotReadable(let path):
            return "Check file permissions at: \(path)"

        case .invalidPath(let path):
            return "Invalid database path: \(path)"

        case .connectionFailed(let reason):
            return "Failed to connect to database: \(reason)"
        }
    }
}
