//
//  ErrorEnum.swift
//  Maktabah
//
//  Created by Ghoys on 31/01/26.
//

import Foundation

enum StorageError: Error, LocalizedError {
    case invalidDirectory
    case cannotAccessSecurityScope
    case collision(URL?)
    case downloadTimeout(String)

    var errorDescription: String? {
        switch self {
        case .invalidDirectory:
            return "Invalid directory."
        case .cannotAccessSecurityScope:
            return "Cannot access security scoped directory."
        case .collision:
            return "File already exists at destination."
        case .downloadTimeout(let file):
            return "Timeout waiting for iCloud download: \(file)"
        }
    }
}
