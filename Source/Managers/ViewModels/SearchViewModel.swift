//
//  SearchViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//

import Combine
import Foundation

// MARK: - SearchViewModel

#if os(macOS)
extension SearchViewModel: ObservableObject {}
#endif

#if os(iOS)
@Observable
#endif
final class SearchViewModel: ViewModelBase {
    // MARK: - Shared State

    var query: String = ""
    var searchMode: SearchMode = .phrase
    private(set) var results: [SearchResultItem] = []
    private(set) var isSearching: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var totalTables: Int = 0
    private(set) var completedTables: Int = 0
    private(set) var currentTable: String = ""
    private(set) var totalRowsInTable: Int = 0
    private(set) var completedRowsInTable: Int = 0
    private(set) var selectedBookIds: Set<Int> = []

    #if os(macOS)
    @Published var state: ViewModelState = .loading
    #elseif os(iOS)
    var state: ViewModelState = .loading
    #endif

    // MARK: - iOS-only

    #if os(iOS)
    var filterText: String = "" {
        didSet {
            if oldValue != filterText {
                filterSubject.send(filterText)
            }
        }
    }

    private(set) var displayedCategories: [CategoryData] = []
    private(set) var updateTrigger: Int = 0
    var searchHistory: [String] = []
    private let historyKey = "SearchHistory"
    #endif

    // MARK: - macOS-only

    #if os(macOS)
    var targetBookId: String = ""

    /// Dikirim sekali saat search dimulai; value = jumlah total tabel
    let searchDidInitialize = PassthroughSubject<Int, Never>()
    /// Dikirim tiap kali ada hasil baru ditambahkan ke `results`
    let searchDidReceiveResult = PassthroughSubject<Void, Never>()
    /// Dikirim tiap tabel selesai; value = (completed, total)
    let searchProgressDidUpdate = PassthroughSubject<(completed: Int, total: Int), Never>()
    /// Dikirim tiap baris diproses; value = (completed, total)
    let rowProgressDidUpdate = PassthroughSubject<(completed: Int, total: Int), Never>()
    /// Dikirim sekali saat search selesai sepenuhnya
    let searchDidComplete = PassthroughSubject<Void, Never>()
    #endif

    private let bkConn = BookConnection()

    // MARK: - Computed

    var progressPercentage: Double {
        guard totalTables > 0 else { return 0 }
        return Double(completedTables) / Double(totalTables)
    }

    var rowProgressPercentage: Double {
        guard totalRowsInTable > 0 else { return 0 }
        return Double(completedRowsInTable) / Double(totalRowsInTable)
    }

    // MARK: - Private

