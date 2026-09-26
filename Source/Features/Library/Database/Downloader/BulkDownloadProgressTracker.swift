//
//  BulkDownloadProgressTracker.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 26/09/26.
//

import Foundation

actor BulkDownloadProgressTracker {
    struct Progress {
        let completed: Int
        let total: Int
        let downloadedBytes: Int64
        let totalBytes: Int64
    }

    let totalBooks: Int
    private(set) var totalBytes: Int64
    private var completedBooksCount: Int = 0
    private var bookBytes: [Int: Int64] = [:]
    private var completedBookIds: Set<Int> = []

    init(totalBooks: Int, totalBytes: Int64) {
        self.totalBooks = totalBooks
        self.totalBytes = totalBytes
    }

    func updateProgress(
        bookId: Int,
        bytesWritten: Int64,
        bookTotal: Int64
    ) -> Progress {
        if !completedBookIds.contains(bookId) {
            bookBytes[bookId] = bytesWritten
        }
        let totalDownloaded = bookBytes.values.reduce(0, +)
        return Progress(
            completed: completedBooksCount,
            total: totalBooks,
            downloadedBytes: totalDownloaded,
            totalBytes: totalBytes
        )
    }

    func markBookCompleted(
        bookId: Int,
        expectedBookSize: Int64?
    ) -> Progress {
        completedBooksCount += 1
        completedBookIds.insert(bookId)
        if let expected = expectedBookSize, expected > 0 {
            bookBytes[bookId] = max(bookBytes[bookId] ?? 0, expected)
        }
        let totalDownloaded = bookBytes.values.reduce(0, +)
        return Progress(
            completed: completedBooksCount,
            total: totalBooks,
            downloadedBytes: totalDownloaded,
            totalBytes: totalBytes
        )
    }
}

