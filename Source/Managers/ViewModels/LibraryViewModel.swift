//
//  LibraryViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//

import Combine
import Foundation

#if os(macOS)
extension LibraryViewModel: ObservableObject {}
#endif

#if os(iOS)
@Observable
#endif
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

    #if os(macOS)
    @Published var searchQuery: String = ""
    @Published var state: ViewModelState = .loading
    @Published var showingImportSheet = false
    @Published var importErrorMessage: String?
    @Published var showImportSuccessAlert = false
    var showOnlyDownloaded: Bool = false
    var viewMode: LibraryViewMode = .category
    let updateSubject = PassthroughSubject<LibraryUpdate, Never>()
    #else
    var state: ViewModelState = .loading
    var showOnlyDownloaded: Bool {
        get {
            _ = _showOnlyDownloadedTracker
            return UserDefaults.standard.integer(forKey: "filterSegmentIndex") == 1
        }
        set {
            UserDefaults.standard.set(newValue ? 1 : 0, forKey: "filterSegmentIndex")
            _showOnlyDownloadedTracker = newValue
            resetAuthorPagination()
            updateDisplayedCategories()
        }
    }

    var _showOnlyDownloadedTracker: Bool = false
    var searchQuery: String = "" {
        didSet {
            if oldValue != searchQuery {
                searchSubject.send(searchQuery)
            }
        }
    }

    var showingDeleteConfirmation = false
    var showingImportSheet = false
    var showingUpdateSheet = false
    var importErrorMessage: String?
    var showImportSuccessAlert = false

    var viewMode: LibraryViewMode {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "libraryViewMode")
            if viewMode == .author, !_hasBuiltAuthorHierarchy {
                _authorHierarchy = dataManager.buildAuthorHierarchy()
                _hasBuiltAuthorHierarchy = true
            }
            resetAuthorPagination()
            updateDisplayedCategories()
        }
    }
    #endif

    // MARK: - Internal Trackers & Subscriptions

    #if os(iOS)
    var updateTrigger: Int = 0
    #endif

    var selectedAuthorId: Int? {
        didSet {
            #if os(iOS)
            #endif
            resetAuthorPagination()
            updateDisplayedCategories()
        }
    }

    private var baseCategories: [CategoryData] = []
    private var bookLookup: [String: (category: CategoryData, book: BooksData)] = [:]
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
    let searchSubject = PassthroughSubject<String, Never>()
    private var bulkDownloadTask: Task<Void, Never>?

    // MARK: - Init

    override init() {
        #if os(iOS)
        viewMode = LibraryViewMode(
            rawValue: UserDefaults.standard.integer(forKey: "libraryViewMode")
        ) ?? .category
        #endif
        super.init()

        #if os(macOS)
        setupMacOSBindings()
        #endif
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
        var base: [CategoryData]
        if isFlatMode {
            base = baseCategories
        } else {
            if viewMode == .author {
                if !_hasBuiltAuthorHierarchy {
                    _authorHierarchy = dataManager.buildAuthorHierarchy()
                    _hasBuiltAuthorHierarchy = true
                }
                base = _authorHierarchy
            } else {
                base = baseCategories
            }
        }

        if showOnlyDownloaded, !isFlatMode {
            base = dataManager.filterIntegrated(base: base)
        }

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

        // Finalize displayedCategories
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

        #if os(iOS)
        updateTrigger += 1
        #else
        updateSubject.send(.reloadData)
        if !searchQuery.isEmpty {
            updateSubject.send(.expandItem(nil))
        }
        #endif
    }

    // MARK: - Migration Support

    func migrateBookId(from oldId: Int, to newId: Int) {
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
        var books: [BooksData] = []
        _getAllBooks(in: category, books: &books)
        return books
    }

    private func _getAllBooks(in category: CategoryData, books: inout [BooksData]) {
        for child in category.children {
            if let book = child as? BooksData {
                books.append(book)
            } else if let sub = child as? CategoryData {
                _getAllBooks(in: sub, books: &books)
            }
        }
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
        let total = books.count
        var downloadedCount = 0
        var completedIntegrations = 0
        var downloadResults: [Int: Result<URL, Error>] = [:]
        var stoppedByNetwork = false

        if await !NetworkMonitor.shared.isConnected {
            stoppedByNetwork = true
        } else {
            await withTaskGroup(of: (Int, Result<URL, Error>).self) { group in
                for book in books {
                    guard !Task.isCancelled else { break }
                    group.addTask {
                        do {
                            let url = try await BookDownloadManager.shared.ensureBookDownloaded(bookId: book.id)
                            return (book.id, .success(url))
                        } catch {
                            return (book.id, .failure(error))
                        }
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
        }

        let successfulDownloads = books.filter { if case .success = downloadResults[$0.id] { return true }; return false }
        let integrateTotal = successfulDownloads.count
        progressState.mode = .integrating
        progressState.message = String(localized: "Download Complete. Begin integrating...")
        progressState.detail = "0 / \(integrateTotal)"
        progressState.progress = 0

        for book in successfulDownloads {
            guard !Task.isCancelled else { break }
            if !BookArchiveIntegrator.shared.isBookIntegrated(book) {
                do {
                    try await BookArchiveIntegrator.shared.ensureBookIntegrated(
                        book, onIntegrating: {},
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

        let failedCount = books.filter { if case .failure = downloadResults[$0.id] { return true }; return false }.count
        selectedBookIds.subtract(books.map(\.id))
        isBulkDownloading = false
        bulkDownloadTask = nil

        let message: String? = if Task.isCancelled {
            String(localized: "Stopped. \(completedIntegrations) books completed.", comment: "")
        } else if stoppedByNetwork {
            NSLocalizedString("Please check your internet connection", comment: "")
        } else if failedCount > 0 {
            String(localized: "\(completedIntegrations) completed, \(failedCount) failed.", comment: "")
        } else {
            String(localized: "All \(completedIntegrations) books processed successfully.", comment: "")
        }
        onFinished(message)
    }

    // MARK: - Observers

    private func setupObservers() {
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

        searchSubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.searchQuery = query
                self?.resetAuthorPagination()
                self?.updateDisplayedCategories()
            }
            .store(in: &cancellables)

        addObserver(
            forName: .bookIntegrated, object: nil, queue: .current
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                #if os(macOS)
                if let bookId = notification.object as? Int {
                    reloadParentCategory(ofBookId: bookId)
                }
                #else
                refreshSubject.send(())
                #endif
            }
        }

        addObserver(
            forName: .booksChanged, object: nil, queue: .current
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                #if os(macOS)
                handleBooksChanged(notification)
                #else
                refreshSubject.send(())
                #endif
                checkBookUpdatesPeriodically(force: true)
            }
        }

        addObserver(
            forName: .bookIdMigrated, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let userInfo = notification.userInfo,
                      let oldId = userInfo["oldId"] as? Int,
                      let newId = userInfo["newId"] as? Int else { return }
                migrateBookId(from: oldId, to: newId)
            }
        }

        addObserver(
            forName: .libraryFolderChanged, object: nil, queue: .current
        ) { [weak self] _ in
            guard let self, reloadTask == nil else { return }
            reloadTask?.cancel()
            reloadTask = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                await refreshLibrary()
                reloadTask = nil
            }
        }
    }

    // MARK: macOS Implementation
    #if os(macOS)
    private func setupMacOSBindings() {
        $searchQuery
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] newQuery in
                self?.performSearch(newQuery)
            }
            .store(in: &cancellables)

        historyManager.$historyBooks
            .receive(on: RunLoop.main)
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] newBooks in self?.updateFlatListFromHistory(newBooks) }
            .store(in: &cancellables)

        historyManager.$favoriteBooks
            .receive(on: RunLoop.main)
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] newBooks in self?.updateFlatListFromFavorites(newBooks) }
            .store(in: &cancellables)
    }

    private func updateFlatListFromHistory(_ newBooks: [BooksData]) {
        guard isFlatMode, filterMode == .history else { return }
        updateFlatListIncrementally(newBooks: newBooks, fallbackCategoryId: -2, fallbackCategoryName: String(localized: "History"))
    }

    private func updateFlatListFromFavorites(_ newBooks: [BooksData]) {
        guard isFlatMode, filterMode == .favorites else { return }
        updateFlatListIncrementally(newBooks: newBooks, fallbackCategoryId: -1, fallbackCategoryName: String(localized: "Favorites"))
    }

    private func updateFlatListIncrementally(newBooks: [BooksData], fallbackCategoryId: Int, fallbackCategoryName: String) {
        guard let firstCat = displayedCategories.first else {
            displayedCategories = newBooks.isEmpty ? [] : [{
                let cat = CategoryData(id: fallbackCategoryId, name: fallbackCategoryName, level: 1, order: 0)
                cat.children = newBooks
                return cat
            }()]
            updateSubject.send(.reloadData)
            return
        }

        let oldBooks = firstCat.children.compactMap { $0 as? BooksData }

        let oldIds = oldBooks.map(\.id)
        let newIds = newBooks.map(\.id)

        if oldIds == newIds { return } // Tidak ada perubahan urutan atau penambahan/pengurangan

        var currentBooks = oldBooks
        updateSubject.send(.beginUpdates)

        // Hapus item lama yang sudah tidak ada
        let newIdSet = Set(newIds)
        for (index, oldBook) in currentBooks.enumerated().reversed() {
            if !newIdSet.contains(oldBook.id) {
                updateSubject.send(.removeItems(IndexSet(integer: index), parent: nil))
                currentBooks.remove(at: index)
            }
        }

        firstCat.children = currentBooks

        for (newIndex, newBook) in newBooks.enumerated() {
            if let oldIndex = currentBooks.firstIndex(where: { $0.id == newBook.id }) {
                if oldIndex != newIndex {
                    updateSubject.send(.moveItem(from: oldIndex, to: newIndex, parent: nil))
                    let movedBook = currentBooks.remove(at: oldIndex)
                    currentBooks.insert(movedBook, at: newIndex)
                    firstCat.children = currentBooks
                }
            } else {
                currentBooks.insert(newBook, at: newIndex)
                firstCat.children = currentBooks
                updateSubject.send(.insertItems(IndexSet(integer: newIndex), parent: nil))
            }
        }
        updateSubject.send(.endUpdates)
    }

    private func handleBooksChanged(_ notification: Notification) {
        guard let payload = notification.object as? BooksChangedNotification else { return }
        for (categoryId, book) in payload.insertedBooks {
            if let category = findCategoryInDisplayed(categoryId) {
                bookLookup[book.book] = (category, book)

                if searchQuery.isEmpty {
                    updateSubject.send(.expandItem(category))
                    updateSubject.send(.reloadItem(category, reloadChildren: true))
                    updateSubject.send(.scrollRowToVisible(book))
                } else {
                    let currentQuery = searchQuery
                    let base = baseCategories.isEmpty ? displayedCategories : baseCategories
                    var filtered: [CategoryData] = []
                    _ = dataManager.filterContent(
                        with: currentQuery,
                        displayedCategories: &filtered,
                        baseCategories: base
                    )
                    displayedCategories = filtered
                    updateSubject.send(.reloadData)
                }
            }
        }
        if !payload.updatedBookIds.isEmpty {
            reloadUpdatedBooks(payload.updatedBookIds)
        }
    }

    private func reloadUpdatedBooks(_ bookIds: Set<Int>) {
        for bookId in bookIds {
            guard let book = dataManager.booksById[bookId] else { continue }
            for (oldName, value) in bookLookup where value.book.id == bookId {
                bookLookup.removeValue(forKey: oldName)
                bookLookup[book.book] = (value.category, book)
                break
            }
            updateSubject.send(.reloadItem(book, reloadChildren: false))
        }
    }

    /// Dipanggil setelah kitab selesai diintegrasikan ke archive.
    /// Reload parent category agar status/icon ter-update.
    private func reloadParentCategory(ofBookId bookId: Int) {
        if showOnlyDownloaded {
            handleIntegratedBookUpdate(bookId)
            return
        }
        guard let parent = findParentCategory(ofBookId: bookId, in: displayedCategories) else { return }

        if isDownloadModal {
            if let childIndex = parent.children.firstIndex(where: { ($0 as? BooksData)?.id == bookId }) {
                updateSubject.send(.beginUpdates)

                if parent.children.count == 1 {
                    parent.children.remove(at: childIndex)
                    selectedBookIds.remove(bookId)
                    if let index = displayedCategories.firstIndex(where: { $0 === parent }) {
                        displayedCategories.remove(at: index)
                        updateSubject.send(.removeItems(IndexSet(integer: index), parent: nil))
                    }
                    baseCategories = displayedCategories
                } else {
                    parent.children.remove(at: childIndex)
                    updateSubject.send(.removeItems(IndexSet(integer: childIndex), parent: parent))
                }

                updateSubject.send(.endUpdates)
                updateSubject.send(.reloadItem(parent, reloadChildren: false))
            }
        } else {
            if let book = parent.children.first(where: { ($0 as? BooksData)?.id == bookId }) {
                updateSubject.send(.reloadItem(book, reloadChildren: false))
            }
        }
    }

    private func handleIntegratedBookUpdate(_ bookId: Int) {
        guard let book = dataManager.booksById[bookId] else {
            removeBookFromDisplayed(bookId: bookId)
            return
        }
        if BookArchiveIntegrator.shared.isBookIntegrated(book) {
            insertIntegratedBookIntoDisplayed(book)
        } else if showOnlyDownloaded {
            removeBookFromDisplayed(bookId: bookId)
        }
    }

    private func removeBookFromDisplayed(bookId: Int) {
        func findAndRemove(in list: inout [CategoryData], parent: CategoryData?) -> Bool {
            var anyChanged = false
            for i in (0 ..< list.count).reversed() {
                let category = list[i]

                if let bookIndex = category.children.firstIndex(where: { ($0 as? BooksData)?.id == bookId }) {
                    updateSubject.send(.removeItems(IndexSet(integer: bookIndex), parent: category))
                    category.children.remove(at: bookIndex)
                    anyChanged = true
                }

                var subChanged = false
                for j in (0 ..< category.children.count).reversed() {
                    if let sub = category.children[j] as? CategoryData {
                        var subList = [sub]
                        if findAndRemove(in: &subList, parent: category) {
                            if subList.isEmpty {
                                updateSubject.send(.removeItems(IndexSet(integer: j), parent: category))
                                category.children.remove(at: j)
                            }
                            subChanged = true
                        }
                    }
                }

                if subChanged || anyChanged {
                    return true
                }
            }
            return false
        }

        var list = displayedCategories
        if findAndRemove(in: &list, parent: nil) {
            var rootChanged = false
            for i in (0 ..< list.count).reversed() {
                if list[i].children.isEmpty {
                    #if os(macOS)
                    updateSubject.send(.removeItems(IndexSet(integer: i), parent: nil))
                    #endif
                    list.remove(at: i)
                    rootChanged = true
                }
            }

            if rootChanged {
                displayedCategories = list
                baseCategories = displayedCategories
            } else {
                baseCategories = list
            }
        }
    }

    private func findParentCategory(ofBookId bookId: Int, in categories: [CategoryData]) -> CategoryData? {
        for category in categories {
            for child in category.children {
                if let b = child as? BooksData, b.id == bookId { return category }
                if let sub = child as? CategoryData,
                   let found = findParentCategory(ofBookId: bookId, in: [sub]) { return found }
            }
        }
        return nil
    }

    private func findPathToBook(bookId: Int, in categories: [CategoryData]) -> [CategoryData]? {
        for category in categories {
            for child in category.children {
                if let b = child as? BooksData, b.id == bookId { return [category] }
                if let sub = child as? CategoryData,
                   let path = findPathToBook(bookId: bookId, in: [sub]) { return [category] + path }
            }
        }
        return nil
    }

    @discardableResult
    private func insertBook(
        _ book: BooksData,
        originalCategory: CategoryData,
        targetCategory: CategoryData
    ) -> Int? {
        if targetCategory.children.contains(where: { ($0 as? BooksData)?.id == book.id }) {
            return nil
        }
        let existingBooks = targetCategory.children.compactMap { $0 as? BooksData }
        let originalIndex = originalCategory.children.firstIndex { ($0 as? BooksData)?.id == book.id } ?? originalCategory.children.count
        var insertBookIndex = 0
        for existingBook in existingBooks {
            let existingIndex = originalCategory.children.firstIndex { ($0 as? BooksData)?.id == existingBook.id } ?? originalCategory.children.count
            if existingIndex > originalIndex { break }
            insertBookIndex += 1
        }
        let firstBookIndex = targetCategory.children.firstIndex { $0 is BooksData } ?? targetCategory.children.count
        targetCategory.children.insert(book, at: firstBookIndex + insertBookIndex)
        return firstBookIndex + insertBookIndex
    }

    @discardableResult
    private func insertCategory(_ category: CategoryData, into list: inout [CategoryData]) -> Int {
        let insertIndex = list.firstIndex { $0.order > category.order } ?? list.count
        list.insert(category, at: insertIndex)
        return insertIndex
    }

    @discardableResult
    private func insertCategory(_ category: CategoryData, into children: inout [Any]) -> Int {
        let firstBookIndex = children.firstIndex { $0 is BooksData } ?? children.count
        let categoryIndex = children.enumerated().first { _, element in
            guard let existing = element as? CategoryData else { return false }
            return existing.order > category.order
        }?.offset ?? firstBookIndex
        let insertIndex = min(categoryIndex, firstBookIndex)
        children.insert(category, at: insertIndex)
        return insertIndex
    }

    private func insertIntegratedBookIntoDisplayed(_ book: BooksData) {
        guard let path = findPathToBook(bookId: book.id, in: dataManager.allRootCategories),
              let originalLeaf = path.last else { return }

        var currentParent: CategoryData?
        for category in path {
            if let parent = currentParent {
                if let existing = parent.children.compactMap({ $0 as? CategoryData }).first(where: { $0.id == category.id }) {
                    currentParent = existing
                } else {
                    let clone = category.copy() as! CategoryData
                    clone.children = []
                    let insertIndex = insertCategory(clone, into: &parent.children)
                    updateSubject.send(.insertItems(IndexSet(integer: insertIndex), parent: parent))
                    currentParent = clone
                }
            } else {
                if let existing = displayedCategories.first(where: { $0.id == category.id }) {
                    currentParent = existing
                } else {
                    let clone = category.copy() as! CategoryData
                    clone.children = []
                    var list = displayedCategories
                    let insertIndex = insertCategory(clone, into: &list)
                    displayedCategories = list
                    updateSubject.send(.insertItems(IndexSet(integer: insertIndex), parent: nil))
                    currentParent = clone
                }
            }
        }

        guard let leaf = currentParent else { return }

        let insertIndex = insertBook(book, originalCategory: originalLeaf, targetCategory: leaf)

        if let insertIndex {
            updateSubject.send(.insertItems(IndexSet(integer: insertIndex), parent: leaf))
        }

        if let bookName = selectedBookName {
            // Optional string routing handled by view manager if needed,
            // but typically restore selection handles it.
            updateSubject.send(.expandItem(bookName))

            /* Removed iOS implementation cause this func is
             macOS only. see line 701 #if os(macOS)
             func setupMacOSBinding its closed #endif
             on line 1054 func findCategoryInDisplayed. */
        }
    }

    func findCategoryInDisplayed(_ categoryId: Int) -> CategoryData? {
        func search(_ category: CategoryData) -> CategoryData? {
            if category.id == categoryId { return category }
            for child in category.children {
                if let sub = child as? CategoryData, let found = search(sub) { return found }
            }
            return nil
        }
        for root in displayedCategories {
            if let found = search(root) { return found }
        }
        return nil
    }
    #endif

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