    private let searchEngine = SearchEngine()
    private let ldm = LibraryDataManager.shared
    private let filterSubject = PassthroughSubject<String, Never>()
    private let refreshSubject = PassthroughSubject<Void, Never>()
    private var searchWork: Task<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()
        setupObservers()
        #if os(iOS)
        loadLibraryData()
        loadHistory()
        #endif
    }

    deinit {
        searchWork?.cancel()
        searchWork = nil
        removeNotificationObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        #if os(iOS)
        filterSubject
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateDisplayedCategories() }
            .store(in: &cancellables)

        refreshSubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] in self?.updateDisplayedCategories() }
            .store(in: &cancellables)

        addObserver(
            forName: .bookIntegrated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSubject.send(())
            }
        }

        addObserver(
            forName: .bookIntegrated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSubject.send(())
            }
        }

        addObserver(
            forName: .booksChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSubject.send(())
            }
        }
        #endif

        addObserver(
            forName: .libraryFolderChanged, object: nil, queue: .current
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                state = .loading
                ldm.resetState()
                await ldm.reloadAllData()
                #if os(iOS)
                loadLibraryData()
                #elseif os(macOS)
                state = .loaded
                #endif
            }
        }
    }

    // MARK: - Library

    func loadLibraryData() {
        Task { [weak self] in
            guard let self, state == .loading else { return }
            await ldm.loadData()
            await ldm.buildArchive()
            await MainActor.run {
                self.state = .loaded
                #if os(iOS)
                self.updateDisplayedCategories()
                #endif
            }
        }
    }

    // MARK: - iOS: Filter & Categories

    #if os(iOS)
    func updateDisplayedCategories() {
        let base: [CategoryData] = AppConfig.isUsingBundleMode
            ? ldm.filterIntegrated()
            : ldm.allRootCategories

        if filterText.isEmpty {
            displayedCategories = base
        } else {
            displayedCategories = base.compactMap { ldm.filterCategory($0, searchText: filterText) }
        }
        updateTrigger += 1
    }

    // MARK: - iOS: History

    func loadHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    func addToHistory(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = searchHistory
        current.removeAll { $0 == trimmed }
        current.insert(trimmed, at: 0)
        if current.count > 20 { current = Array(current.prefix(20)) }
        searchHistory = current
        UserDefaults.standard.set(current, forKey: historyKey)
    }

    func removeFromHistory(_ query: String) {
        var current = searchHistory
        current.removeAll { $0 == query }
        searchHistory = current
        UserDefaults.standard.set(current, forKey: historyKey)
    }
    #endif

    // MARK: - macOS: Helpers

    #if os(macOS)
    func setSearchMode(_ mode: SearchMode) {
        searchMode = mode
    }

    func setSearchModeFromSegment(_ segmentIndex: Int) {
        switch segmentIndex {
        case 0: searchMode = .phrase
        case 1: searchMode = .contains
        case 2: searchMode = .or
        default: break
        }
    }

    func setTargetBook(_ bookId: String) {
        targetBookId = bookId
    }

    func getCheckedTables(from categories: [CategoryData]) -> Set<String> {
        ldm.getCheckedTables(categories)
    }

    func getBookTitle(for bookId: Int) -> String? {
        ldm.booksById[bookId]?.book
    }

    func resetProgress() {
        totalTables = 0
        completedTables = 0
        totalRowsInTable = 0
        completedRowsInTable = 0
        currentTable = ""
    }

    /// Resolve `BooksData` dari `SearchResultItem`. Returns nil jika tidak ditemukan.
    func resolveBook(from result: SearchResultItem) -> BooksData? {
        let table = result.tableName.hasPrefix("b")
            ? String(result.tableName.dropFirst())
            : result.tableName
        guard let tableInt = Int(table) else { return nil }
        return ldm.getBook([tableInt]).first
    }

    /// Load data library lalu isi `libraryViewManager` dengan kategori.
    func loadLibraryDataForDisplay(
        libraryViewManager: LibraryViewManager?,
        onComplete: @MainActor @escaping () -> Void
    ) {
        guard state == .loading, let libraryViewManager else {
            Task { [weak self] in
                self?.loadLibraryData()
                await onComplete()
            }
            return
        }
        Task.detached(priority: .userInitiated) { [weak libraryViewManager] in
            guard let libraryViewManager else { await onComplete(); return }
            await libraryViewManager.prepareData { [weak self] in
                guard let self else { onComplete(); return }
                Task.detached { [weak self] in
                    guard let self else { return }
                    await ldm.buildArchive()
                    await onComplete()
                    await MainActor.run {
                        self.state = .loaded
                    }
                }
            }
        }
    }
    #endif

    // MARK: - Bookmarked Search Results

    /// Load saved results dari database, emit via `searchDidReceiveResult`.
    @discardableResult
    func loadSavedResults(
        _ savedResults: [SavedResultsItem],
        onProgress: (@MainActor (Double) -> Void)? = nil,
        onInsert: (@MainActor (Int, Int) -> Void)? = nil, // (prevCount, newCount)
        onFinish: (@MainActor () -> Void)? = nil
    ) -> Task<Void, Never> {
        clearResults()
        if let first = savedResults.first { query = first.query }
        results = []
        totalTables = 0
        completedTables = 0
        completedRowsInTable = 0
        totalRowsInTable = 0

        let task = Task.detached { [weak self] in
            guard let self else { return }

            await onProgress?(Double(savedResults.count))

            let grouped = Dictionary(grouping: savedResults, by: \.archive)
            var buffer = ResultBuffer()

            for (archiveId, items) in grouped {
                guard searchWork?.isCancelled == false,
                      let arc = Int(archiveId)
                else { return }

                do {
                    try bkConn.connect(archive: arc)
                } catch {
                    continue
                }

                for item in items {
                    guard searchWork?.isCancelled == false else { return }
                    
                    while isPaused {
                        guard searchWork?.isCancelled == false else { return }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }

                    if let result = await processSavedItem(item) {
                        buffer.add(result)
                        if buffer.isFull {
                            await flushBuffer(&buffer, onInsert: onInsert)
                        }
                    }
                }
            }

            if !buffer.isEmpty {
                await flushBuffer(&buffer, onInsert: onInsert)
            }
            await onFinish?()
        }

        searchWork = task
        return task
    }

    private func processSavedItem(_ item: SavedResultsItem) async -> SearchResultItem? {
        guard let bookContent = bkConn.getContent(bkid: item.tableName, contentId: item.bookId)
        else { return nil }

        let bookId = Int(item.tableName.dropFirst()) ?? 0
        let book = ldm.booksById[bookId]
        let isMultilingual = book?.isMultiLanguage ?? false

        let normalized = bookContent.nash.convertToArabicDigits(isMultilingual: isMultilingual)
        let queryConverted = item.query.convertToArabicDigits(isMultilingual: isMultilingual)
        let snippet = normalized.snippetAround(keywords: [queryConverted], contextLength: 60)
        let attributed = snippet.highlightedAttributedText(keywords: [queryConverted])

        return SearchResultItem(
            archive: item.archive,
            tableName: item.tableName,
            bookId: item.bookId,
            bookTitle: item.bookTitle,
            page: bookContent.page,
            part: bookContent.part,
            attributedText: attributed
        )
    }

    private func flushBuffer(
        _ buffer: inout ResultBuffer,
        onInsert: (@MainActor (Int, Int) -> Void)?
    ) async {
        let items = buffer.flush()
        await MainActor.run { [weak self] in
            guard let self,
                  searchWork?.isCancelled == false
            else { return }
            let prev = results.count
            results.append(contentsOf: items)
            completedTables = prev + items.count
            onInsert?(prev, results.count)
        }
    }

    // MARK: - Search

    func setSelectedBooks(_ bookIds: Set<Int>) {
        selectedBookIds = bookIds
    }

    @MainActor
    func startSearch() {
        if query.isEmpty { return }

        if searchEngine.currentlyPaused() ||
            isPaused {
            searchEngine.resume()
            isPaused = false
            return
        }

        if searchEngine.isRunning() ||
            isSearching {
            searchEngine.pause()
            isPaused = true
            return
        }

        isSearching = true
        isPaused = false

        results = []
        totalTables = 0
        completedTables = 0
        completedRowsInTable = 0
        totalRowsInTable = 0

        let tablesToScan: Set<String>
        #if os(iOS)
        if selectedBookIds.isEmpty {
            tablesToScan = ldm.getCheckedTables(displayedCategories)
        } else {
            tablesToScan = Set(selectedBookIds.map { "b\($0)" })
        }
        #else
        if !selectedBookIds.isEmpty {
            tablesToScan = Set(selectedBookIds.map { "b\($0)" })
        } else if !targetBookId.isEmpty {
            tablesToScan = [targetBookId]
        } else {
            tablesToScan = []
        }
        #endif

        if tablesToScan.isEmpty { stopSearch(); return }

        searchWork = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            await ldm.performSearch(
                tableToScan: tablesToScan,
                searchEngine: searchEngine,
                query: query,
                mode: searchMode,
                onInitialize: { [weak self] total in
                    self?.totalTables = total
                    self?.completedTables = 0
                    #if os(macOS)
                    self?.searchDidInitialize.send(total)
                    #endif
                },
                onTableProgress: { [weak self] completed in
                    self?.completedTables = completed
                    #if os(macOS)
                    self?.searchProgressDidUpdate.send((completed: completed, self?.totalTables ?? 0))
                    #endif
                },
                onRowProgress: { [weak self] _, tableName, current, total in
                    self?.currentTable = tableName
                    self?.completedRowsInTable = current
                    self?.totalRowsInTable = total
                    #if os(macOS)
                    self?.rowProgressDidUpdate.send((completed: current, total: total))
                    #endif
                },
                completion: { [weak self] item in
                    self?.results.append(item)
                    #if os(macOS)
                    self?.searchDidReceiveResult.send()
                    #endif
                },
                onComplete: { [weak self] in
                    self?.stopSearch()
                }
            )
        }
    }

    func stopSearch() {
        searchEngine.stop()
        searchWork?.cancel()
        searchWork = nil
        isSearching = false
        isPaused = false

        #if os(macOS)
        completedTables = totalTables
        searchDidComplete.send()
        #endif
    }

    func clearResults() {
        stopSearch()
        results.removeAll()
    }

    func sortResults(by key: SearchSortKey, ascending: Bool) {
        SearchResultsSorter.sort(&results, by: key, ascending: ascending)
    }

    func commitBuffer(
        _ buffer: inout ResultBuffer,
        onItemAppended: @escaping (SearchResultItem, IndexSet) -> Void
    ) async {
        let items = buffer.flush()

        await MainActor.run { [weak self, items] in
            guard let self else { return }

            // Loop item satu per satu agar closure bisa dipanggil di setiap row
            for item in items {
                let currentIndex = results.count
                results.append(item)

                // Panggil closure bawaan
                onItemAppended(item, IndexSet(integer: currentIndex))
            }
        }
    }
}

