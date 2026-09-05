//
//  SearchViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//

import Combine
import Foundation
import Observation

// MARK: - SearchViewModel

@Observable
final class SearchViewModel: ViewModelBase {
    // MARK: - Shared State

    var query: String = ""
    var searchMode: SearchMode = .phrase
    var nearDistance: Int = UserDefaults.standard.searchNearDistance {
        didSet {
            UserDefaults.standard.searchNearDistance = nearDistance
        }
    }

    var results: [SearchResultItem] = []
    var isSearching: Bool = false
    var isPaused: Bool = false
    var totalTables: Int = 0
    var completedTables: Int = 0
    var currentTable: String = ""
    var totalRowsInTable: Int = 0
    var completedRowsInTable: Int = 0
    var selectedBookIds: Set<Int> = []
    var onStateChanged: ((ViewModelState) -> Void)?

    var state: ViewModelState = .loading {
        didSet {
            onStateChanged?(state)
        }
    }

    var targetBookId: String = ""

    // MARK: - iOS-only

    #if os(iOS)
    var filterText: String = "" {
        didSet {
            if oldValue != filterText {
                filterSubject.send(filterText)
            }
        }
    }

    var displayedCategories: [CategoryData] = []
    var updateTrigger: Int = 0
    var searchHistory: [String] = []
    let historyKey = "SearchHistory"

    let filterSubject = PassthroughSubject<String, Never>()
    let refreshSubject = PassthroughSubject<Void, Never>()
    #endif

    // MARK: - macOS Progress Streams

    #if os(macOS)
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
    /// Dikirim saat data dimigrasi atau butuh reload UI secara penuh
    let searchNeedsReload = PassthroughSubject<Void, Never>()
    #endif

    let bkConn = BookConnection()

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

    let searchEngine = SearchEngine()
    let ldm = LibraryDataManager.shared
    var searchWork: Task<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()
        setupObservers()
        #if os(iOS)
        loadLibraryData()
        loadHistory()
        #endif
    }

    // MARK: - Migration Support

    override func migrateBookId(from oldId: Int, to newId: Int) {
        if selectedBookIds.contains(oldId) {
            selectedBookIds.remove(oldId)
            selectedBookIds.insert(newId)
        }

        for i in 0 ..< results.count where results[i].bookId == oldId {
            let oldItem = results[i]
            results[i] = SearchResultItem(
                archive: oldItem.archive,
                tableName: "b\(newId)",
                bookId: newId,
                bookTitle: oldItem.bookTitle,
                page: oldItem.page,
                part: oldItem.part,
                attributedText: oldItem.attributedText
            )
        }

        if targetBookId == String(oldId) {
            targetBookId = String(newId)
        }

        #if os(macOS)
        searchNeedsReload.send(())
        #else
        updateDisplayedCategories()
        #endif
    }

    deinit {
        searchWork?.cancel()
        searchWork = nil
        removeNotificationObservers()
    }
}
