//
//  IbarotTextVC.swift
//  maktab
//
//  Created by MacBook on 07/12/25.
//

import Cocoa

class IbarotTextVC: NSViewController {
    @IBOutlet weak var textView: IbarotTextView!

    private let defaultFontSize: CGFloat = 18.0

    private var showHarakat: Bool {
        get {
            return UserDefaults.standard.textViewShowHarakat
        }
        set {
            UserDefaults.standard.textViewShowHarakat = newValue
        }
    }

    var bookDB: BookConnection = .init()

    var sidebarVC: SidebarVC?

    let defaultTitle: String = "المكتبة الإسلامية"
    let subtitle: String = "لتيسر البحث العبارة"

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

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        //        guard let window = view.window,
        //              let guide = window.contentLayoutGuide as? NSLayoutGuide
        //        else { return }
        //
        //        let ve = NSVisualEffectView()
        //        ve.material = .fullScreenUI
        //        ve.blendingMode = .withinWindow
        //        ve.state = .active
        //        ve.translatesAutoresizingMaskIntoConstraints = false
        //        view.addSubview(ve, positioned: .above, relativeTo: textView)
        //
        //        NSLayoutConstraint.activate([
        //            ve.topAnchor.constraint(equalTo: view.topAnchor),
        //            ve.bottomAnchor.constraint(equalTo: guide.topAnchor),
        //            ve.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        //            ve.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        //        ])
    }

    func restoreWindowTitleAfterModeSwitch(
        oldTitle: String,
        oldSubtitle: String
    ) {
        guard !windowTitle.isEmpty,
              !windowSubtitle.isEmpty
        else { return }

        guard oldTitle != defaultTitle,
              oldSubtitle != subtitle
        else { return }

        setDefaultWindowTitle()
    }

    fileprivate func setDefaultWindowTitle() {
        view.window?.title = defaultTitle
        view.window?.subtitle = subtitle
    }

    func didChangeBook(
        book: BooksData,
        loadSidebar: Bool = true
    ) {
        if let sidebarVC, loadSidebar {
            Task { @MainActor in
                await sidebarVC.reloadBook(book: book)
            }
        }

        currentBook = book
        updateWindowTitle(id: book.id)
    }

    func fetchInitialBook() {
        guard let id = currentBook?.id,
            let content = bookDB.getFirstContent(bkid: String(id))
        else {
            return
        }
        didChangePage(content: content)
    }

    @MainActor
    func updateWindowTitle(id: Int, part: Int? = nil, page: Int? = nil) {
        guard let currentBook else { return }
        if let page {
            currentPage = page
        } else {
            currentPage = nil
        }

        currentID = id

        let title = currentBook.book
        let muallif = DatabaseManager.shared.getAuthor(currentBook.muallif)

        if let page {
            let pageString = String(page)
            let pageArb = pageString.convertToArabicDigits()
            if let part {
                currentPart = part
                let partString = String(part)
                let partArb = partString.convertToArabicDigits()
                windowTitle = title
                windowSubtitle =
                    "\(muallif?.nama ?? "") ・ الصفحة \(pageArb) ・ الجزء \(partArb)"
            } else {
                windowTitle = title
                windowSubtitle = "\(muallif?.nama ?? "") ・ الصفحة \(pageArb)"
            }
        } else {
            windowTitle = title
            windowSubtitle = "\(muallif?.nama ?? "")"
        }
    }

    func applyFont(_ redraw: Bool) {
        if !redraw {
            let defaults = UserDefaults.standard

            var fontSize = CGFloat(defaults.textViewFontSize)

            if fontSize == 0 { fontSize = defaultFontSize }

            let fontName = defaults.textViewFontName

            if let font = NSFont(name: fontName, size: fontSize) {
                textView.font = font

                // Update semua teks yang ada
                if let textStorage = textView.textStorage {
                    let range = NSRange(location: 0, length: textStorage.length)
                    textStorage.addAttribute(.font, value: font, range: range)
                }
            }
        } else {
            refreshCurrentPage()
        }
    }

    func toggleHarakat(_ on: Bool) {
        showHarakat = on ? true : false
        refreshCurrentPage()
    }

    private func refreshCurrentPage() {
        guard let currentID, let currentBook,
            let content = bookDB.getContentByPage(
                bkid: "\(currentBook.id)",
                idNumber: currentID
            )
        else { return }

        textView.loadIbarotText(content.nash, color: NSColor.header)
    }

    func applyBackgroundColor(_ color: NSColor) {
        textView.backgroundColor = color
    }

    @IBAction func previousPage(_ sender: Any?) {
        guard let currentID, let currentBook,
            let content = bookDB.getPrevPage(
                from: currentBook,
                contentId: currentID
            )
        else {
            return
        }

        didChangePage(content: content)
        didNavigateToContent(content)
    }

    @IBAction func nextPage(_ sender: Any?) {
        guard let currentID, let currentBook,
            let content = bookDB.getNextPage(
                from: currentBook,
                contentId: currentID
            )
        else {
            return
        }

        didChangePage(content: content)
        didNavigateToContent(content)
    }

    func didChangePage(content: BookContent) {
        let id = content.id
        let nash = content.nash
        let page = content.page
        let part = content.part

        textView.bkId = currentBook?.id
        textView.contentId = id
        textView.part = part
        textView.page = page

        Task { @MainActor in
            // Display content
            textView?.loadIbarotText(nash, color: NSColor.header)

            // Scroll to top
            textView?.scrollToBeginningOfDocument(nil)

            updateWindowTitle(id: id, part: part, page: page)
        }
    }

    @IBAction func bookInfo(_ sender: Any) {
        let dm = LibraryDataManager.shared
        guard let currentBook else { return }
        guard
            let bookOnLibrary = dm.getBook(
                [currentBook.id]).first
        else { return }

        self.currentBook = bookOnLibrary

        dm.loadBookInfo(bookOnLibrary.id) { [weak self] in
            let bookInf = BookInfo()
            bookInf.bookData = bookOnLibrary
            if let button = sender as? NSButton {
                WindowController.showPopOver(
                    sender: button,
                    viewController: bookInf
                )
            } else {
                bookInf.popOver = false
                self?.presentAsSheet(bookInf)
            }
        }
    }

    func copyWith() {
        guard let currentBook,
            let window = view.window
        else { return }

        // Ambil attributed string dari textView
        let attributedText = textView.attributedString()

        // Buat tambahan footer dengan style default (plain)
        let footer =
            "\n\n\n__________\n" + currentBook.book + " " + window.title + " - "
            + window.subtitle
        let footerAttr = NSAttributedString(string: footer)

        // Gabungkan attributed text + footer
        let combined = NSMutableAttributedString(
            attributedString: attributedText
        )
        combined.append(footerAttr)

        // Dapatkan pasteboard umum
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Tulis attributed string ke pasteboard sebagai RTF (supaya style ikut)
        if let rtfData = try? combined.data(
            from: NSRange(location: 0, length: combined.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtf
            ]
        ) {
            pasteboard.setData(rtfData, forType: .rtf)
        }

        // Optional: juga tulis plain text untuk fallback
        pasteboard.setString(combined.string, forType: .string)
    }
}

