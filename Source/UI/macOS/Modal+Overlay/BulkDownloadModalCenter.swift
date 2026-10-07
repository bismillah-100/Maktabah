//
//  BulkDownloadModalCenter.swift
//  Maktabah
//

import AppKit

// MARK: - BulkDownloadModalCenter

/// Mengelola modal window bulk download dan mengorkestrasikan:
///  - Download kitab secara concurrent (TaskGroup)
///  - Integrasi (copy tables + FTS) secara serial
///
/// Pemakaian dari menu item:
/// ```swift
/// @IBAction func bulkDownloadMenuAction(_ sender: Any) {
///     BulkDownloadModalCenter.shared.presentModal()
/// }
/// ```
@MainActor
final class BulkDownloadModalCenter {
    static let shared = BulkDownloadModalCenter()

    private var window: NSWindow?
    private var vc: BulkDownloadVC?
    private var downloadTask: Task<Void, Never>?
    private var shouldStopDownloads = false
    private var isDismissing = false

    private init() {}

    // MARK: - Modal presentation

    func presentModal() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let bulkVC = BulkDownloadVC()
        vc = bulkVC

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = String(localized: .Library.downloadBook)
        w.contentViewController = bulkVC
        w.minSize = NSSize(width: 440, height: 360)
        w.isReleasedWhenClosed = false
        w.delegate = WindowCloseDelegate.shared
        window = w

