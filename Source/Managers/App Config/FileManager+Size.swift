//
//  FileManager+Size.swift
//  Maktabah
//

import Foundation

extension FileManager {
    func isNonEmptyFile(atPath path: String) -> Bool {
        guard fileExists(atPath: path) else { return false }
        let size = (try? attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        return size > 0
    }

    func isNonEmptyFile(at url: URL) -> Bool {
        isNonEmptyFile(atPath: url.path)
    }

    func removeDatabaseAndSidecars(at url: URL) {
        removeDatabaseAndSidecars(atPath: url.path)
    }

    func removeDatabaseAndSidecars(atPath path: String) {
        try? removeItem(atPath: path)
        try? removeItem(atPath: path + "-wal")
        try? removeItem(atPath: path + "-shm")
        try? removeItem(atPath: path + "-journal")
    }

    func cleanupDirectory(at url: URL) {
        guard let items = try? contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return }

        for item in items {
            removeDatabaseAndSidecars(at: item)
        }
    }
}
