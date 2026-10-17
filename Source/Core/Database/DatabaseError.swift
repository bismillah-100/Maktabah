//
//  DatabaseError.swift
//  Maktabah
//
//  Created by MacBook on 05/02/26.
//

import Foundation

/// Kesalahan kustom untuk operasi database.
enum DatabaseError: Error, LocalizedError {
    case noConnection
    case authorNotFound(Int)
    case bookNotFound(Int)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .noConnection:
            String(
                localized: "Database connection is not available."
            )
        case let .authorNotFound(id):
            String(
                localized: "Author with ID \(id) not found."
            )
        case let .bookNotFound(id):
            String(
                localized: .Library.bookNotFound(id)
            )
        case let .other(message):
            String(
                localized: "Database error: \(message)"
            )
        }
    }
}
