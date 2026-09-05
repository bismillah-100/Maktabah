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

    @MainActor
    func startBulkDownload(
        progressState: BundleArchiveDownloadProgressState,
        onFinished: @escaping (String?) -> Void
    ) {
        let books = selectedDownloadBooks
        guard !books.isEmpty else { return }
        isBulkDownloading = true
        progressState.mode = .downloading
        progressState.title = NSLocalizedString("Download Book", comment: "Bulk download window title")
        progressState.message = String(localized: "Begin downloading...")
        progressState.detail = "0 / \(books.count)"
        progressState.progress = 0

        bulkDownloadTask = Task { [weak self] in
            guard let self else { return }
            await runBulkDownload(books: books, progressState: progressState, onFinished: onFinished)
        }
    }

    @MainActor
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

        let failedCount = books.filter {
            if case .failure = downloadResults[$0.id] {
                return true
            }
            return false
        }.count

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

    @MainActor
    private func performBulkDownloadPhase(
        books: [BooksData],
        progressState: BundleArchiveDownloadProgressState
    ) async -> ([Int: Result<URL, Error>], Bool) {
        let total = books.count
        var downloadedCount = 0
        var downloadResults: [Int: Result<URL, Error>] = [:]
        var stoppedByNetwork = false

        if await !NetworkMonitor.shared.isConnected {
            return (downloadResults, true)
        }

        await withTaskGroup(of: (Int, Result<URL, Error>).self) { group in
            for book in books {
                guard !Task.isCancelled else { break }
                group.addTask {
                    await BookDownloadManager.shared.downloadBookResult(bookId: book.id)
                }
            }
            for await (bookId, result) in group {
                if Task.isCancelled {
                    group.cancelAll(); break
                }
                downloadResults[bookId] = result
                downloadedCount += 1
                progressState.message = String(localized: "Downloading \(downloadedCount) of \(total) books...")
                progressState.detail = "\(downloadedCount) / \(total)"
                progressState.progress = total > 0 ? Double(downloadedCount) / Double(total) : 0
                if case let .failure(error) = result, isNetworkFailure(error) {
                    stoppedByNetwork = true
                    group.cancelAll()
                }
            }
        }
        return (downloadResults, stoppedByNetwork)
    }

    @MainActor
    private func performBulkIntegrationPhase(
        successfulDownloads: [BooksData],
        downloadResults: inout [Int: Result<URL, Error>],
        progressState: BundleArchiveDownloadProgressState
    ) async -> Int {
        let integrateTotal = successfulDownloads.count
        var completedIntegrations = 0

        progressState.mode = .integrating
        progressState.message = String(localized: "Download Complete. Begin integrating...")
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
            String(localized: "Stopped. \(completedIntegrations) books completed.", comment: "")
        } else if stoppedByNetwork {
            NSLocalizedString("Please check your internet connection", comment: "")
        } else if failedCount > 0 {
            String(localized: "\(completedIntegrations) completed, \(failedCount) failed.", comment: "")
        } else {
            String(localized: "All \(completedIntegrations) books processed successfully.", comment: "")
        }
    }
}
