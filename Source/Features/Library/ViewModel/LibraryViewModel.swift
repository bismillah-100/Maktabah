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
    let historyManager: HistoryViewModel = .shared

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
    var historySelectionTask: Task<Void, Never>?

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
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                self?.performSearch(self?.searchQuery ?? "")
            }
        }
    }

    var searchTask: Task<Void, Never>?

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
    let lookupQueue = SerialTaskQueue()

    var hasLoadedLibrary = false
    var _cachedDisplayedCategories: [CategoryData] = []
    var _authorHierarchy: [CategoryData] = []
    var _hasBuiltAuthorHierarchy = false
    let authorPageSize = 100
    var _displayedAuthorCount: Int = 0
    var _allFilteredAuthors: [CategoryData] = []
    var _displayedFilteredCount: Int = 0

    let refreshSubject = PassthroughSubject<Void, Never>()
    var bulkDownloadTask: Task<Void, Never>?

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
        if hasLoadedLibrary {
            return
        }
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

    func setBaseCategories(_ categories: [CategoryData], reload: Bool) {
        baseCategories = categories
        buildBookLookup()
    }

    func buildBookLookup() {
        lookupQueue.cancelAll()
        lookupQueue.enqueue { [weak self] in
            guard let self else { return }
            var newLookup: [String: (category: CategoryData, book: BooksData)] = [:]

            func traverse(_ category: CategoryData) {
                for child in category.children {
                    if let book = child as? BooksData {
                        newLookup[book.book] = (category, book)
                    } else if let sub = child as? CategoryData {
                        traverse(sub)
                    }
                }
            }

            for category in displayedCategories {
                traverse(category)
            }

            bookLookup = newLookup
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

    func isNetworkFailure(_ error: Error) -> Bool {
        if let bookError = error as? BookDownloadError, case .networkUnavailable = bookError {
            return true
        }
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
