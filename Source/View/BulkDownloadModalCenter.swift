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

final class BulkDownloadModalCenter {
    static let shared = BulkDownloadModalCenter()

    private var window: NSWindow?
    private var vc: BulkDownloadVC?
    private var downloadTask: Task<Void, Never>?
    private var shouldStopDownloads = false

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
        w.title = NSLocalizedString(
            "Download Book",
            comment: "Bulk download window title"
        )
        w.contentViewController = bulkVC
        w.minSize = NSSize(width: 440, height: 360)
        w.isReleasedWhenClosed = false
        w.delegate = WindowCloseDelegate.shared
        window = w

        w.center()
        NSApp.runModal(for: w)
    }

    func dismissModal() {
        if NSApp.modalWindow != nil {
            NSApp.stopModal()
        }
        window?.orderOut(nil)
        window?.close()
        vc = nil
        window = nil
    }

    // MARK: - Download orchestration
    @MainActor
    func startDownload(books: [BooksData], vc: BulkDownloadVC) {
        shouldStopDownloads = false

        downloadTask = Task { [weak self] in
            guard let self else { return }
            await runBulkDownload(books: books, vc: vc)
        }
    }

    @MainActor
    func stop() {
        shouldStopDownloads = true
        Task {
            await BookDownloadManager.shared.cancelAllDownloads()
            await MainActor.run { [weak vc] in
                vc?.statusLabel.stringValue = NSLocalizedString(
                    "Stopping downloads. Integrating completed books...",
                    comment: "Bulk download stopping message"
                )
                vc?.stopButton.isEnabled = false
            }
        }
    }

    // MARK: - Core logic

    @MainActor
    private func runBulkDownload(books: [BooksData], vc: BulkDownloadVC) async {
        let total = books.count
        vc.updateDownloadProgress(completed: 0, total: total)

        // ── Fase 1: Download concurrent ──────────────────────────────────────
        let downloadResults = await executeConcurrentDownloads(books: books, vc: vc, total: total)

        let successfulDownloads = books.filter {
            if case .success = downloadResults[$0.id] { return true }
            return false
        }
        let integrateTotal = successfulDownloads.count

        // ── Fase 2: Integrate serial ──────────────────────────────────────────
        let completedIntegrations = await executeSerialIntegrations(successfulDownloads: successfulDownloads, vc: vc, integrateTotal: integrateTotal)

        // ── Selesai ───────────────────────────────────────────────────────────
        finalizeProcess(books: books, vc: vc, completedIntegrations: completedIntegrations, integrateTotal: integrateTotal)
    }

    @MainActor
    private func executeConcurrentDownloads(books: [BooksData], vc: BulkDownloadVC, total: Int) async -> [Int: Result<URL, Error>] {
        var downloadResults: [Int: Result<URL, Error>] = [:]
        var downloadedCount = 0

        if await !NetworkMonitor.shared.isConnected {
            shouldStopDownloads = true
            vc.statusLabel.stringValue = String(localized: "No internet connection. Skipping downloads.")
        }

        await withTaskGroup(of: (Int, Result<URL, Error>).self) { group in
            for book in books {
                guard !shouldStopDownloads, !Task.isCancelled else { break }
                group.addTask {
                    do {
                        let url = try await BookDownloadManager.shared
                            .ensureBookDownloaded(bookId: book.id)
                        return (book.id, .success(url))
                    } catch {
                        return (book.id, .failure(error))
                    }
                }
                vc.updateStatus(bookId: book.id, status: .downloading)
            }

            for await (bookId, result) in group {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                downloadResults[bookId] = result
                downloadedCount += 1
                vc.updateDownloadProgress(completed: downloadedCount, total: total)
                switch result {
                case .success:
                    vc.updateStatus(bookId: bookId, status: .downloaded)
                case .failure(let error):
                    vc.updateStatus(
                        bookId: bookId,
                        status: .failed(error.localizedDescription)
                    )
                    if error is CancellationError ||
                        vc.dataVM?.viewModel.isNetworkFailure(error) == true {
                        shouldStopDownloads = true
                        group.cancelAll()
                    }
                }
            }
        }
        return downloadResults
    }

    @MainActor
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

    @MainActor
    private func finalizeProcess(books: [BooksData], vc: BulkDownloadVC, completedIntegrations: Int, integrateTotal: Int) {
        downloadTask = nil
        vc.setDownloading(false)

        let failedCount = books.filter {
            if case .failed = vc.bookStatuses[$0.id] { return true }
            return false
        }.count

        if Task.isCancelled {
            vc.statusLabel.stringValue = String(localized: "Stopped. \(completedIntegrations) books completed.", comment: "Status message when the task is cancelled")
        } else if failedCount > 0 {
            vc.statusLabel.stringValue = String(localized: "\(completedIntegrations) completed, \(failedCount) failed.", comment: "Status message showing count of completed and failed downloads")
        } else if integrateTotal == 0 {
            vc.statusLabel.stringValue = String(localized: "No books were successfully downloaded.", comment: "Status message when no books were downloaded")
        } else if shouldStopDownloads {
            vc.statusLabel.stringValue = String(localized: "Stopped downloads. \(completedIntegrations) books completed.", comment: "Status message when user manually stops downloads")
        } else {
            vc.statusLabel.stringValue = String(localized: "All \(completedIntegrations) books processed successfully.", comment: "Status message when all tasks finished successfully")
        }
    }
}


// MARK: - WindowCloseDelegate

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowCloseDelegate()

    func windowWillClose(_ notification: Notification) {
        BulkDownloadModalCenter.shared.stop()
        if NSApp.modalWindow != nil {
            NSApp.stopModal()
        }
        DispatchQueue.main.async {
            BulkDownloadModalCenter.shared.dismissModal()
        }
    }
}
