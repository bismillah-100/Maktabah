//
//  LibraryViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//

import Combine
import Foundation
import Observation

@Observable
final class LibraryViewModel: ViewModelBase {
    // MARK: - Shared

    let dataManager: LibraryDataManager = .shared
    private let historyManager: HistoryViewModel = .shared

    // MARK: - State Properties

    var displayedCategories: [CategoryData] = []
    var filterMode: LibraryFilterMode = .all
    var isFlatMode: Bool = false
    var selectedBookName: String?
    var rootCategories: [CategoryData] = []
    var selectedBookIds: Set<Int> = []
    var isSelectionMode = false
    var isBulkDownloading = false
    var isDownloadModal = false
    var singleBookToDelete: BooksData?
    var reloadTask: Task<Void, Never>?
    var availableUpdateCount: Int = 0
    private var historySelectionTask: Task<Void, Never>?

    var onStateChanged: ((ViewModelState) -> Void)?
    var state: ViewModelState = .loading {
        didSet {
            onStateChanged?(state)
        }
    }

    var showOnlyDownloaded: Bool = UserDefaults.standard.integer(forKey: "filterSegmentIndex") == 1 {
        didSet {
            #if os(iOS)
            UserDefaults.standard.set(showOnlyDownloaded ? 1 : 0, forKey: "filterSegmentIndex")
            #endif
            resetAuthorPagination()
            updateDisplayedCategories()
        }
    }

