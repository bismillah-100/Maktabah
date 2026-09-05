//
//  ReaderViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//

import Foundation
import Observation
import SwiftUI

@Observable
class ReaderViewModel: ViewModelBase {
    // MARK: - Shared State

    var currentBook: BooksData?
    var currentPage: Int?
    var currentPart: Int?
    var currentContentId: Int = 0
    var recordHistory: Bool = true

    var contentText: String = ""
    #if os(macOS)
    var contentPayload: ContentRenderPayload = .init(
        text: "", keepScrollPosition: false
    )
    #endif
    var currentAnnotations: [Annotation] = []

    var state: ViewModelState = .idle
    var totalParts: Int = 0
    var minPageInPart: Int = 0
    var maxPageInPart: Int = 0

    // MARK: - macOS-Only State

    #if os(macOS)
    var windowTitle: String = ""
    var windowSubtitle: String = ""

    /// Called when content changes — UI should update text view
    var onContentChanged: ((BookContent) -> Void)?
    /// Called when page should scroll to top
    var onNeedScrollToTop: (() -> Void)?
    /// Called when error occurs
    var onError: ((Error) -> Void)?
    /// Called when window title should be updated
    var onWindowTitleChanged: ((String, String) -> Void)?
    /// Callen when ``contentPayload`` changed.
    var onPayloadChanged: ((ContentRenderPayload) -> Void)?
    /// Called when navigation limits/page/part update
    var onNavigationLimitsChanged: (() -> Void)?
    #endif

    // MARK: - iOS-Only State

    #if os(iOS)
    static let kfgqpc = Font.custom(ArabicFont.kfgqpcUthmanTahaNaskh.rawValue, size: 16)
    static let kfgqpcTitle = Font.custom(ArabicFont.kfgqpcUthmanTahaNaskh.rawValue, size: 18)
    static let kfgqpcList = Font.custom(ArabicFont.kfgqpcUthmanTahaNaskh.rawValue, size: 20)

    var searchText: String = ""
    var searchMode: SearchMode?
    var nearDistance: Int = UserDefaults.standard.searchNearDistance {
        didSet {
            UserDefaults.standard.searchNearDistance = nearDistance
        }
    }

    var targetAnnotation: Annotation?
    var searchViewModel = SearchViewModel()
    var readerState: ReaderState = .init()
    var needsScrollRestore: Bool = false
    var fetchScrollPosition: (() -> CGPoint?)?
    var fetchSelectedRange: (() -> NSRange?)?
    #endif

    // MARK: - Computed Properties

    @ObservationIgnored
    lazy var tocViewModel: BookTOCViewModel = .init(connFactory: { [weak self] in
        self?.bookConnection ?? BookConnection()
    })

    /// Tasykil/Harokat
    var showHarakat: Bool {
        TextViewState.shared.showHarakat
    }

    /// Cross-platform subtitle string (page/part info)
    var statusSubtitle: String {
        if let currentPage {
            let pageArb = String(currentPage).convertToArabicDigits()
            if let currentPart, currentPart != -1 {
                let partArb = String(currentPart).convertToArabicDigits()
                return "ص \(pageArb) ・ ج \(partArb)"
            } else {
                return "ص \(pageArb)"
            }
        } else {
            return "صفحة"
        }
    }

    var diacriticsText: String {
        currentBookContent?.nash ?? ""
    }

    var currentBookContent: BookContent? {
        guard let bkId = currentBook?.id else { return nil }
        return BookPageCache.shared.get(bookId: bkId, contentId: currentContentId)
    }

    // MARK: - Dependencies

    var bookConnection: BookConnection = .init()
    let historyVM: HistoryViewModel = .shared
    let annotationManager: AnnotationManager = .shared
    let annotationCoordinator: AnnotationCoordinator = .init()

    // MARK: - Private Properties

    var _currentID: Int?

    var currentID: Int? {
        get { _currentID }
        set { _currentID = newValue }
    }

    // MARK: - Initialization

    init(book: BooksData? = nil) {
        super.init()
        if let book { currentBook = book }
        setupNotificationObservers()
    }

    // MARK: - Override

    override func migrateBookId(from oldId: Int, to newId: Int) {
        guard let current = currentBook, current.id == oldId else { return }
        if let newBookData = LibraryDataManager.shared.booksById[newId] {
            currentBook = newBookData
        }
    }

    // MARK: - Private: Core Update

    func updateContentState(with content: BookContent) {
        contentText = content.nash
        #if os(macOS)
        contentPayload = ContentRenderPayload(text: content.nash, content: content, keepScrollPosition: false)
        onPayloadChanged?(contentPayload)
        #endif
        currentPart = content.part
        currentPage = content.page
        currentID = content.id
        currentContentId = content.id

        if recordHistory, let bookId = currentBook?.id {
            historyVM.updateLastContentId(content.id, for: bookId)
        }

        loadAnnotations()

        #if os(macOS)
        onContentChanged?(content)
        updateWindowTitle(
            book: currentBook, page: currentPage, part: currentPart
        )
        onNavigationLimitsChanged?()
        #endif

        #if os(iOS)
        // Sync to state
        readerState.currentBook = currentBook
        readerState.currentID = content.id
        readerState.currentPart = content.part
        readerState.currentPage = content.page
        // Clear saved scroll/selection so it scrolls to top on page change
        readerState.scrollPosition = nil
        readerState.selectedRange = nil
        updateNavigationLimits()
        #endif
    }
}