extension IbarotTextVC {
    /// Get SplitVC dari hierarchy
    private var splitVC: SplitVC? {
        // Navigate up the view controller hierarchy
        var current: NSViewController? = self
        while let parent = current?.parent {
            if let unified = parent as? SplitVC {
                return unified
            }
            current = parent
        }
        return nil
    }

    // MARK: - State Properties (via SplitVC)

    /// Current book - reads/writes dari SplitVC state
    var currentBook: BooksData? {
        get {
            splitVC?.currentState.currentBook
        }
        set {
            if var state = splitVC?.currentState {
                state.currentBook = newValue
                splitVC?.currentState = state
            }
        }
    }

    /// Current page
    var currentPage: Int? {
        get {
            splitVC?.currentState.currentPage
        }
        set {
            if var state = splitVC?.currentState {
                state.currentPage = newValue
                splitVC?.currentState = state
            }
        }
    }

    /// Current ID
    var currentID: Int? {
        get {
            splitVC?.currentState.currentID
        }
        set {
            if var state = splitVC?.currentState {
                state.currentID = newValue
                splitVC?.currentState = state
            }
        }
    }

    /// Current part
    var currentPart: Int? {
        get {
            splitVC?.currentState.currentPart
        }
        set {
            if var state = splitVC?.currentState {
                state.currentPart = newValue
                splitVC?.currentState = state
            }
        }
    }

    // MARK: - State Operations

    /// Clear state (untuk close book)
    func clearUI() {
        textView.bkId = nil
        textView.page = nil
        textView.part = nil
        textView.contentId = nil
        textView.string.removeAll()
        sidebarVC?.cleanUpOutlineView()
        windowTitle = ""
        windowSubtitle = ""
        if splitVC?.currentMode != .author {
            setDefaultWindowTitle()
        }
    }
}