    var searchQuery: String = "" {
        didSet {
            searchTask?.cancel()
            searchTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.performSearch(self?.searchQuery ?? "")
            }
        }
    }

    private var searchTask: Task<Void, Never>?

    var viewMode: LibraryViewMode = .init(
        rawValue: UserDefaults.standard.integer(forKey: "libraryViewMode")
    ) ?? .category {
        didSet {
            #if os(iOS)
            UserDefaults.standard.set(viewMode.rawValue, forKey: "libraryViewMode")
            #endif
            if viewMode == .author, !_hasBuiltAuthorHierarchy {
                _authorHierarchy = dataManager.buildAuthorHierarchy()
                _hasBuiltAuthorHierarchy = true
            }
            resetAuthorPagination()
            updateDisplayedCategories()
        }
    }

    var showingDeleteConfirmation = false
    var showingImportSheet = false
    var showingUpdateSheet = false
    var importErrorMessage: String?
    var showImportSuccessAlert = false

    #if os(macOS)
    let updateSubject = PassthroughSubject<LibraryUpdate, Never>()
    #endif

    // MARK: - Internal Trackers & Subscriptions

    var updateTrigger: Int = 0

    var selectedAuthorId: Int? {
        didSet {
            resetAuthorPagination()
            updateDisplayedCategories()
        }
    }

    var baseCategories: [CategoryData] = []
    var bookLookup: [String: (category: CategoryData, book: BooksData)] = [:]
    private let lookupQueue = SerialTaskQueue()

    private var hasLoadedLibrary = false
    private var _cachedDisplayedCategories: [CategoryData] = []
    private var _authorHierarchy: [CategoryData] = []
    private var _hasBuiltAuthorHierarchy = false
    private let authorPageSize = 100
    private var _displayedAuthorCount: Int = 0
    private var _allFilteredAuthors: [CategoryData] = []
    private var _displayedFilteredCount: Int = 0

    private let refreshSubject = PassthroughSubject<Void, Never>()
    private var bulkDownloadTask: Task<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()
        setupObservers()
    }

    // MARK: - Shared Helpers

    func isBookDownloaded(_ book: BooksData) -> Bool {
        BookArchiveIntegrator.shared.isBookIntegrated(book)
    }

    // MARK: - Data Preparation (Unified)

    func prepareData() {
        // Digunakan oleh macOS saat data pertama kali dimuat
        rootCategories = dataManager.allRootCategories
        setBaseCategories(rootCategories, reload: false)
    }

    func loadLibrary() async {
        if hasLoadedLibrary { return }
        await load()
    }

    func refreshLibrary() async {
        state = .loading
        hasLoadedLibrary = false
        dataManager.resetState()
        await dataManager.reloadAllData()
        await load()
    }

    private func load() async {
        state = .loading
        await dataManager.loadData()
        rootCategories = dataManager.allRootCategories
        if viewMode == .author {
            _authorHierarchy = dataManager.buildAuthorHierarchy()
            _hasBuiltAuthorHierarchy = true
        }

        /* Revert jules commit cause `OptionSearchVC` load
         all books without filter only downloaded books.
         */
        setBaseCategories(rootCategories, reload: false)
        resetAuthorPagination()
        updateDisplayedCategories()
        state = .loaded
        hasLoadedLibrary = dataManager.isDataLoaded
    }

    // MARK: - Filtering (Unified)

    func applyFilter(_ mode: LibraryFilterMode) {
        filterMode = mode
        var filtered: [CategoryData] = []

        switch mode {
        case .all:
            showOnlyDownloaded = false
            isFlatMode = false
            filtered = dataManager.allRootCategories

        case .downloaded:
            showOnlyDownloaded = true
            isFlatMode = false
            filtered = dataManager.filterIntegrated()

        case .favorites:
            showOnlyDownloaded = false
            isFlatMode = true
            let favBooks = historyManager.favoriteBooks
            let cat = CategoryData(id: -1, name: String(localized: "Favorites"), level: 1, order: 0)
            cat.children = favBooks
            filtered = favBooks.isEmpty ? [] : [cat]

        case .history:
            showOnlyDownloaded = false
            isFlatMode = true
            let histBooks = historyManager.historyBooks
            let cat = CategoryData(id: -2, name: String(localized: "History"), level: 1, order: 0)
            cat.children = histBooks
            filtered = histBooks.isEmpty ? [] : [cat]
        }

        setBaseCategories(filtered, reload: true)
        resetAuthorPagination()
        updateDisplayedCategories()
    }

    func applyDownloadFilter(forSegmentIndex index: Int) {
        guard let mode = LibraryFilterMode(rawValue: index) else { return }
        applyFilter(mode)
    }

    func setBaseCategories(_ categories: [CategoryData], reload: Bool) {
        baseCategories = categories
        buildBookLookup()
    }

    func performSearch(_ query: String) {
        searchQuery = query
        resetAuthorPagination()
        updateDisplayedCategories()
    }

    func updateDisplayedCategories() {
        var base = resolveBaseCategories()

        if showOnlyDownloaded, !isFlatMode {
            base = dataManager.filterIntegrated(base: base)
        }

        applySearchFilter(base: base)
        finalizeDisplayedCategories()

        #if os(iOS)
        updateTrigger += 1
        #else
        updateSubject.send(.reloadData)
        if !searchQuery.isEmpty {
            updateSubject.send(.expandItem(nil))
        }
        #endif
    }

    private func resolveBaseCategories() -> [CategoryData] {
        if isFlatMode {
            return baseCategories
        }
        if viewMode == .author {
            if !_hasBuiltAuthorHierarchy {
                _authorHierarchy = dataManager.buildAuthorHierarchy()
                _hasBuiltAuthorHierarchy = true
            }
            return _authorHierarchy
        }
        return baseCategories
    }

    private func applySearchFilter(base: [CategoryData]) {
        if searchQuery.isEmpty {
            _cachedDisplayedCategories = showOnlyDownloaded ? base : (isFlatMode ? baseCategories : base)
        } else {
            if viewMode == .author, !isFlatMode {
                _allFilteredAuthors = dataManager.filterAuthorHierarchy(base, searchText: searchQuery)
                _cachedDisplayedCategories = []
            } else {
                var filtered: [CategoryData] = []
                _ = dataManager.filterContent(
                    with: searchQuery,
                    displayedCategories: &filtered,
                    baseCategories: base
                )
                _cachedDisplayedCategories = filtered
            }
        }
    }

    private func finalizeDisplayedCategories() {
        if viewMode == .author, !isFlatMode {
            if !searchQuery.isEmpty {
                displayedCategories = Array(_allFilteredAuthors.prefix(_displayedFilteredCount))
            } else if showOnlyDownloaded {
                displayedCategories = Array(_cachedDisplayedCategories.prefix(_displayedAuthorCount))
            } else {
                displayedCategories = Array(_authorHierarchy.prefix(_displayedAuthorCount))
            }
        } else {
            displayedCategories = _cachedDisplayedCategories
        }
    }

    // MARK: - Migration Support

    override func migrateBookId(from oldId: Int, to newId: Int) {
        if selectedBookIds.contains(oldId) {
            selectedBookIds.remove(oldId)
            selectedBookIds.insert(newId)
        }
        if singleBookToDelete?.id == oldId {
            singleBookToDelete = dataManager.getBook([newId]).first
        }

        // Reload all data references from the database manager (which was already reloaded in LibraryDataManager)
        rootCategories = dataManager.allRootCategories
        _hasBuiltAuthorHierarchy = false
        if viewMode == .author {
            _authorHierarchy = dataManager.buildAuthorHierarchy()
            _hasBuiltAuthorHierarchy = true
        }

        // Apply the filter to rebuild baseCategories, displayedCategories, and bookLookup
        applyFilter(filterMode)
    }

    // MARK: - Authors Pagination (Unified)

    var hasMoreAuthors: Bool {
        let total = showOnlyDownloaded
            ? _cachedDisplayedCategories.count
            : (searchQuery.isEmpty ? _authorHierarchy.count : _allFilteredAuthors.count)
        let displayed = searchQuery.isEmpty ? _displayedAuthorCount : _displayedFilteredCount
        return viewMode == .author && displayed < total
    }

    var totalAuthorCount: Int {
        searchQuery.isEmpty
            ? (showOnlyDownloaded ? _cachedDisplayedCategories.count : _authorHierarchy.count)
            : _allFilteredAuthors.count
    }

    private func resetAuthorPagination() {
        _displayedAuthorCount = authorPageSize
        _displayedFilteredCount = authorPageSize
    }

    func loadMoreAuthors() {
        let total = showOnlyDownloaded
            ? _cachedDisplayedCategories.count
            : (searchQuery.isEmpty ? _authorHierarchy.count : _allFilteredAuthors.count)
        if searchQuery.isEmpty {
            _displayedAuthorCount = min(_displayedAuthorCount + authorPageSize, total)
        } else {
            _displayedFilteredCount = min(_displayedFilteredCount + authorPageSize, _allFilteredAuthors.count)
        }
        updateDisplayedCategories()
    }

    // MARK: - Selection & Interaction (Unified)

    func restoreSelectionEntry(byBookName bookName: String) -> (category: CategoryData, book: BooksData)? {
        bookLookup[bookName]
    }

    func handleBookSelection(book: BooksData) {
        if selectedBookName == book.book { return }
        selectedBookName = book.book

        historySelectionTask?.cancel()
        historySelectionTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.historyManager.addBookToHistory(book.id)
            }
        }
    }

    var selectedDownloadBooks: [BooksData] {
        booksForSelectedIds(in: displayedCategories).filter { !isBookDownloaded($0) }
    }

    var selectedDownloadCount: Int {
        selectedDownloadBooks.count
    }

    func enterSelectionMode(selecting book: BooksData? = nil) {
        isSelectionMode = true
        if let book { toggleBookSelection(book) }
    }

    func exitSelectionMode() {
        isSelectionMode = false
        selectedBookIds.removeAll()
    }

    func isBookSelected(_ book: BooksData) -> Bool {
        selectedBookIds.contains(book.id)
    }

    func toggleBookSelection(_ book: BooksData) {
        if selectedBookIds.contains(book.id) { selectedBookIds.remove(book.id) }
        else { selectedBookIds.insert(book.id) }
    }

    func isCategorySelected(_ category: CategoryData) -> Bool {
        let books = getAllBooks(in: category)
        return !books.isEmpty && books.allSatisfy { selectedBookIds.contains($0.id) }
    }

    func isCategoryPartiallySelected(_ category: CategoryData) -> Bool {
        let books = getAllBooks(in: category)
        guard !books.isEmpty else { return false }
        return books.contains { selectedBookIds.contains($0.id) } && books.contains { !selectedBookIds.contains($0.id) }
    }

    func toggleCategorySelection(_ category: CategoryData) {
        let books = getAllBooks(in: category)
        guard !books.isEmpty else { return }
        var currentSelection = selectedBookIds
        if books.allSatisfy({ currentSelection.contains($0.id) }) {
            books.forEach { currentSelection.remove($0.id) }
        } else {
            books.forEach { currentSelection.insert($0.id) }
        }
        selectedBookIds = currentSelection
    }

    func selectAllBook(state: Bool) {
        if state {
            var newSelection = selectedBookIds
            for category in displayedCategories {
                let books = getAllBooks(in: category)
                books.forEach { newSelection.insert($0.id) }
            }
            selectedBookIds = newSelection
        } else {
            selectedBookIds.removeAll()
        }
    }

    func getAllBooks(in category: CategoryData) -> [BooksData] {
        category.allBooks
    }

    var selectedDeleteBooks: [BooksData] {
        booksForSelectedIds(in: displayedCategories).filter { isBookDownloaded($0) }
    }

    var selectedDeleteCount: Int {
        selectedDeleteBooks.count
    }

    func startBulkDeletion(onFinished: @escaping () -> Void) {
        let books = selectedDeleteBooks
        guard !books.isEmpty else { return }
        Task { [weak self] in
            for book in books {
                try? await BookArchiveIntegrator.shared.removeBookFromArchive(book)
            }
            self?.exitSelectionMode()
            onFinished()
        }
    }

    #if os(iOS)
    @MainActor
    func selectBook(_ book: BooksData, using navigationManager: iOSNavigationManager) {
        let lastId = historyManager.entriesByBookId[book.id]?.lastContentId
        navigationManager.openBook(book, initialContentId: lastId)
    }

    func notifySelectionChanged() {
        selectedBookIds = selectedBookIds
    }
    #endif

    func deleteSingleBook(_ book: BooksData) async {
        try? await BookArchiveIntegrator.shared.removeBookFromArchive(book)
    }

    func importOfflineBook(from url: URL, metadata: BookMetadata, authorRow: [String: Any]?) async {
        let updateManager = BookUpdateManager.shared
        do {
            let result = try await updateManager.importOfflineUpdate(
                from: url,
                providedMetadata: metadata,
                authorRow: authorRow
            )
            try await dataManager.processBookUpdates([result])
            await updateManager.integrateBooks(metadata: metadata)
            await MainActor.run {
                showImportSuccessAlert = true
                showingImportSheet = false
            }
        } catch {
            await MainActor.run {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Bulk Download (Unified)

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
            if case .success = downloadResults[$0.id] { return true }
            return false
        }

        let completedIntegrations = await performBulkIntegrationPhase(
            successfulDownloads: successfulDownloads,
            downloadResults: &downloadResults,
            progressState: progressState
        )

        let failedCount = books.filter {
            if case .failure = downloadResults[$0.id] { return true }
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
                if Task.isCancelled { group.cancelAll(); break }
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

    // MARK: - Observers

    private func setupObservers() {
        setupDebouncedStreams()
        observeBookIntegrated()
        observeBooksChanged()
        enableBookIdMigrationObserver()
        observeLibraryFolderChanged()
    }

    private func setupDebouncedStreams() {
        refreshSubject
            .debounce(for: .seconds(0.3), scheduler: RunLoop.current)
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    rootCategories = Array(dataManager.allRootCategories)
                    if viewMode == .author {
                        _authorHierarchy = dataManager.buildAuthorHierarchy()
                        _hasBuiltAuthorHierarchy = true
                    }
                    applyFilter(filterMode)
                }
            }
            .store(in: &cancellables)
    }

    private func observeBookIntegrated() {
        addObserver(forName: .bookIntegrated, object: nil, queue: .current) { [weak self] _ in
            Task { @MainActor [weak self] in
                #if os(iOS)
                self?.refreshSubject.send(())
                #endif
            }
        }
    }

    private func observeBooksChanged() {
        addObserver(forName: .booksChanged, object: nil, queue: .current) { [weak self] notification in
            Task { @MainActor [weak self] in
                #if os(iOS)
                self?.refreshSubject.send(())
                #endif
                self?.checkBookUpdatesPeriodically(force: true)
            }
        }
    }

    private func observeLibraryFolderChanged() {
        addObserver(forName: .libraryFolderChanged, object: nil, queue: .current) { [weak self] _ in
            guard let self, reloadTask == nil else { return }
            reloadTask?.cancel()
            reloadTask = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                await refreshLibrary()
                reloadTask = nil
            }
        }
    }

    // MARK: - General Helpers

    private func buildBookLookup() {
        lookupQueue.cancelAll()
        lookupQueue.enqueue { [weak self] in
            guard let self else { return }
            var newLookup: [String: (category: CategoryData, book: BooksData)] = [:]

            func traverse(_ category: CategoryData) {
                for child in category.children {
                    if let book = child as? BooksData { newLookup[book.book] = (category, book) }
                    else if let sub = child as? CategoryData { traverse(sub) }
                }
            }

            for category in displayedCategories {
                traverse(category)
            }

            bookLookup = newLookup
        }
    }

    private func booksForSelectedIds(in categories: [CategoryData]) -> [BooksData] {
        categories.flatMap { getAllBooks(in: $0).filter { selectedBookIds.contains($0.id) } }
    }

    func isNetworkFailure(_ error: Error) -> Bool {
        if let bookError = error as? BookDownloadError, case .networkUnavailable = bookError { return true }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut:
                return true
            default: return false
            }
        }
        return false
    }

    // MARK: - Periodic Book Update Check

    @MainActor
    func checkBookUpdatesPeriodically(force: Bool = false) {
        dataManager.checkBookUpdatesPeriodically(
            force: force
        ) { [weak self] count in
            self?.availableUpdateCount = count
        }
    }
}

// MARK: - ENUM

enum LibraryFilterMode: Int {
    case all
    case favorites
    case history
    case downloaded
}

#if os(macOS)
enum LibraryUpdate {
    case reloadData
    case reloadItem(Any?, reloadChildren: Bool)
    case expandItem(Any?)
    case scrollRowToVisible(Any)
    case beginUpdates
    case endUpdates
    case removeItems(IndexSet, parent: Any?)
    case insertItems(IndexSet, parent: Any?)
    case moveItem(from: Int, to: Int, parent: Any?)
}
#endif
