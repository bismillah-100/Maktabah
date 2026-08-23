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

    private var observerTokens: [NotificationToken] = []

    init() {
        setupObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupObservers() {
        observerTokens.append(
            NotificationToken(
                token: NotificationCenter.default.addObserver(
                    forName: .bookIntegrated,
                    object: nil,
                    queue: .main
                ) { notification in
                    guard let bookId = notification.object as? Int else {
                        return
                    }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.handleBookIntegrationChanged(bookId: bookId)
                    }
                }
            )
        )

        observerTokens.append(
            NotificationToken(
                token: NotificationCenter.default.addObserver(
                    forName: .libraryFolderChanged,
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor [weak self] in
                        self?.clearAllTabs()
                    }
                }
            )
        )

        observerTokens.append(
            NotificationToken(
                token: NotificationCenter.default.addObserver(
                    forName: .bookIdMigrated,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let userInfo = notification.userInfo,
                        let oldId = userInfo["oldId"] as? Int,
                        let newId = userInfo["newId"] as? Int
                    else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        handleBookIdMigrated(oldId: oldId, newId: newId)
                    }
                }
            )
        )
    }

    private func handleBookIdMigrated(oldId: Int, newId: Int) {
        let ldm = LibraryDataManager.shared
        guard let newBookData = ldm.booksById[newId] else { return }

        for i in 0 ..< openTabs.count {
            if openTabs[i].book.id == oldId {
                let oldTab = openTabs[i]
                openTabs[i] = ReaderTab(
                    id: oldTab.id,
                    book: newBookData,
                    initialContentId: oldTab.initialContentId,
                    viewModel: oldTab.viewModel
                )
                openTabs[i].viewModel.currentBook = newBookData
            }
        }

        if selectedBook?.id == oldId {
            selectedBook = newBookData
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

    func openBook(_ book: BooksData, initialContentId: Int? = nil, searchText: String? = nil, searchMode: SearchMode? = nil, nearDistance: Int = 10, targetAnnotation: Annotation? = nil, recordHistory: Bool = true) {
        Task {
            await openBookAsync(book, initialContentId: initialContentId, searchText: searchText, searchMode: searchMode, nearDistance: nearDistance, targetAnnotation: targetAnnotation, recordHistory: recordHistory)
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

        case let .single(book, initialContentId):
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
                        if !MaktabahApp.isIpad, self.selectedBook != nil {
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

    private func openBookAsync(_ book: BooksData, initialContentId: Int?, searchText: String? = nil, searchMode: SearchMode? = nil, nearDistance: Int = 10, targetAnnotation: Annotation? = nil, recordHistory: Bool = true) async {
        if AppConfig.isUsingBundleMode,
           !BookArchiveIntegrator.shared.isBookIntegrated(book)
        {
            showBookIntegrationConfirmation(for: book, initialContentId: initialContentId)
            return
        }

        presentReader(book, initialContentId: initialContentId, searchText: searchText, searchMode: searchMode, nearDistance: nearDistance, targetAnnotation: targetAnnotation, recordHistory: recordHistory)

        await Task.yield()

        if recordHistory {
            HistoryViewModel.shared.addBookToHistory(book.id)
            if let initialContentId {
                HistoryViewModel.shared.updateLastContentId(initialContentId, for: book.id)
            }
        }
    }

    func showBookIntegrationConfirmation(
        for book: BooksData,
        initialContentId: Int?
    ) {
        // Prevent duplicate confirmation for the same book
        if activeIntegrationStates.contains(where: {
            if case let .single(b, _) = $0.pendingData { return b.id == book.id }
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

    private func presentReader(_ book: BooksData, initialContentId: Int?, searchText: String? = nil, searchMode: SearchMode? = nil, nearDistance: Int = 10, targetAnnotation: Annotation? = nil, recordHistory: Bool = true) {
        switchToMode(.viewer)
        clearPendingBookIntegration()

        if let activeId = activeTabId, let currentTab = openTabs.first(where: { $0.id == activeId }) {
            currentTab.viewModel.saveCurrentState()
        }

        if let existingTabIndex = openTabs.firstIndex(where: { $0.book.id == book.id }) {
            activeTabId = openTabs[existingTabIndex].id
            // Update initialContentId if provided, so the reader can jump to it
            let updatedTab = openTabs[existingTabIndex]
            updatedTab.viewModel.recordHistory = updatedTab.viewModel.recordHistory || recordHistory
            if let contentId = initialContentId {
                let isSameContent = updatedTab.viewModel.currentContentId == contentId
                let hasNewSearch = (searchText != nil && !searchText!.isEmpty)
                let hasNewTarget = (targetAnnotation != nil)

                if !isSameContent || hasNewSearch || hasNewTarget {
                    updatedTab.viewModel.searchText = searchText ?? ""
                    updatedTab.viewModel.searchMode = searchMode
                    updatedTab.viewModel.nearDistance = nearDistance
                    updatedTab.viewModel.targetAnnotation = targetAnnotation
                    updatedTab.viewModel.fetchContentById(contentId)
                }

                openTabs[existingTabIndex] = updatedTab
            } else {
                updatedTab.viewModel.searchText = searchText ?? ""
                updatedTab.viewModel.searchMode = searchMode
                updatedTab.viewModel.nearDistance = nearDistance
                updatedTab.viewModel.targetAnnotation = targetAnnotation
                openTabs[existingTabIndex] = updatedTab
            }
        } else {
            let viewModel = ReaderViewModel(book: book)
            viewModel.recordHistory = recordHistory
            viewModel.searchText = searchText ?? ""
            viewModel.searchMode = searchMode
            viewModel.nearDistance = nearDistance
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
