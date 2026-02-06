//
//  DatabaseError.swift
//  Maktabah
//
//  Created by MacBook on 05/02/26.
//

import Foundation

extension DatabaseManager {
    /// Kesalahan kustom untuk operasi database.
    enum DatabaseError: Error, LocalizedError {
        case noConnection
        case authorNotFound(Int)
        case bookNotFound(Int)
        case other(String)

        var errorDescription: String? {
            switch self {
            case .noConnection:
                return NSLocalizedString(
                    "Database connection is not available.",
                    comment: ""
                )
            case .authorNotFound(let id):
                return NSLocalizedString(
                    "Author with ID \(id) not found.",
                    comment: ""
                )
            case .bookNotFound(let id):
                return NSLocalizedString(
                    "Book with ID \(id) not found.",
                    comment: ""
                )
            case .other(let message):
                return NSLocalizedString(
                    "Database error: \(message)",
                    comment: ""
                )
            }
        }
    }
}
