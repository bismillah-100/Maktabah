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
    }

    // MARK: - Setup

    private func setupBindings() {
        textView.viewModel = viewModel
        // Bind content text changes
        viewModel.bind(viewModel.$contentText) { [weak self] text in
            guard let self, !text.isEmpty else { return }
            textView.loadIbarotText(
                text,
                color: NSColor.header,
                isMultiLanguage: viewModel.currentBook?.isMultiLanguage,
                isImported: viewModel.currentBook?.isImported ?? false
            )
        }

        // Bind window title changes
        viewModel.onWindowTitleChanged = { [weak self] title, subtitle in
            self?.windowTitle = title
            self?.windowSubtitle = subtitle
        }

        // Bind content changed callback
        viewModel.onContentChanged = { [weak self] content in
            guard let self else { return }
            handleNavigationToContent(content)
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
            guard let self = self, let sidebarView = self.sidebarVC?.view else { return }
            if isLoading {
                ReusableFunc.showProgressWindow(sidebarView)
            } else {
                ReusableFunc.closeProgressWindow(sidebarView)
            }
        }

        viewModel.tocViewModel.onTOCLoaded = { [weak self] nodes in
            self?.sidebarVC?.updateTOC(nodes)
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .libraryFolderChanged,
            object: nil,
            queue: .current
        ) { [weak self] _ in
            guard let self else { return }
            viewModel.cleanUpState()
            viewModel.tocViewModel.cleanUp()
        }

        NotificationCenter.default.addObserver(
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
        }
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

    var currentBook: BooksData? { viewModel.currentBook }

    var currentPage: Int? { viewModel.currentPage }

    var currentPart: Int? { viewModel.currentPart }

    /// Alias ke viewModel.bookConnection untuk backward compatibility dengan SidebarVC
    var bookDB: BookConnection { viewModel.bookConnection }

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
        } else {
            viewModel.refreshCurrentPage()
        }
    }

    func toggleHarakat(_ on: Bool) {
        viewModel.refreshCurrentPage()
    }

    func applyBackgroundColor(_ color: NSColor) {
        textView.backgroundColor = color
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
                self.presentAsSheet(bookInf)
            }
        }
    }

    @IBAction func copyWith(_ sender: Any? = nil) {
        let attributedText: NSAttributedString
        if textView.selectedRange.length > 1 {
            attributedText = textView.attributedString().attributedSubstring(from: textView.selectedRange())
        } else {
            attributedText = textView.attributedString()
        }

        let combined = NSMutableAttributedString(attributedString: attributedText)
        let formattedReference = viewModel.getCopyReference(for: "")
        combined.append(NSAttributedString(string: formattedReference.replacingOccurrences(of: "\n\n", with: "")))

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

    private func handleNavigationToContent(_ content: BookContent) {
        guard let sidebarVC else { return }
        
        if lastSelectedContentIdFromSidebar == content.id {
            lastSelectedContentIdFromSidebar = nil
            return
        }
        
        sidebarVC.enableDelegate = false
        Task {
            if let node = viewModel.tocViewModel.findNode(forContentId: content.id) {
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
            for i in 0..<childCount {
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

    func displayBook(_ book: BooksData) async throws {
        do {
            try await viewModel.connectBookWithBundleFallback(book)
            didChangeBook(book: book)
            viewModel.loadInitialContent()
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

    @MainActor
    func highlighAndScrollToAnns(_ ann: Annotation) {
        let range = textView.displayedRange(for: ann)
        textView.scrollRangeToVisible(range)
        Task { [weak self] in
            await Task.yield()
            await Task.yield()
            self?.textView.showFindIndicator(for: range)
        }
    }

    @MainActor
    func highlightAndScrollToText(_ searchText: String) {
        guard let range = textView.textStorage?.highlightSearchText(
            searchText: searchText,
            baseColor: .highlightText
        ) else { return }

        Task { [weak textView] in
            textView?.scrollRangeToVisible(range)
            await Task.yield()
            textView?.showFindIndicator(for: range)
        }
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
    func didSelectBook(for book: BooksData) async {
        if viewModel.currentBook?.id == book.id { return }
        try? await displayBook(book)
    }
}

// MARK: - OptionSearchDelegate

extension IbarotTextVC: OptionSearchDelegate {
    func didSelectResult(for id: Int, highlightText: String) async {
        handleDelegate(id, fromResults: true)
        DispatchQueue.main.async { [weak self] in
            self?.highlightAndScrollToText(highlightText)
        }
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
        await MainActor.run { [weak self] in
            if let query {
                self?.highlightAndScrollToText(query.normalizeArabic(true))
            }
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

        if let sidebarVC = sidebarVC {
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
           !BookArchiveIntegrator.shared.isBookIntegrated(book) {
            viewModel.currentBook = nil
            return
        } else {
        }

        Task { [weak self] in
            guard let self else { return }

            if viewModel.currentBook?.id != book.id {
                viewModel.restore(from: state)
            }

            await MainActor.run { [weak self] in
                guard let self else { return }

                if let range = state.selectedRange {
                    textView.setSelectedRange(range)
                    view.window?.makeFirstResponder(textView)
                }

                if let query = state.searchQuery {
                    highlightAndScrollToText(query)
                }

                libraryVC?.dataVM.viewModel.selectedBookName = book.book

                if let scrollPos = state.scrollPosition {
                    textView.enclosingScrollView?.documentView?.scroll(scrollPos)
                }
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