// MARK: - SearchViewModel Restoration

extension SearchViewModel {
    /// Memulihkan status pencarian dari `ReaderState` ke dalam properti ViewModel.
    /// - Parameter state: Objek `ReaderState` yang menyimpan status sebelumnya.
    /// - Returns: Boolean yang menandakan apakah ada data hasil pencarian yang berhasil dipulihkan.
    func restore(from state: ReaderState) {
        // Hanya restore jika hasil saat ini kosong untuk menghindari overwrite saat pencarian aktif
        guard results.isEmpty,
              let savedResults = state.searchResults,
              !savedResults.isEmpty
        else {
            return
        }

        // Memulihkan query teks pencarian jika tersedia
        if let savedQuery = state.searchQuery {
            query = savedQuery
        }

        // Memasukkan kembali daftar hasil pencarian yang tersimpan
        results = savedResults
    }

    /// Menyimpan status pencarian saat ini ke dalam referensi `ReaderState`.
    /// - Parameter state: Referensi inout `ReaderState` yang akan diperbarui.
    func updateState(_ state: inout ReaderState) {
        state.searchResults = results
        state.searchQuery = query
    }

    /// Membersihkan seluruh data pencarian di dalam ViewModel.
    func cleanUpState() {
        clearResults()
        query = ""
    }
}

// MARK: - Result Buffer Helper

struct ResultBuffer {
    private var items: [SearchResultItem] = []
    private let batchSize = 10

    var isEmpty: Bool {
        items.isEmpty
    }

    var isFull: Bool {
        items.count >= batchSize
    }

    mutating func add(_ item: SearchResultItem) {
        items.append(item)
    }

    mutating func flush() -> [SearchResultItem] {
        let flushed = items
        items.removeAll(keepingCapacity: true)
        return flushed
    }
}
