//
//  ReaderViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//

import Foundation

#if os(macOS)
extension ReaderViewModel: ObservableObject {}
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

#if os(iOS)
@Observable
#endif
class ReaderViewModel: ViewModelBase {
    // MARK: - Shared State

    var currentBook: BooksData?
    var currentPage: Int?
    var currentPart: Int?
    var currentContentId: Int = 0

    #if os(macOS)
    @Published var contentText: String = ""
    @Published var state: ViewModelState = .idle
    @Published var totalParts: Int = 0
    @Published var minPageInPart: Int = 0
    @Published var maxPageInPart: Int = 0
    #else
    var contentText: String = ""
    var state: ViewModelState = .idle
    var totalParts: Int = 0
    var minPageInPart: Int = 0
    var maxPageInPart: Int = 0
    #endif

    // MARK: - macOS-Only State

    #if os(macOS)
    @Published var windowTitle: String = ""
    @Published var windowSubtitle: String = ""

    /// Called when content changes — UI should update text view
    var onContentChanged: ((BookContent) -> Void)?
    /// Called when page should scroll to top
    var onNeedScrollToTop: (() -> Void)?
    /// Called when error occurs
    var onError: ((Error) -> Void)?
    /// Called when window title should be updated
    var onWindowTitleChanged: ((String, String) -> Void)?

    // macOS Annotations Support. Tidak perlu publish disini.
    // IbarotTextView sudah pintar handling notifikasi perubahan anotasi.
    var currentAnnotations: [Annotation] {
        guard let bkId = currentBook?.id else { return .init() }
        return annotationManager.loadAnnotations(
            bkId: bkId, contentId: currentContentId
        )
    }
    #endif

    // MARK: - iOS-Only State

    #if os(iOS)
    static let kfgqpc = Font.custom(ArabicFont.kfgqpcUthmanTahaNaskh.rawValue, size: 16)
    static let kfgqpcTitle = Font.custom(ArabicFont.kfgqpcUthmanTahaNaskh.rawValue, size: 18)
    static let kfgqpcList = Font.custom(ArabicFont.kfgqpcUthmanTahaNaskh.rawValue, size: 20)

    var searchText: String = ""
    var targetAnnotation: Annotation?
    var searchViewModel = SearchViewModel()
    var readerState: ReaderState = .init()
    var needsScrollRestore: Bool = false
    var fetchScrollPosition: (() -> CGPoint?)?
    var fetchSelectedRange: (() -> NSRange?)?
    var currentAnnotations: [Annotation] = []
    #endif