extension IbarotTextVC: NavigationDelegate {
    @IBAction func navigationPage(_ sender: Any) {
        let navVC = Navigation(nibName: "Navigation", bundle: nil)
        navVC.bookDB = bookDB
        navVC.currentBook = currentBook
        navVC.delegate = self

        if let button = sender as? NSButton {
            WindowController.showPopOver(sender: button, viewController: navVC)
        } else {
            navVC.popover = false
            presentAsSheet(navVC)
        }

        if let currentPage {
            navVC.currentPage = currentPage
        }

        navVC.currentJuz = currentPart ?? 0
    }

    func sliderDidNavigateInto(content: BookContent) {
        didChangePage(content: content)
        didNavigateToContent(content)
    }

    func didNavigateToContent(_ content: BookContent) {
        // Update sidebar selection jika perlu
        if let sidebarVC {
            sidebarVC.enableDelegate = false
            Task.detached {
                _ = await sidebarVC.loadingTask?.value
                if let node = await sidebarVC.findNode(forPage: content.id) {
                    await sidebarVC.selectNode(withId: node.id)
                }
                await MainActor.run {
                    sidebarVC.enableDelegate = true
                }
            }
        }
    }

    func handleDelegate(_ contentId: Int, fromResults: Bool = false) {
        guard let currentBook,
            let content = bookDB.getContent(
                bkid: "\(currentBook.id)",
                contentId: contentId
            )
        else {
            Task { @MainActor in
                textView?.string = "Konten tidak ditemukan"
            }
            return
        }
        didChangePage(content: content)
        if fromResults {
            Task {
                didNavigateToContent(content)
            }
        }
    }

    @MainActor
    func highlighAndScrollToAnns(_ ann: Annotation) {
        let diacritics = TextViewState.shared.showHarakat
        let range = diacritics ? ann.rangeDiacritics : ann.range

        textView.scrollRangeToVisible(range)
        Task { [weak self] in
            await Task.yield()
            await Task.yield()
            self?.textView.showFindIndicator(for: range)
        }
    }

    @MainActor
    func highlightAndScrollToText(_ searchText: String) {
        guard let textStorage = textView.textStorage else { return }

        let fullText = textStorage.string
            .normalizeArabic(false)
            .replacingOccurrences(of: "\\n", with: "\n")

        let lowerFullText = fullText

        let searchTerms =
            searchText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.normalizeArabic(true) }

        guard !searchTerms.isEmpty else { return }

        // Warna berbeda untuk tiap term (opsional)
        let colors: [NSColor] = [
            .highlightText,
            NSColor.magenta.withAlphaComponent(0.4),
            NSColor.systemPink.withAlphaComponent(0.4),
            NSColor.systemPurple.withAlphaComponent(0.4),
            NSColor.systemIndigo.withAlphaComponent(0.4),
        ]

        var firstMatchRange: NSRange?

        for (index, searchTerm) in searchTerms.enumerated() {
            let color = colors[index % colors.count]
            var searchRange = lowerFullText.startIndex..<lowerFullText.endIndex

            while let found = lowerFullText.range(
                of: searchTerm,
                options: [.diacriticInsensitive],
                range: searchRange
            ) {
                let nsRange = NSRange(found, in: fullText)

                if firstMatchRange == nil {
                    firstMatchRange = nsRange
                }

                var hasBackground = false
                textStorage.enumerateAttribute(
                    .backgroundColor,
                    in: nsRange,
                    options: []
                ) { value, _, stop in
                    if value != nil {
                        hasBackground = true
                        stop.pointee = true
                    }
                }

                if !hasBackground {
                    textStorage.addAttribute(
                        .backgroundColor,
                        value: color,
                        range: nsRange
                    )
                }

                searchRange = found.upperBound..<lowerFullText.endIndex
            }
        }

        if let firstRange = firstMatchRange {
            Task { @MainActor [weak self, firstRange] in
                self?.textView.scrollRangeToVisible(firstRange)
                await Task.yield()
                self?.textView.showFindIndicator(for: firstRange)
            }
        }
    }
}

extension IbarotTextVC: SidebarDelegate {
    func didSelectItem(_ id: Int) {
        handleDelegate(id)
    }
}

extension IbarotTextVC: LibraryDelegate {
    func didSelectBook(for book: BooksData) async {
        if currentBook?.id != book.id {
            didChangeBook(book: book)
        }
        bookDB.connect(archive: book.archive)
        fetchInitialBook()
    }
}

extension IbarotTextVC: OptionSearchDelegate {
    func didSelectResult(for id: Int, highlightText: String) async {
        handleDelegate(id, fromResults: true)
        await MainActor.run {
            highlightAndScrollToText(highlightText)
        }
    }
}

// MARK: - Author Mode Specific

extension IbarotTextVC {

    /// Current rowi (untuk Author mode)
    var currentRowi: Rowi? {
        get {
            splitVC?.currentState.currentRowi
        }
        set {
            guard var state = splitVC?.currentState else { return }
            state.edit {
                $0.currentRowi = newValue
            }
        }
    }