        w.center()
        NSApp.runModal(for: w)
    }

    func dismissModal() {
        guard !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }

        if NSApp.modalWindow != nil {
            NSApp.stopModal()
        }
        let w = window
        window = nil
        vc = nil
        w?.delegate = nil
        w?.orderOut(nil)
        w?.close()
    }

    // MARK: - Download orchestration

    func startDownload(books: [BooksData], vc: BulkDownloadVC) {
        shouldStopDownloads = false

        downloadTask = Task.detached { [weak self] in
            guard let self else { return }
            await runBulkDownload(books: books, vc: vc)
        }
    }

    func stop() {
        shouldStopDownloads = true
        Task {
            await BookDownloadManager.shared.cancelAllDownloads()
            await MainActor.run { [weak vc] in
                vc?.statusLabel.stringValue = String(localized: .Library.stoppingDownloadsIntegrating)
                vc?.stopButton.isEnabled = false
            }
        }
    }

    // MARK: - Core logic

    private func runBulkDownload(books: [BooksData], vc: BulkDownloadVC) async {
        let total = books.count
        let totalBytes: Int64 = books.reduce(0) { $0 + max(0, $1.compressedDownloadSize ?? 0) }
        vc.updateDownloadProgress(completed: 0, total: total, downloadedBytes: 0, totalBytes: totalBytes)

        // ── Fase 1: Download concurrent ──────────────────────────────────────
        let downloadResults = await executeConcurrentDownloads(
            books: books,
            vc: vc,
            total: total,
            totalBytes: totalBytes
        )

        let successfulDownloads = books.filter {
            if case .success = downloadResults[$0.id] {
                return true
            }
            return false
        }
        let integrateTotal = successfulDownloads.count

        // ── Fase 2: Integrate serial ──────────────────────────────────────────
        let completedIntegrations = await executeSerialIntegrations(successfulDownloads: successfulDownloads, vc: vc, integrateTotal: integrateTotal)

        // ── Selesai ───────────────────────────────────────────────────────────
        finalizeProcess(books: books, vc: vc, completedIntegrations: completedIntegrations, integrateTotal: integrateTotal)
    }

    private func executeConcurrentDownloads(
        books: [BooksData],
        vc: BulkDownloadVC,
        total: Int,
        totalBytes: Int64
    ) async -> [Int: Result<URL, Error>] {
        if await !NetworkMonitor.shared.isConnected {
            shouldStopDownloads = true
            vc.statusLabel.stringValue = String(localized: .Library.noInternetSkippingDownloads)
            return [:]
        }

        let (downloadResults, stoppedByNetwork) = await BoundedBulkDownloader.run(
            books: books,
            onTaskScheduled: { [weak vc] book in
                Task { @MainActor [weak vc] in
                    vc?.updateStatus(bookId: book.id, status: .downloading)
                }
            },
            onProgressUpdate: { [weak vc] report in
                Task { @MainActor [weak vc] in
                    vc?.updateDownloadProgress(
                        completed: report.completed,
                        total: report.total,
                        downloadedBytes: report.downloadedBytes,
                        totalBytes: report.totalBytes
                    )
                }
            },
            onBookCompleted: { [weak vc] book, result, report in
                Task { @MainActor [weak vc] in
                    vc?.updateDownloadProgress(
                        completed: report.completed,
                        total: report.total,
                        downloadedBytes: report.downloadedBytes,
                        totalBytes: report.totalBytes
                    )
                    switch result {
                    case .success:
                        vc?.updateStatus(bookId: book.id, status: .downloaded)
                    case let .failure(error):
                        vc?.updateStatus(bookId: book.id, status: .failed(error.localizedDescription))
                    }
                }
            }
        )

        if stoppedByNetwork {
            shouldStopDownloads = true
        }

        return downloadResults
    }

    private func executeSerialIntegrations(successfulDownloads: [BooksData], vc: BulkDownloadVC, integrateTotal: Int) async -> Int {
        var completedIntegrations = 0
        vc.updateIntegrateProgress(completed: 0, total: integrateTotal)

        for book in successfulDownloads {
            guard !Task.isCancelled else { break }

            if BookArchiveIntegrator.shared.isBookIntegrated(book) {
                vc.updateStatus(bookId: book.id, status: .done)
                completedIntegrations += 1
                vc.updateIntegrateProgress(
                    completed: completedIntegrations,
                    total: integrateTotal
                )
                continue
            }

            do {
                try await BookArchiveIntegrator.shared.ensureBookIntegrated(
                    book,
                    onIntegrating: {
                        await MainActor.run {
                            vc.updateStatus(bookId: book.id, status: .integrating)
                        }
                    },
                    onProgress: { phase in
                        await MainActor.run {
                            // Perbarui status badge di baris kitab dalam outline
                            switch phase {
                            case .fts:
                                vc.updateStatus(bookId: book.id, status: .integratingFTS)
                            case .data:
                                vc.updateStatus(bookId: book.id, status: .integratingData)
                            }
                            // Perbarui label status utama dengan nama kitab + fase
                            vc.updateCurrentBook(book.book, phase: phase)
                        }
                    }
                )
                vc.updateStatus(bookId: book.id, status: .done)
            } catch {
                vc.updateStatus(
                    bookId: book.id,
                    status: .failed(error.localizedDescription)
                )
            }

            completedIntegrations += 1
            vc.updateIntegrateProgress(
                completed: completedIntegrations,
                total: integrateTotal
            )
        }
        return completedIntegrations
    }

    private func finalizeProcess(books: [BooksData], vc: BulkDownloadVC, completedIntegrations: Int, integrateTotal: Int) {
        downloadTask = nil
        vc.setDownloading(false)

        let failedCount = books.count(where: {
            if case .failed = vc.bookStatuses[$0.id] {
                return true
            }
            return false
        })

        if Task.isCancelled {
            vc.statusLabel.stringValue = String(localized: .Library.stoppedBooksCompleted(completedIntegrations))
        } else if failedCount > 0 {
            vc.statusLabel.stringValue = String(localized: .Library.completedAndFailedCount(completedIntegrations, failedCount))
        } else if integrateTotal == 0 {
            vc.statusLabel.stringValue = String(localized: .Library.noBooksDownloaded)
        } else if shouldStopDownloads {
            vc.statusLabel.stringValue = String(localized: .Library.stoppedDownloadsCompleted(completedIntegrations))
        } else {
            vc.statusLabel.stringValue = String(localized: .Library.allBooksProcessedSuccessfully(completedIntegrations))
        }
    }
}

// MARK: - WindowCloseDelegate

@MainActor
private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowCloseDelegate()

    func windowWillClose(_ notification: Notification) {
        BulkDownloadModalCenter.shared.stop()
        if NSApp.modalWindow != nil {
            NSApp.stopModal()
        }
        BulkDownloadModalCenter.shared.dismissModal()
    }
}