    // MARK: - Computed Properties
    #if os(macOS)
    lazy var tocViewModel: BookTOCViewModel = .init(connFactory: { [weak self] in
        self?.bookConnection ?? BookConnection()
    })
    #elseif os(iOS)
    @ObservationIgnored
    lazy var tocViewModel: BookTOCViewModel = .init(connFactory: { [weak self] in
        self?.bookConnection ?? BookConnection()
    })
    #endif

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
        BookPageCache.shared.get(
            bookId: currentBook?.id ?? 0,
            contentId: currentContentId
        )?.nash ?? ""
    }

    /// Helper for copy functionality
    func getCopyReference(for selectedText: String) -> String {
        let bookName = currentBook?.book ?? ""
        var referencePage: [String] = []

        if let part = currentPart, part != -1 {
            referencePage.append("ج: \(part)".convertToArabicDigits())
        }

        if let page = currentPage {
            referencePage.append("ص: \(page)".convertToArabicDigits())
        }

        let referenceLines = "~ \(bookName) - \(referencePage.joined(separator: " • "))"
        return "\(selectedText)\n\n__________\n\(referenceLines)"
    }

    /// Helper for share functionality
    func getShareReference(for selectedText: String) -> String {
        let bookName = currentBook?.book ?? ""
        var referencePage: [String] = []

        if let part = currentPart, part != -1 {
            referencePage.append("ج: \(part)".convertToArabicDigits())
        }

        if let page = currentPage {
            referencePage.append("ص: \(page)".convertToArabicDigits())
        }

        let referenceLines = "~ \(bookName) - \(referencePage.joined(separator: " • "))"
        return "\(selectedText)\n\n\(referenceLines)"
    }

    // MARK: - Dependencies

    private(set) var bookConnection: BookConnection = .init()
    private let historyVM: HistoryViewModel = .shared
    private let annotationManager: AnnotationManager = .shared
    private let annotationCoordinator: AnnotationCoordinator = .init()

    // MARK: - Private Properties

    private var _currentID: Int?

    private var currentID: Int? {
        get { _currentID }
        set { _currentID = newValue }
    }

    // MARK: - Initialization

    init(book: BooksData? = nil) {
        super.init()
        if let book { currentBook = book }
        setupNotificationObservers()
    }

    // MARK: - Book Loading

    /// Loads initial content, optionally restoring a specific contentId
    func loadInitialContent(initialContentId: Int? = nil) {
        guard let book = currentBook else { return }

        do {
            try bookConnection.connect(archive: book.archive)
        } catch {
            contentText = DatabaseError.bookNotFound(book.archive).localizedDescription
        }

        // Start loading TOC immediately for both platforms
        tocViewModel.loadTOC(book: book)

        guard let initialContentId else {
            loadFromHistory(for: book)
            return
        }

        if let content = getContent(
            bkId: book.id,
            contentId: initialContentId
        ) {
            updateContentState(with: content)
        } else {
            contentText = "Content ID not found."
        }
    }

    func getContent(bkId: Int, contentId: Int) -> BookContent? {
        bookConnection.getContent(bkid: String(bkId), contentId: contentId)
    }

    func loadFromHistory(for book: BooksData) {
        // Try to restore from history first
        guard let lastContentId = historyVM.entriesByBookId[book.id]?.lastContentId,
              let content = bookConnection.getContent(bkid: String(book.id), contentId: lastContentId)
        else {
            getFirstBookContent(for: book)
            return
        }

        updateContentState(with: content)
    }

    func getFirstBookContent(for book: BooksData) {
        if let content = bookConnection.getFirstContent(bkid: String(book.id)) {
            updateContentState(with: content)
        } else {
            contentText = "No content found for this book."
        }
    }

    func fetchBookInfo(completion: @escaping (BooksData?) -> Void) {
        guard let currentBook else {
            completion(nil)
            return
        }
        let dm = LibraryDataManager.shared
        guard let bookOnLibrary = dm.getBook([currentBook.id]).first else {
            completion(nil)
            return
        }
        self.currentBook = bookOnLibrary
        dm.loadBookInfo(bookOnLibrary.id) {
            completion(bookOnLibrary)
        }
    }

    #if os(macOS)
    /// Connects to book archive with bundle fallback (macOS only)
    func connectBookWithBundleFallback(_ book: BooksData) async throws {
        guard AppConfig.isUsingBundleMode else {
            try bookConnection.connect(archive: book.archive)
            return
        }

        guard !BookArchiveIntegrator.shared.isBookIntegrated(book) else {
            try bookConnection.connect(archive: book.archive)
            return
        }

        let confirmed = await BookIntegrateModalCenter.shared
            .presentAndWaitForConfirmation(book: book)
        guard confirmed else { throw CancellationError() }

        defer {
            Task { @MainActor in
                BookIntegrateModalCenter.shared.dismiss()
            }
        }

        try await BookArchiveIntegrator.shared.ensureBookIntegrated(
            book,
            onIntegrating: {
                await BookIntegrateModalCenter.shared.showIntegrating()
            }
        )

        try bookConnection.connect(archive: book.archive)
    }
    #endif

    // MARK: - Navigation

    enum PageDirection {
        case next
        case prev
    }

    func navigateToPage(direction: PageDirection) -> BookContent? {
        guard let currentBook, let currentId = currentID else { return nil }

        let content: BookContent? = switch direction {
        case .next:
            bookConnection.getNextPage(from: currentBook, contentId: currentId)
        case .prev:
            bookConnection.getPrevPage(from: currentBook, contentId: currentId)
        }

        #if os(macOS)
        onNeedScrollToTop?()
        #endif

        return content
    }

    func goToNextPage() {
        guard let content = navigateToPage(direction: .next) else { return }
        updateContentState(with: content)
    }

    func goToPrevPage() {
        guard let content = navigateToPage(direction: .prev) else { return }
        updateContentState(with: content)
    }

    func fetchContentById(_ contentId: Int) {
        guard let currentBook else { return }
        if let content = bookConnection.getContent(
            bkid: "\(currentBook.id)",
            contentId: contentId,
            quran: false
        ) {
            #if os(iOS)
            DispatchQueue.main.async { [weak self] in
                self?.updateContentState(with: content)
            }
            #else
            updateContentState(with: content)
            #endif
        }
    }

    #if os(macOS)
    // MARK: - State Management

    func updateState(_ state: inout ReaderState) {
        state.edit {
            $0.currentBook = currentBook
            $0.currentPage = currentPage
            $0.currentID = currentID
            $0.currentPart = currentPart
        }
    }

    @discardableResult
    func restore(from state: ReaderState) -> BookContent? {
        guard state.hasContent else {
            cleanUpState()
            return nil
        }

        guard let book = state.currentBook else { return nil }

        do {
            try bookConnection.connect(archive: book.archive)
            if AppConfig.isUsingBundleMode,
               !BookArchiveIntegrator.shared.isBookIntegrated(book)
            {
                currentBook = nil
                return nil
            } else if currentBook?.id != book.id {
                currentBook = book
            }

            tocViewModel.loadTOC(book: book)

            if let id = state.currentID,
               let content = bookConnection.getContent(bkid: String(book.id), contentId: id)
            {
                updateContentState(with: content)
                return content
            }
        } catch {
            onError?(error)
        }

        return nil
    }

    func cleanUpState() {
        contentText = ""
        currentBook = nil
        currentPage = nil
        currentPart = nil
        currentID = nil
        currentContentId = 0
        windowTitle = ""
        windowSubtitle = ""
        bookConnection = .init()
    }
    #endif

    // MARK: - Private: Core Update

    func updateContentState(with content: BookContent) {
        contentText = content.nash
        currentPart = content.part
        currentPage = content.page
        currentID = content.id
        currentContentId = content.id

        if let bookId = currentBook?.id {
            historyVM.updateLastContentId(content.id, for: bookId)
        }

        loadAnnotations()

        #if os(macOS)
        onContentChanged?(content)
        updateWindowTitle(
            book: currentBook, page: currentPage, part: currentPart
        )
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

    #if os(macOS)
    func refreshCurrentPage() {
        guard let currentBook, let currentID,
              let content = bookConnection.getContent(
                  bkid: "\(currentBook.id)",
                  contentId: currentID
              )
        else { return }

        contentText = content.nash
        onContentChanged?(content)
    }

    // MARK: - macOS: Window Title

    func updateWindowTitle(book: BooksData?, page: Int?, part: Int?) {
        guard let book else {
            windowTitle = ""
            windowSubtitle = ""
            onWindowTitleChanged?("", "")
            return
        }

        let title = book.book
        let muallif = DatabaseManager.shared.getAuthor(book.muallif)

        if let page {
            let pageArb = String(page).convertToArabicDigits()
            if let part {
                let partArb = String(part).convertToArabicDigits()
                let subtitle = "\(muallif?.nama ?? "") ・ الصفحة \(pageArb) ・ الجزء \(partArb)"
                windowTitle = title
                windowSubtitle = subtitle
                onWindowTitleChanged?(title, subtitle)
            } else {
                let subtitle = "\(muallif?.nama ?? "") ・ الصفحة \(pageArb)"
                windowTitle = title
                windowSubtitle = subtitle
                onWindowTitleChanged?(title, subtitle)
            }
        } else {
            windowTitle = title
            windowSubtitle = muallif?.nama ?? ""
            onWindowTitleChanged?(title, muallif?.nama ?? "")
        }
    }
    #endif

    // MARK: - Navigation Limits

    func updateNavigationLimits() {
        guard let part = currentPart, let book = currentBook else { return }
        let bkid = String(book.id)

        Task.detached { [weak self] in
            guard let self else { return }
            let total = bookConnection.getTotalParts(bkid: bkid)

            let juz = part < 1 ? 1 : part
            let minPg = bookConnection.getMinPagesInPart(bkid: bkid, part: juz)
            let maxPg = bookConnection.getPagesInPart(bkid: bkid, part: juz)

            await MainActor.run {
                self.totalParts = total
                self.minPageInPart = minPg
                self.maxPageInPart = maxPg
            }
        }
    }

    func jumpToPart(_ part: Int) {
        guard let book = currentBook else { return }
        let bkid = String(book.id)
        Task.detached { [weak self] in
            guard let self else { return }
            let minPage = bookConnection.getMinPagesInPart(bkid: bkid, part: part)
            guard let result = bookConnection.getContent(
                bkid: bkid, part: part, page: minPage
            )
            else { return }

            await MainActor.run { [result] in
                self.updateContentState(with: result)
            }
        }
    }

    func jumpToPage(_ page: Int) {
        guard let book = currentBook else { return }
        let bkid = String(book.id)
        let part = currentPart ?? -1 <= 1 ? 1 : currentPart!
        Task { [weak self] in
            guard let self else { return }
            guard let result = bookConnection.getContent(
                bkid: bkid, part: part, page: page
            )
            else { return }

            await MainActor.run { [result] in
                self.updateContentState(with: result)
            }
        }
    }

    #if os(iOS)
    func saveCurrentState() {
        if let scroll = fetchScrollPosition?() {
            readerState.scrollPosition = scroll
        }
        if let range = fetchSelectedRange?() {
            readerState.selectedRange = range
        }
    }

    func didSelectTOCNode(id: Int) {
        searchText = ""
        targetAnnotation = nil
        fetchContentById(id)
    }

    func didSelectSearch(query: String, contentId: Int) {
        searchText = query
        fetchContentById(contentId)
    }

    func didSelectAnnotation(_ ann: Annotation) {
        targetAnnotation = ann
        fetchContentById(Int(ann.contentId))
    }
    #endif

    // MARK: - Shared: Annotations

    func loadAnnotations() {
        guard let book = currentBook else { return }
        let anns = annotationManager.loadAnnotations(
            bkId: book.id,
            contentId: currentContentId
        )

        #if os(iOS)
        currentAnnotations = anns
        #endif
    }

    func findBestAnnotation(for range: NSRange) -> Annotation? {
        guard let book = currentBook else { return nil }
        return annotationCoordinator.findBestAnnotation(
            overlapping: range,
            bkId: book.id,
            contentId: currentContentId,
            showHarakat: TextViewState.shared.showHarakat
        )
    }

    func addAnnotation(
        in range: NSRange,
        mode: AnnotationMode,
        sourceText: String,
        color: PlatformColor
    ) throws {
        guard let book = currentBook else { return }
        _ = try annotationCoordinator.saveHighlight(
            text: sourceText,
            range: range,
            color: color,
            bkId: book.id,
            contentId: currentContentId,
            page: currentPage ?? 0,
            part: currentPart ?? 0,
            diacriticsText: diacriticsText,
            showHarakat: showHarakat,
            mode: mode
        )
        loadAnnotations()
    }

    func deleteAnnotation(id: Int64) throws {
        try annotationManager.deleteAnnotation(id: id)
        loadAnnotations()
    }

    func updateAnnotation(_ annotation: Annotation) throws {
        try annotationManager.updateAnnotation(annotation)
        loadAnnotations()
    }
}

// MARK: - Notification Observers

extension ReaderViewModel {
    func setupNotificationObservers() {
        #if os(macOS)
        addObserver(
            forName: .libraryFolderChanged,
            object: nil, queue: .current
        ) { [weak self] _ in
            Task { @MainActor in self?.handleLibraryFolderChanged() }
        }
        addObserver(
            forName: .bookIntegrated,
            object: nil, queue: .current
        ) { [weak self] notification in
            Task { @MainActor in self?.handleBookIntegrated(notification) }
        }
        #endif

        #if os(iOS)
        addObserver(
            forName: .annotationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadAnnotations()
        }

        addObserver(
            forName: .annotationTreeDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadAnnotations()
        }
        #endif
    }

    #if os(macOS)
    func handleLibraryFolderChanged() {
        cleanUpState()
    }

    func handleBookIntegrated(_ notification: Notification) {
        guard let bookId = notification.object as? Int,
              let currentBook,
              currentBook.id == bookId,
              !BookArchiveIntegrator.shared.isBookIntegrated(currentBook)
        else { return }

        cleanUpState()
    }
    #endif
}
