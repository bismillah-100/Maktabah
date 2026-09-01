//
//  IbarotTextVC.swift
//  maktab
//
//  Created by MacBook on 07/12/25.
//

import Cocoa
import Combine

class IbarotTextVC: NSViewController {
    // MARK: - IBOutlets

    @IBOutlet weak var textView: IbarotTextView!

    // MARK: - Properties

    var sidebarVC: SidebarVC?
    var libraryVC: LibraryVC?
    weak var textDelegate: TextViewRenderable?

    /// ViewModel - manages all reader business logic
    let viewModel: ReaderViewModel = .init()

    private let defaultFontSize: CGFloat = 18.0

    // MARK: - Window Title Properties

    private let defaultTitle: String = "المكتبة الإسلامية"
    private let subtitle: String = "لتيسر البحث العبارة"

    var windowTitle: String = .init() {
        didSet {
            if windowTitle.isEmpty { return }
            view.window?.title = windowTitle
        }
    }

    var windowSubtitle: String = .init() {
        didSet {
            if windowSubtitle.isEmpty { return }
            view.window?.subtitle = windowSubtitle
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBindings()
        setupNotificationObservers()
        textDelegate = textView
    }

    // MARK: - Setup

    private func setupBindings() {
        textView.viewModel = viewModel
        // Bind content text changes syncrhounously
        viewModel.$contentPayload
            .sink { [weak self] payload in
                guard let self, !payload.text.isEmpty else { return }
                textDelegate?.loadIbarotText(
                    payload.text,
                    content: payload.content,
                    color: NSColor.header,
                    isMultiLanguage: viewModel.currentBook?.isMultiLanguage,
                    isImported: viewModel.currentBook?.isImported ?? false,
                    keepScrollPosition: payload.keepScrollPosition
                )
            }
            .store(in: &viewModel.cancellables)

        // Bind window title changes
        viewModel.onWindowTitleChanged = { [weak self] title, subtitle in
            self?.windowTitle = title
            self?.windowSubtitle = subtitle
        }

        // Bind content changed callback
        viewModel.onContentChanged = { [weak self] content in
            guard let self else { return }
            handleNavigationToContent(content.id)
        }

        // Setup textView annotation callbacks
        textView.onAddAnnotation = { [weak self] range, color, mode, sourceText in
            do {
                try self?.viewModel.addAnnotation(
                    in: range,
                    mode: mode,
                    sourceText: sourceText,
                    color: color
                )
            } catch {
                print("Failed to add annotation: \(error)")
            }
        }

        textView.onUpdateAnnotation = { [weak self] annotation in
            do {
                try self?.viewModel.updateAnnotation(annotation)
            } catch {
                print("Failed to update annotation: \(error)")
            }
        }

        textView.onDeleteAnnotation = { [weak self] id in
            do {
                try self?.viewModel.deleteAnnotation(id: id)
            } catch {
                print("Failed to delete annotation: \(error)")
            }
        }

        // Bind scroll to top callback
        viewModel.onNeedScrollToTop = { [weak self] in
            self?.textView.scrollToBeginningOfDocument(nil)
        }

        // Bind error callback
        viewModel.onError = { error in
            ReusableFunc.showAlert(
                title: "Error",
                message: error.localizedDescription,
                style: .critical
            )
        }

        // Bind TOC events
        viewModel.tocViewModel.onTOCLoadingStateChanged = { [weak self] isLoading in
            guard let self, let sidebarView = sidebarVC?.view else { return }
            if isLoading {
                ReusableFunc.showProgressWindow(sidebarView)
            } else {
                ReusableFunc.closeProgressWindow(sidebarView)
            }
        }

        viewModel.tocViewModel.onTOCLoaded = { [weak self] nodes in
            guard let self else { return }
            sidebarVC?.updateTOC(nodes)
            // Auto-expand TOC ke konten yang sedang aktif begitu TOC selesai di-load di background
            if viewModel.currentContentId > 0 {
                handleNavigationToContent(viewModel.currentContentId)
            }
        }
    }

    private var observerTokens: [NSObjectProtocol] = []

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setupNotificationObservers() {
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .libraryFolderChanged,
            object: nil,
            queue: .current
        ) { [weak self] _ in
            guard let self else { return }
            viewModel.cleanUpState()
            viewModel.tocViewModel.cleanUp()
        })

        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .bookIntegrated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let bookId = notification.object as? Int else { return }
            if viewModel.currentBook?.id == bookId {
                if !BookArchiveIntegrator.shared.isBookIntegrated(viewModel.currentBook!) {
                    clearUI()
                }
            }
        })

        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .bookIdMigrated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let oldId = userInfo["oldId"] as? Int,
                  let newId = userInfo["newId"] as? Int else { return }

            if viewModel.currentBook?.id == oldId {
                // ReaderViewModel handleBookIdMigrated will update its currentBook.
                // We just need to make sure IbarotTextVC doesn't crash or holds onto stale state.
                // Re-rendering or updating title can be triggered here if necessary.
                if let newBookData = LibraryDataManager.shared.booksById[newId] {
                    viewModel.currentBook = newBookData
                }
            }
        })
    }

    // MARK: - State Accessors

    private var splitVC: SplitVC? {
        var current: NSViewController? = self
        while let parent = current?.parent {
            if let unified = parent as? SplitVC {
                return unified
            }
            current = parent
        }
        return nil
    }

    var currentBook: BooksData? {
        viewModel.currentBook
    }

    var currentPage: Int? {
        viewModel.currentPage
    }

    var currentPart: Int? {
        viewModel.currentPart
    }

    /// Alias ke viewModel.bookConnection untuk backward compatibility dengan SidebarVC
    var bookDB: BookConnection {
        viewModel.bookConnection
    }

    var currentRowi: Rowi? {
        get { splitVC?.currentState.currentRowi }
        set {
            guard var state = splitVC?.currentState else { return }
            state.edit { $0.currentRowi = newValue }
        }
    }

    // MARK: - Public Methods

    func restoreWindowTitleAfterModeSwitch(oldTitle: String, oldSubtitle: String) {}

    private func setDefaultWindowTitle() {
        view.window?.title = defaultTitle
        view.window?.subtitle = subtitle
    }

    func didChangeBook(book: BooksData, loadSidebar: Bool = true) {
        if viewModel.currentBook?.id != book.id {
            viewModel.resetContentState()
        }
        viewModel.currentBook = book

        // Update window title
        viewModel.updateWindowTitle(
            book: book, page: currentPage, part: currentPart
        )

        libraryVC?.dataVM.viewModel.selectedBookName = book.book
        libraryVC?.dataVM.restoreSelection(byBookName: book.book)
    }

    func updateLibraryReference(for mode: AppMode, library: LibraryVC?) {
        libraryVC = (mode == .viewer) ? library : nil
    }

    // MARK: - Font & Appearance

    func applyFont(_ redraw: Bool) {
        if !redraw {
            guard let scrollView = textView.enclosingScrollView else { return }
            let visibleRect = scrollView.documentVisibleRect
            let totalHeight = scrollView.documentView?.frame.size.height ?? 0
            let scrollPercentage = totalHeight > 0 ? (visibleRect.origin.y / totalHeight) : 0

            let defaults = UserDefaults.standard
            var fontSize = CGFloat(defaults.textViewFontSize)
            if fontSize == 0 { fontSize = defaultFontSize }
            let fontName = defaults.textViewFontName

            textView.textStorage?.applyFont(
                footnoteRanges: textView.footnoteRanges,
                fontName: fontName,
                fontSize: fontSize
            )
            textView.typingAttributes[.font] = NSFont(name: fontName, size: fontSize)

            textView.textLayoutManager?.ensureFullDocumentLayout()

            let newTotalHeight = scrollView.documentView?.frame.size.height ?? 0
            let targetY = scrollPercentage * newTotalHeight
            scrollView.contentView.scroll(to: NSPoint(x: visibleRect.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            viewModel.refreshCurrentPage(keepScrollPosition: true)
        }
    }

    func toggleHarakat(_ on: Bool) {
        viewModel.refreshCurrentPage(keepScrollPosition: true)
    }

    func applyBackgroundColor(_ color: NSColor) {
        textView.backgroundColor = color
        if let textLayoutManager = textView.textLayoutManager {
            textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
        }
    }

    // MARK: - Actions

    @IBAction func previousPage(_ sender: Any?) {
        viewModel.goToPrevPage()
    }

    @IBAction func nextPage(_ sender: Any?) {
        viewModel.goToNextPage()
    }

    @IBAction func bookInfo(_ sender: Any) {
        viewModel.fetchBookInfo { [weak self] bookData in
            guard let self, let bookData else { return }
            let bookInf = BookInfo()
            bookInf.bookData = bookData
            if let button = sender as? NSButton {
                WindowController.showPopOver(sender: button, viewController: bookInf)
            } else {
                bookInf.popOver = false
                presentAsSheet(bookInf)
            }
        }
    }

    @IBAction func copyWith(_ sender: Any? = nil) {
        let rawAttributedText: NSAttributedString = if textView.selectedRange.length > 1 {
            textView.attributedString().attributedSubstring(from: textView.selectedRange())
        } else {
            textView.attributedString()
        }
        let attributedText = rawAttributedText.trimmingCharacters(in: .whitespacesAndNewlines)

        let rtlStyle = NSMutableParagraphStyle()
        rtlStyle.baseWritingDirection = .rightToLeft
        rtlStyle.alignment = .right
        let rtlAttributes: [NSAttributedString.Key: Any] = [.paragraphStyle: rtlStyle]

        let combined = NSMutableAttributedString()
        combined.append(attributedText)
        combined.append(NSAttributedString(string: "\n\n", attributes: rtlAttributes))

        let citation = viewModel.getCopyCitation()
        if !citation.isEmpty {
            combined.append(NSAttributedString(string: citation, attributes: rtlAttributes))
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let rtfData = try? combined.data(
            from: NSRange(location: 0, length: combined.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pasteboard.setData(rtfData, forType: .rtf)
        }
        pasteboard.setString(combined.string, forType: .string)
    }

    // MARK: - State Management

    func clearUI() {
        textView.string.removeAll()
        sidebarVC?.cleanUpOutlineView()
        viewModel.cleanUpState()
        windowTitle = ""
        windowSubtitle = ""
        if splitVC?.currentMode != .narrator {
            setDefaultWindowTitle()
        }
    }

    // MARK: - Sidebar Helpers

    private var lastSelectedContentIdFromSidebar: Int?

    private func handleNavigationToContent(_ contentId: Int) {
        guard let sidebarVC else { return }

        if lastSelectedContentIdFromSidebar == contentId {
            lastSelectedContentIdFromSidebar = nil
            return
        }

        sidebarVC.enableDelegate = false
        Task {
            if let node = viewModel.tocViewModel.findNode(forContentId: contentId) {
                let path = viewModel.tocViewModel.pathToNode(node)
                await sidebarVC.selectNode(node, path: path)
            }
            await MainActor.run {
                sidebarVC.enableDelegate = true
            }
        }
    }

    private func collectExpandedNodeIDs() -> [Int] {
        guard let outlineView = sidebarVC?.outlineView else { return [] }
        var expandedIDs: [Int] = []
        func collectExpanded(item: Any?) {
            let childCount = outlineView.numberOfChildren(ofItem: item)
            for i in 0 ..< childCount {
                let child = outlineView.child(i, ofItem: item)
                if let node = child as? TOCNode {
                    if outlineView.isItemExpanded(child) {
                        expandedIDs.append(node.id)
                        collectExpanded(item: child)
                    }
                }
            }
        }
        collectExpanded(item: nil)
        return expandedIDs
    }
}

// MARK: - NavigationDelegate

extension IbarotTextVC {
    @IBAction func navigationPage(_ sender: Any) {
        let navVC = Navigation(nibName: "Navigation", bundle: nil)
        navVC.viewModel = viewModel

        if let button = sender as? NSButton {
            WindowController.showPopOver(sender: button, viewController: navVC)
        } else {
            navVC.popover = false
            presentAsSheet(navVC)
        }
    }

    func displayBook(
        _ book: BooksData,
        loadContent: Bool = true
    ) async throws {
        do {
            try await viewModel.connectBookWithBundleFallback(book)
            didChangeBook(book: book)
            loadContent
                ? viewModel.loadInitialContent()
                : viewModel.loadTOC(book: book)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await MainActor.run {
                ReusableFunc.showAlert(
                    title: DatabaseError.bookNotFound(book.id).localizedDescription,
                    message: error.localizedDescription,
                    style: .critical
                )
            }
        }
    }

    func handleDelegate(_ contentId: Int, fromResults: Bool = false) {
        guard currentBook != nil else {
            Task { @MainActor in
                textView?.string = "Konten tidak ditemukan"
            }
            return
        }

        viewModel.fetchContentById(contentId)
    }
}

// MARK: - SidebarDelegate

extension IbarotTextVC: SidebarDelegate {
    func didSelectItem(_ id: Int) {
        lastSelectedContentIdFromSidebar = id
        handleDelegate(id)
    }
}

// MARK: - LibraryDelegate

extension IbarotTextVC: LibraryDelegate {
    func didSelectBook(for book: BooksData, loadContent: Bool) async {
        if loadContent { viewModel.recordHistory = true }
        if viewModel.currentBook?.id == book.id { return }
        try? await displayBook(book, loadContent: loadContent)
    }
}

// MARK: - OptionSearchDelegate

extension IbarotTextVC: OptionSearchDelegate {
    func didSelectResult(for id: Int, highlightText: String, mode: SearchMode?, nearDistance: Int) async {
        if viewModel.currentContentId != id { handleDelegate(id) }
        await textDelegate?.highlightAndScrollToText(highlightText, mode: mode, nearDistance: nearDistance)
    }
}

// MARK: - Author Mode

extension IbarotTextVC {
    func setRowiDisplayMode() {
        guard var state = splitVC?.currentState else { return }
        state.edit { $0.authorDisplayMode = .bookContent }
    }

    func setAuthorRowiDisplay(rowi: Rowi) {
        var state = splitVC?.currentState ?? ReaderState()
        state.edit {
            $0.currentRowi = rowi
            $0.authorDisplayMode = .rowiInfo
        }
        #if DEBUG
        print("Author mode: display mode (\(String(describing: state.authorDisplayMode)))")
        #endif
    }
}

// MARK: - TarjamahBDelegate

extension IbarotTextVC: TarjamahBDelegate {
    func didSelectRowi(rowi: Rowi) {
        viewModel.currentBook = nil
        sidebarVC?.cleanUpOutlineView()
        setAuthorRowiDisplay(rowi: rowi)
    }

    func didSelect(tarjamahB: TarjamahMen, query: String?) async {
        guard let bookData = LibraryDataManager.shared.getBook([tarjamahB.bk]).first else { return }

        if viewModel.currentBook?.id != bookData.id {
            try? await displayBook(bookData)
            try? viewModel.bookConnection.connect(archive: bookData.archive)
        }

        guard let content = viewModel.getContent(
            bkId: tarjamahB.bk,
            contentId: tarjamahB.id
        ) else {
            #if DEBUG
            print("unable to get content from tarjamahB")
            #endif
            return
        }

        viewModel.updateContentState(with: content)
        setRowiDisplayMode()

        try? await Task.sleep(nanoseconds: 300_000_000)
        if let query {
            await textDelegate?.highlightAndScrollToText(query.normalizeArabic(true), mode: .phrase, nearDistance: 10)
        }
    }
}

// MARK: - ReaderStateComponent

extension IbarotTextVC: ReaderStateComponent {
    func updateState(_ state: inout ReaderState) {
        state.selectedRange = textView.selectedRange()

        if let scrollView = textView.enclosingScrollView {
            state.scrollPosition = scrollView.documentVisibleRect.origin
        }

        if let sidebarVC {
            state.expandedNodeIDs = collectExpandedNodeIDs()
            state.sidebarScrollPosition = sidebarVC.scrollView.documentVisibleRect.origin
        }

        viewModel.updateState(&state)
    }

    func restore(from state: ReaderState) {
        guard state.hasContent, let book = state.currentBook
        else { clearUI(); return }

        try? viewModel.bookConnection.connect(archive: book.archive)

        if AppConfig.isUsingBundleMode,
           !BookArchiveIntegrator.shared.isBookIntegrated(book)
        {
            viewModel.currentBook = nil
            return
        }

        Task { [weak self] in
            guard let self else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }

                viewModel.restore(from: state)

                if let range = state.selectedRange {
                    textView.setSelectedRange(range)
                    view.window?.makeFirstResponder(textView)
                }

                libraryVC?.dataVM.viewModel.selectedBookName = book.book
            }

            if let query = state.searchQuery {
                let mode = state.searchModeRaw.flatMap { SearchMode(rawValue: $0) }
                let nearDistance = state.searchNearDistance ?? 10
                await textDelegate?.highlightAndScrollToText(query, mode: mode, nearDistance: nearDistance)
            }

            if let scrollPos = state.scrollPosition {
                await textDelegate?.scrollTo(scrollPos)
            }
        }
    }

    func cleanUpState() {
        clearUI()
        var newState = ReaderState()
        newState.isSidebarCollapsed = splitVC?.sidebarItem.isCollapsed ?? false
        splitVC?.currentState = newState
    }
}
