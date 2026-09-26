//
//  BulkActionLibrary.swift
//  Maktabah
//

import Foundation

extension LibraryViewModel {
    // MARK: - Bulk Download Actions

    func cancelBulkDownload() {
        bulkDownloadTask?.cancel()
        bulkDownloadTask = nil
        isBulkDownloading = false
        Task { await BookDownloadManager.shared.cancelAllDownloads() }
    }

    func startBulkDownload(
        progressState: BundleArchiveDownloadProgressState,
        onFinished: @escaping (String?) -> Void
    ) {
        let books = selectedDownloadBooks
        guard !books.isEmpty else { return }
        isBulkDownloading = true
        progressState.mode = .downloading
        progressState.title = String(localized: .Library.downloadBook)
        progressState.message = String(localized: .Library.beginDownloading)
        progressState.detail = "0 / \(books.count)"
        progressState.progress = 0

        bulkDownloadTask = Task { [weak self] in
            guard let self else { return }
            await runBulkDownload(books: books, progressState: progressState, onFinished: onFinished)
        }
    }

    private func runBulkDownload(
        books: [BooksData],
        progressState: BundleArchiveDownloadProgressState,
        onFinished: @escaping (String?) -> Void
    ) async {
        var (downloadResults, stoppedByNetwork) = await performBulkDownloadPhase(
            books: books,
            progressState: progressState
        )

        let successfulDownloads = books.filter {
            if case .success = downloadResults[$0.id] {
                return true
            }
            return false
        }

        let completedIntegrations = await performBulkIntegrationPhase(
            successfulDownloads: successfulDownloads,
            downloadResults: &downloadResults,
            progressState: progressState
        )

        let failedCount = books.count(where: {
            if case .failure = downloadResults[$0.id] {
                return true
            }
            return false
        })

        selectedBookIds.subtract(books.map(\.id))
        isBulkDownloading = false
        bulkDownloadTask = nil

        let message = buildBulkCompletionMessage(
            isCancelled: Task.isCancelled,
            stoppedByNetwork: stoppedByNetwork,
            completedIntegrations: completedIntegrations,
            failedCount: failedCount
        )
        onFinished(message)
    }

    private func performBulkDownloadPhase(
        books: [BooksData],
        progressState: BundleArchiveDownloadProgressState
    ) async -> ([Int: Result<URL, Error>], Bool) {
        let total = books.count
        var downloadedCount = 0
        var downloadResults: [Int: Result<URL, Error>] = [:]
        var stoppedByNetwork = false

        let totalBytes: Int64 = books.reduce(0) { $0 + max(0, $1.compressedDownloadSize ?? 0) }
        let booksById: [Int: BooksData] = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        let tracker = BulkDownloadProgressTracker(totalBooks: total, totalBytes: totalBytes)

        if await !NetworkMonitor.shared.isConnected {
            return (downloadResults, true)
        }

        await withTaskGroup(of: (Int, Result<URL, Error>).self) { group in
            for book in books {
                guard !Task.isCancelled else { break }
                group.addTask {
                    await BookDownloadManager.shared.downloadBookResult(
                        bookId: book.id,
                        expectedSize: book.compressedDownloadSize,
                        onProgress: { written, bookTotal in
                            Task { @MainActor in
                                let progress = await tracker.updateProgress(
                                    bookId: book.id,
                                    bytesWritten: written,
                                    bookTotal: bookTotal
                                )
                                if progress.totalBytes > 0 {
                                    let writtenStr = ByteCountFormatter.string(fromByteCount: progress.downloadedBytes, countStyle: .file)
                                    let totalStr = ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)
                                    progressState.detail = "\(progress.completed)/\(progress.total) (\(writtenStr) / \(totalStr))"
                                    progressState.progress = min(1.0, Double(progress.downloadedBytes) / Double(progress.totalBytes))
                                }
                            }
                        }
                    )
                }
            }
            for await (bookId, result) in group {
                if Task.isCancelled {
                    group.cancelAll(); break
                }
                downloadResults[bookId] = result
                downloadedCount += 1
                let expectedSize = booksById[bookId]?.compressedDownloadSize
                let progress = await tracker.markBookCompleted(bookId: bookId, expectedBookSize: expectedSize)
                progressState.message = String(localized: .Library.downloadingCountOfTotal(downloadedCount, total))
                if progress.totalBytes > 0 {
                    let writtenStr = ByteCountFormatter.string(fromByteCount: progress.downloadedBytes, countStyle: .file)
                    let totalStr = ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)
                    progressState.detail = "\(downloadedCount)/\(total) (\(writtenStr) / \(totalStr))"
                    progressState.progress = min(1.0, Double(progress.downloadedBytes) / Double(progress.totalBytes))
                } else {
                    progressState.detail = "\(downloadedCount) / \(total)"
                    progressState.progress = total > 0 ? Double(downloadedCount) / Double(total) : 0
                }
                if case let .failure(error) = result, isNetworkFailure(error) {
                    stoppedByNetwork = true
                    group.cancelAll()
                }
            }
        }
        return (downloadResults, stoppedByNetwork)
    }

    private func performBulkIntegrationPhase(
        successfulDownloads: [BooksData],
        downloadResults: inout [Int: Result<URL, Error>],
        progressState: BundleArchiveDownloadProgressState
    ) async -> Int {
        let integrateTotal = successfulDownloads.count
        var completedIntegrations = 0

        progressState.mode = .integrating
        progressState.message = String(localized: .Library.downloadCompleteBeginIntegrating)
        progressState.detail = "0 / \(integrateTotal)"
        progressState.progress = 0

        for book in successfulDownloads {
            guard !Task.isCancelled else { break }
            if !BookArchiveIntegrator.shared.isBookIntegrated(book) {
                do {
                    try await BookArchiveIntegrator.shared.ensureBookIntegrated(
                        book,
                        onIntegrating: {},
                        onProgress: { phase in
                            await MainActor.run {
                                progressState.message = "\(phase == .fts ? "FTS" : "Data"): \(book.book)"
                            }
                        }
                    )
                } catch {
                    downloadResults[book.id] = .failure(error)
                }
            }
            completedIntegrations += 1
            progressState.detail = "\(completedIntegrations) / \(integrateTotal)"
            progressState.progress = integrateTotal > 0 ? Double(completedIntegrations) / Double(integrateTotal) : 0
        }
        return completedIntegrations
    }

    private func buildBulkCompletionMessage(
        isCancelled: Bool,
        stoppedByNetwork: Bool,
        completedIntegrations: Int,
        failedCount: Int
    ) -> String? {
        if isCancelled {
            String(localized: .Library.stoppedBooksCompleted(completedIntegrations))
        } else if stoppedByNetwork {
            String(localized: .Library.checkInternetConnection)
        } else if failedCount > 0 {
            String(localized: .Library.completedAndFailedCount(completedIntegrations, failedCount))
        } else {
            String(localized: .Library.allBooksProcessedSuccessfully(completedIntegrations))
        }
    }
}
