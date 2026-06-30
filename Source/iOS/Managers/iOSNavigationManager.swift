import Foundation
import SwiftUI
import UIKit

/// Manages the navigation and current mode for the iOS application.
@MainActor
@Observable
class iOSNavigationManager {
    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    struct ReaderTab: Identifiable, Equatable {
        let id: UUID
        let book: BooksData
        var initialContentId: Int?
        var viewModel: ReaderViewModel

        static func == (lhs: ReaderTab, rhs: ReaderTab) -> Bool {
            lhs.id == rhs.id
        }
    }

    var currentMode: AppMode = .viewer
    var selectedBook: BooksData?
    var selectedContentId: Int?
    var searchText: String = ""
    var showViewOptions: Bool = false
    var activeIntegrationStates: [BundleArchiveDownloadProgressState] = []
    var alertMessage: AlertMessage?

    var libraryViewModel = LibraryViewModel()
    var searchViewModel = SearchViewModel()
    var authorViewModel = NarratorViewModel()
    var annotationViewModel = AnnotationViewModel()

    var openTabs: [ReaderTab] = []
    var activeTabId: UUID?

    init() {
        setupObservers()
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: .bookIntegrated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let bookId = notification.object as? Int else { return }
            Task { @MainActor in
                self.handleBookIntegrationChanged(bookId: bookId)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .libraryFolderChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearAllTabs()
            }
        }
    }

    private func handleBookIntegrationChanged(bookId: Int) {
        // If a book is no longer integrated, close its tab
        let tabsToClose = openTabs.filter { tab in
            tab.book.id == bookId && !BookArchiveIntegrator.shared.isBookIntegrated(tab.book)
        }

        for tab in tabsToClose {
            closeTab(id: tab.id)
        }
    }

    func switchToMode(_ mode: AppMode) {
        currentMode = mode
    }

    func openBook(_ book: BooksData, initialContentId: Int? = nil, searchText: String? = nil, targetAnnotation: Annotation? = nil) {
        Task {
            await openBookAsync(book, initialContentId: initialContentId, searchText: searchText, targetAnnotation: targetAnnotation)
        }
    }

    func closeTab(id: UUID) {
        if let index = openTabs.firstIndex(where: { $0.id == id }) {
            let tab = openTabs[index]
            if activeTabId == id {
                tab.viewModel.saveCurrentState()
            }

            openTabs.remove(at: index)
            if activeTabId == id {
                activeTabId = openTabs.last?.id
                if let nextTabId = activeTabId, let nextTab = openTabs.first(where: { $0.id == nextTabId }) {
                    selectedBook = nextTab.book
                } else {
                    selectedBook = nil
                }
            } else if selectedBook?.id == tab.book.id {
                selectedBook = nil
            }
        }
    }

    func clearAllTabs() {
        for tab in openTabs {
            if activeTabId == tab.id {
                tab.viewModel.saveCurrentState()
            }
        }
        openTabs.removeAll()
        activeTabId = nil
        selectedBook = nil
        selectedContentId = nil
    }

    func selectTab(id: UUID) {
        if let activeId = activeTabId, let currentTab = openTabs.first(where: { $0.id == activeId }) {
            currentTab.viewModel.saveCurrentState()
        }
        activeTabId = id
        if let nextTab = openTabs.first(where: { $0.id == id }) {
            selectedBook = nextTab.book
            selectedContentId = nextTab.initialContentId
        }
    }

    func confirmPendingBookIntegration(state: BundleArchiveDownloadProgressState) {
        guard let pendingData = state.pendingData else { return }

        switch pendingData {
        case .bulk:
            state.mode = .downloading
            libraryViewModel.startBulkDownload(progressState: state) { [weak self] message in
                self?.activeIntegrationStates.removeAll { $0.id == state.id }
                self?.libraryViewModel.exitSelectionMode()

                if let message {
                    self?.alertMessage = AlertMessage(
                        title: NSLocalizedString(
                            "Download Book",
                            comment: "Bulk download window title"
                        ),
                        message: message
                    )
                }
            }

        case .single(let book, let initialContentId):
            state.mode = .downloading
            state.message = NSLocalizedString(
                "Downloading book file from server...",
                comment: "Book integrate downloading message"
            )
            state.detail = ""
            state.progress = 0

            Task {
                do {
                    try await BookArchiveIntegrator.shared.ensureBookIntegrated(
                        book,
                        onIntegrating: { [weak self] in
                            await MainActor.run { [weak self] in
                                self?.showIntegratingState(for: state)
                            }
                        }
                    )

                    await MainActor.run {
                        if !MaktabahApp.isIpad && self.selectedBook != nil {
                            // Do not automatically push a new book if there is already an active reader on iPhone
                        } else {
                            self.presentReader(book, initialContentId: initialContentId)
                        }
                        self.activeIntegrationStates.removeAll { $0.id == state.id }
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.activeIntegrationStates.removeAll { $0.id == state.id }
                    }
                } catch {
                    await MainActor.run {
                        self.activeIntegrationStates.removeAll { $0.id == state.id }
                        self.alertMessage = AlertMessage(
                            title: NSLocalizedString("Download Failed", comment: "Download failed alert title"),
                            message: error.localizedDescription
                        )
                    }
                }
            }
        }
    }

    func cancelPendingBookIntegration(state: BundleArchiveDownloadProgressState) {
        if case .bulk = state.pendingData {
            libraryViewModel.exitSelectionMode()
        }
        activeIntegrationStates.removeAll { $0.id == state.id }
    }

    private func openBookAsync(_ book: BooksData, initialContentId: Int?, searchText: String? = nil, targetAnnotation: Annotation? = nil) async {
        if AppConfig.isUsingBundleMode,
           !BookArchiveIntegrator.shared.isBookIntegrated(book)
        {
            showBookIntegrationConfirmation(for: book, initialContentId: initialContentId)
            return
        }

        presentReader(book, initialContentId: initialContentId, searchText: searchText, targetAnnotation: targetAnnotation)

        await Task.yield()

        HistoryViewModel.shared.addBookToHistory(book.id)
        if let initialContentId = initialContentId {
            HistoryViewModel.shared.updateLastContentId(initialContentId, for: book.id)
        }
    }

    func showBookIntegrationConfirmation(
        for book: BooksData,
        initialContentId: Int?
    ) {
        // Prevent duplicate confirmation for the same book
        if activeIntegrationStates.contains(where: {
            if case .single(let b, _) = $0.pendingData { return b.id == book.id }
            return false
        }) {
            return
        }

        let bodyFormat = String(localized: "Confirm Download Message")
        let message = String(
            format: bodyFormat,
            locale: Locale.current,
            book.book
        )

        var sizeString = ""
        if let size = book.compressedDownloadSize, size > 0 {
            sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        let state = BundleArchiveDownloadProgressState(
            title: book.book,
            message: message,
            mode: .confirmation,
            totalSizeString: sizeString
        )
        state.pendingData = .single(book: book, contentId: initialContentId)
        activeIntegrationStates.append(state)
    }

    func showBulkDownloadConfirmation(books: [BooksData]) {
        // Prevent multiple bulk confirmations
        if activeIntegrationStates.contains(where: {
            if case .bulk = $0.pendingData { return true }
            return false
        }) {
            return
        }

        let totalSize = books.reduce(0 as Int64) { $0 + ($1.compressedDownloadSize ?? 0) }
        var sizeString = ""
        if totalSize > 0 {
            sizeString = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        }

        let message = String(
            format: String(
                localized: .bulkBookDownloadAlert(
                    totalBook: books.count
                )
            )
        )

        let state = BundleArchiveDownloadProgressState(
            title: String(localized: "Download Book"),
            message: message,
            mode: .confirmation,
            totalSizeString: sizeString
        )
        state.pendingData = .bulk(books: books)
        activeIntegrationStates.append(state)
    }

    private func showIntegratingState(for state: BundleArchiveDownloadProgressState) {
        state.mode = .integrating
        state.title = NSLocalizedString(
            "Integrating Book",
            comment: "Book integrate phase title"
        )
        state.message = NSLocalizedString(
            "Copying tables and rebuilding FTS index...",
            comment: "Book integrate phase message"
        )
        state.detail = NSLocalizedString(
            "Please wait, this process cannot be cancelled.",
            comment: "Book integrate phase detail"
        )
        state.progress = 0
    }

    private func presentReader(_ book: BooksData, initialContentId: Int?, searchText: String? = nil, targetAnnotation: Annotation? = nil) {
        switchToMode(.viewer)
        clearPendingBookIntegration()

        if let activeId = activeTabId, let currentTab = openTabs.first(where: { $0.id == activeId }) {
            currentTab.viewModel.saveCurrentState()
        }

        if let existingTabIndex = openTabs.firstIndex(where: { $0.book.id == book.id }) {
            activeTabId = openTabs[existingTabIndex].id
            // Update initialContentId if provided, so the reader can jump to it
            if let contentId = initialContentId {
                var updatedTab = openTabs[existingTabIndex]
                updatedTab.initialContentId = contentId
                updatedTab.viewModel.searchText = searchText ?? ""
                updatedTab.viewModel.targetAnnotation = targetAnnotation
                updatedTab.viewModel.fetchContentById(contentId)
                openTabs[existingTabIndex] = updatedTab
            } else {
                let updatedTab = openTabs[existingTabIndex]
                updatedTab.viewModel.searchText = searchText ?? ""
                updatedTab.viewModel.targetAnnotation = targetAnnotation
                openTabs[existingTabIndex] = updatedTab
            }
        } else {
            let viewModel = ReaderViewModel(book: book)
            viewModel.searchText = searchText ?? ""
            viewModel.targetAnnotation = targetAnnotation
            viewModel.loadInitialContent(initialContentId: initialContentId)
            let newTab = ReaderTab(id: UUID(), book: book, initialContentId: initialContentId, viewModel: viewModel)
            openTabs.append(newTab)
            activeTabId = newTab.id
        }

        selectedContentId = initialContentId
        selectedBook = book
    }

    private func clearPendingBookIntegration() {
        activeIntegrationStates.removeAll { $0.mode == .confirmation }
    }
}
