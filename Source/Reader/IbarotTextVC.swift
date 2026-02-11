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

    var currentBook: BooksData?
    var sidebarVC: SidebarVC?

    var currentPage: Int?
    var currentID: Int?
    var currentPart: Int?

    var windowTitle: String = "المكتبة الإسلامية" {
        didSet {
            view.window?.title = windowTitle
        }
    }

    var windowSubtitle: String = "لتيسر البحث العبارة" {
        didSet {
            view.window?.subtitle = windowSubtitle
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.title = windowTitle
        view.window?.subtitle = windowSubtitle

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

    func didChangeBook(book: BooksData) async throws {
        if currentBook?.id == book.id {
            throw (NSError(domain: "Book not chaned", code: 1))
        }

        if let sidebarVC {
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
        guard let currentBook else { return }
        LibraryDataManager.shared.loadBookInfo(currentBook.id) { [weak self] in
            let bookInf = BookInfo()
            bookInf.bookData = currentBook
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
        textView.showFindIndicator(for: range)  // Animasi indicator (opsional)
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
        do {
            try await didChangeBook(book: book)
            bookDB.connect(archive: book.archive)
            fetchInitialBook()
        } catch {
            return
        }
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

extension IbarotTextVC: TarjamahBDelegate {
    func didSelectRowi() {
        currentBook = nil
    }

    func didSelect(tarjamahB: TarjamahMen, query: String?) async {
        guard
            let bookData = LibraryDataManager
                .shared.getBook([tarjamahB.bk]).first
        else {
            return
        }

        do {
            try await didChangeBook(book: bookData)
            bookDB.connect(archive: bookData.archive)
        } catch {
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

        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run { [weak self] in
            if let query {
                self?.highlightAndScrollToText(query.normalizeArabic(true))
            }
        }
    }
}
