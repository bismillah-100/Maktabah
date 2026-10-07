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

// MARK: - Bounded Bulk Downloader

enum BoundedBulkDownloader {
    static let defaultMaxConcurrent = 4

    struct ProgressReport: Sendable {
        let completed: Int
        let total: Int
        let downloadedBytes: Int64
        let totalBytes: Int64
    }

    static func run(
        books: [BooksData],
        maxConcurrent: Int = defaultMaxConcurrent,
        onTaskScheduled: (@Sendable (BooksData) -> Void)? = nil,
        onProgressUpdate: (@Sendable (ProgressReport) -> Void)? = nil,
        onBookCompleted: (@Sendable (BooksData, Result<URL, Error>, ProgressReport) -> Void)? = nil
    ) async -> (results: [Int: Result<URL, Error>], stoppedByNetwork: Bool) {
        let total = books.count
        guard total > 0 else { return ([:], false) }

        if await !NetworkMonitor.shared.isConnected {
            return ([:], true)
        }

        let totalBytes: Int64 = books.reduce(0) { $0 + max(0, $1.compressedDownloadSize ?? 0) }
        let booksById: [Int: BooksData] = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        let tracker = BulkDownloadProgressTracker(totalBooks: total, totalBytes: totalBytes)

        var downloadResults: [Int: Result<URL, Error>] = [:]
        var stoppedByNetwork = false

        await withTaskGroup(of: (Int, Result<URL, Error>).self) { group in
            var nextIndex = 0

            func schedule(book: BooksData) {
                onTaskScheduled?(book)
                group.addTask(operation: makeDownloadTask(for: book, tracker: tracker, onProgressUpdate: onProgressUpdate))
            }

            while nextIndex < min(maxConcurrent, total) {
                guard !Task.isCancelled else { break }
                let book = books[nextIndex]
                nextIndex += 1
                schedule(book: book)
            }

            for await (bookId, result) in group {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                downloadResults[bookId] = result
                let expectedSize = booksById[bookId]?.compressedDownloadSize
                let progress = await tracker.markBookCompleted(bookId: bookId, expectedBookSize: expectedSize)
                let report = ProgressReport(
                    completed: progress.completed,
                    total: progress.total,
                    downloadedBytes: progress.downloadedBytes,
                    totalBytes: progress.totalBytes
                )

                if let book = booksById[bookId] {
                    onBookCompleted?(book, result, report)
                }

                if case let .failure(error) = result, BookDownloadManager.isNetworkFailure(error) {
                    stoppedByNetwork = true
                    // Hentikan penambahan antrean unduhan baru saat jaringan bermasalah,
                    // tetapi biarkan unduhan yang sedang berjalan (in-flight) selesai dan disimpan.
                } else if !stoppedByNetwork && nextIndex < total && !Task.isCancelled {
                    let nextBook = books[nextIndex]
                    nextIndex += 1
                    schedule(book: nextBook)
                }
            }
        }

        return (downloadResults, stoppedByNetwork)
    }

    private static func makeDownloadTask(
        for book: BooksData,
        tracker: BulkDownloadProgressTracker,
        onProgressUpdate: (@Sendable (ProgressReport) -> Void)?
    ) -> @Sendable () async -> (Int, Result<URL, Error>) {
        {
            let download = await BookDownloadManager.shared.downloadBookResult(
                bookId: book.id,
                expectedSize: book.compressedDownloadSize,
                onProgress: { written, bookTotal in
                    Task {
                        let progress = await tracker.updateProgress(
                            bookId: book.id,
                            bytesWritten: written,
                            bookTotal: bookTotal
                        )
                        onProgressUpdate?(ProgressReport(
                            completed: progress.completed,
                            total: progress.total,
                            downloadedBytes: progress.downloadedBytes,
                            totalBytes: progress.totalBytes
                        ))
                    }
                }
            )
            return (download.bookId, download.result)
        }
    }
}