    func setRowiDisplayMode() {
        guard var state = splitVC?.currentState else { return }
        state.edit {
            $0.authorDisplayMode = .bookContent
        }
    }

    /// Set state untuk Rowi button display (dipanggil dari RowiResultsVC.buttonDidClick)
    func setAuthorRowiDisplay(rowi: Rowi) {
        var state = splitVC?.currentState ?? ReaderState()
        state.edit{
            $0.currentRowi = rowi
            $0.authorDisplayMode = .rowiInfo
        }

        #if DEBUG
            print("Author mode: display mode (\(String(describing: state.authorDisplayMode) ))")
        #endif
    }
}

extension IbarotTextVC: TarjamahBDelegate {
    func didSelectRowi(rowi: Rowi) {
        currentBook = nil
        textView.bkId = nil
        sidebarVC?.cleanUpOutlineView()
        setAuthorRowiDisplay(rowi: rowi)
    }

    func didSelect(tarjamahB: TarjamahMen, query: String?) async {
        guard
            let bookData = LibraryDataManager
                .shared.getBook([tarjamahB.bk]).first
        else {
            return
        }

        if currentBook?.id != bookData.id {
            didChangeBook(book: bookData)
            bookDB.connect(archive: bookData.archive)
        } else {
            return
        }

        guard
            let content = bookDB.getContentByPage(
                bkid: "\(tarjamahB.bk)",
                idNumber: tarjamahB.id
            )
        else {
            #if DEBUG
                print("unable to get content from tarjamahB")
            #endif
            return
        }

        didChangePage(content: content)
        didNavigateToContent(content)
        setRowiDisplayMode()

        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run { [weak self] in
            if let query {
                self?.highlightAndScrollToText(query.normalizeArabic(true))
            }
        }
    }
}

extension IbarotTextVC: ReaderStateComponent {
    // MARK: - ReaderStateComponent

    func updateState(_ state: inout ReaderState) {
        // Update data buku
        state.edit {
             $0.currentBook = currentBook
             $0.currentPage = currentPage
             $0.currentID = currentID
             $0.currentPart = currentPart
             $0.currentRowi = currentRowi
             $0.selectedRange = textView.selectedRange()
        }

        // Update UI (Scroll & Selection)
        if let scrollView = textView.enclosingScrollView {
            state.scrollPosition = scrollView.documentVisibleRect.origin
        }

        // Update Sidebar/TOC
        if let sidebarVC = sidebarVC {
            state.expandedNodeIDs = collectExpandedNodeIDs()
            state.sidebarScrollPosition = sidebarVC.scrollView.documentVisibleRect.origin
        }
    }

    func restore(from state: ReaderState) {
        guard state.hasContent else {
            clearUI()
            return
        }

        // 1. Load data buku & halaman
        if let book = state.currentBook {
            bookDB.connect(archive: book.archive)
            if currentBook?.id != book.id {
                didChangeBook(book: book)
            }

            if let id = state.currentID,
                let content = bookDB.getContent(bkid: String(book.id), contentId: id)
            {
                didChangePage(content: content)

                // 2. Restore Sidebar (Async)
                Task { @MainActor in
                    if let sidebarVC = sidebarVC {
                        await sidebarVC.reloadBook(book: book)
                        didNavigateToContent(content)

                        // Restore expanded items & scroll sidebar
                        sidebarVC.enableDelegate = false
                        for nodeID in state.expandedNodeIDs {
                            if let node = sidebarVC.findNodeById(nodeID) {
                                sidebarVC.outlineView.expandItem(node)
                            }
                        }
                        if let pos = state.sidebarScrollPosition {
                            sidebarVC.scrollView.documentView?.scroll(pos)
                        }
                        sidebarVC.enableDelegate = true
                    }

                    // 3. Restore Main Text Scroll & Selection
                    if let scrollPos = state.scrollPosition {
                        textView.enclosingScrollView?.documentView?.scroll(scrollPos)
                    }

                    if let range = state.selectedRange {
                        textView.setSelectedRange(range)
                        view.window?.makeFirstResponder(textView)
                    }

                    // 4. Spesifik untuk Search Mode highlight
                    if let query = state.searchQuery {
                        highlightAndScrollToText(query)
                    }
                }
            }
        }
    }

    func cleanUpState() {
        clearUI()
        var newState = ReaderState()
        let collapsed = splitVC?.sidebarItem.isCollapsed ?? false
        newState.isSidebarCollapsed = collapsed
        splitVC?.currentState = newState
    }

    // MARK: - Sidebar Helpers
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
