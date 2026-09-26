//
//  BulkDownloadProgressTracker.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 26/09/26.
//

import Foundation

actor BulkDownloadProgressTracker {
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
    ) -> (completed: Int, total: Int, downloadedBytes: Int64, totalBytes: Int64) {
        if !completedBookIds.contains(bookId) {
            bookBytes[bookId] = bytesWritten
        }
        let totalDownloaded = bookBytes.values.reduce(0, +)
        return (completedBooksCount, totalBooks, totalDownloaded, totalBytes)
    }

    func markBookCompleted(
        bookId: Int,
        expectedBookSize: Int64?
    ) -> (completed: Int, total: Int, downloadedBytes: Int64, totalBytes: Int64) {
        completedBooksCount += 1
        completedBookIds.insert(bookId)
        if let expected = expectedBookSize, expected > 0 {
            bookBytes[bookId] = max(bookBytes[bookId] ?? 0, expected)
        }
        let totalDownloaded = bookBytes.values.reduce(0, +)
        return (completedBooksCount, totalBooks, totalDownloaded, totalBytes)
    }
}
