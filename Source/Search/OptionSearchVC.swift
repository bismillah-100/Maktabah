//
//  OptionSearchVC.swift
//  maktab
//
//  Created by MacBook on 03/12/25.
//

import Cocoa

class OptionSearchVC: NSViewController {

    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var progressTable: NSProgressIndicator!
    @IBOutlet weak var progressRows: NSProgressIndicator!
    @IBOutlet weak var searchField: DSFSearchField!
    @IBOutlet weak var startButton: NSButton!
    @IBOutlet weak var stopButton: NSButton!
    @IBOutlet weak var optionsSegment: NSSegmentedControl!
    @IBOutlet weak var helpButton: NSButton!
    @IBOutlet weak var cleanUpButton: NSButton!
    @IBOutlet weak var ismKitabColumn: NSTableColumn!
    @IBOutlet weak var displayResults: NSButton!
    @IBOutlet weak var insertNewResults: NSButton!

    // Array penampung hasil
    var results: [SearchResultItem] = []

    var searchText: String = .init() {
        didSet {
            if searchSplitVC != nil {
                SearchSplitView.query = searchText
            }
        }
    }

    var searchOptions: SearchMode = .phrase

    let bkConn: BookConnection = .init()

    let ldm: LibraryDataManager = .shared

    weak var delegate: LibraryDelegate?
    weak var itemDelegate: OptionSearchDelegate?
    weak var libraryViewManager: LibraryViewManager?
    weak var searchSplitVC: SearchSplitView?

    var bkId: String = ""
    var onSelectedItem: ((Int, String) -> Void)?
    var onCleanUp: (() -> Void)?

    var compactConfigured: Bool = false

    // Mengganti DispatchWorkItem dengan Task untuk konsistensi konkurensi
    private var resultsLoadingTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        resetProgressBar()
        searchField.focusRingType = .none
        searchField.recentsAutosaveName = "SearchInSelectedBooks"
        searchField.delegate = self
        tableView.userInterfaceLayoutDirection = .leftToRight
        if #available(macOS 26.0, *) {  // PERINGATAN: Ganti 26.0 dengan versi macOS yang aktual
            optionsSegment.borderShape = .circle
            let btn = [
                cleanUpButton, startButton, stopButton, insertNewResults,
                displayResults,
            ]
            btn.forEach { button in
                button?.borderShape = .circle
            }
        } else {
            // Fallback on earlier versions
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task.detached {
            await LibraryDataManager.shared.coordinator.waitUntilLoaded()
            await LibraryDataManager.shared.buildArchive()
        }
    }

    func compactButton() {
        if compactConfigured { return }
        helpButton.isHidden = true
        cleanUpButton.title.removeAll()
        cleanUpButton.image = NSImage(
            systemSymbolName: "xmark.square.fill",
            accessibilityDescription: nil
        )
        optionsSegment.setLabel("", forSegment: 0)
        optionsSegment.setLabel("", forSegment: 1)
        optionsSegment.setImage(
            NSImage(
                systemSymbolName: "text.viewfinder",
                accessibilityDescription: nil
            ),
            forSegment: 0
        )
        optionsSegment.setImage(
            NSImage(
                systemSymbolName: "a.magnify",
                accessibilityDescription: nil
            ),
            forSegment: 1
        )
        optionsSegment.setWidth(26, forSegment: 0)
        optionsSegment.setWidth(26, forSegment: 1)
        let f = searchField.frame
        searchField.frame = NSRect(
            x: f.origin.x,
            y: f.origin.y,
            width: 128,
            height: f.height
        )
        searchField.placeholderString = "searchInThisBook".localized
        if let ismKitabColumn {
            tableView.removeTableColumn(ismKitabColumn)
        }
        tableView.sizeToFit()
        compactConfigured = true
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        ReusableFunc.registerNib(
            tableView: tableView,
            nibName: .resultNib,  // CellIViewIdentifier.resultNib
            cellIdentifier: .resultAndOutlineChild  // CellIViewIdentifier.resultAndOutlineChild
        )
    }

    @IBAction func saveResults(_ sender: NSButton) {
        let sr = ResultWriter()
        sr.query = searchField.stringValue
        let popover = NSPopover()
        popover.contentViewController = sr
        popover.behavior = .semitransient
        popover.show(
            relativeTo: sender.bounds,
            of: sender,
            preferredEdge: .minY
        )
        sr.results = results
    }

    @IBAction func cleanUp(_ sender: Any) {
        stopSearch(sender)
        results.removeAll()
        tableView.removeRows(
            at: IndexSet(
                integersIn: 0..<tableView.numberOfRows
            )
        )
        onCleanUp?()
        if !bkId.isEmpty {
            libraryViewManager = nil
        }
    }

    @IBAction func displayBookmark(_ sender: Any?) {
        let bm = SavedResults()
        bm.delegate = self
        let window = NSWindow(contentViewController: bm)
        window.setFrameAutosaveName("searchResultsSheetWindowFrame")
        window.isReleasedWhenClosed = true
        view.window?.beginSheet(window)
    }

    @MainActor
    func updateStartButton(
        systemSymbolName: String = "play.fill",
        state: NSControl.StateValue
    ) {
        startButton.image = NSImage(
            systemSymbolName: systemSymbolName,
            accessibilityDescription: .none
        )
        startButton.state = state
    }

    func startSearchEngine(
        currentMode: SearchMode,
        isPaused: Bool,
        isRunning: Bool
    ) async {
        if isPaused {
            ldm.searchEngine.resume()
            return
        }

        if isRunning {
            ldm.searchEngine.pause()
            return
        }

        if !isRunning {
            // Reset UI
            await MainActor.run {
                self.startButton.image = NSImage(
                    systemSymbolName: "pause.fill",
                    accessibilityDescription: .none
                )
                self.results.removeAll()
                self.tableView.reloadData()
            }

            let tableToScan: Set<String>

            if let libraryViewManager {
                tableToScan = ldm.getCheckedTables(
                    libraryViewManager.displayedCategories
                )
            } else {
                tableToScan = [bkId]
            }

            ldm.performSearch(
                tableToScan: tableToScan,
                query: searchText,
                mode: currentMode,
                onInitialize: { [weak self] totalTables in
                    guard let self = self else { return }

                    // Set maxValue dan tampilkan HANYA progressTable
                    progressTable.maxValue = Double(totalTables)
                    progressTable.doubleValue = 0
                    progressTable.isHidden = false

                    #if DEBUG
                        print("📊 Total Tables: \(totalTables)")
                    #endif
                },
                onTableProgress: { [weak self] completedTables in
                    guard let self = self else { return }

                    // Update progress
                    progressTable.doubleValue = Double(completedTables)
                    #if DEBUG
                        print(
                            "📈 Progress: \(completedTables)/\(Int(progressTable.maxValue))"
                        )
                    #endif
                },
                onRowProgress: {
                    [weak self] archiveId, tableName, current, total in
                    guard let self = self else { return }
                    // ✅ Update row progress
                    if progressRows.isHidden {
                        progressRows.isHidden = false
                        // labelCurrentTable.isHidden = false
                    }

                    progressRows.maxValue = Double(total)
                    progressRows.doubleValue = Double(current)

                    // ✅ Format info tabel yang sedang di-scan
                    // let bookId = Int(tableName.dropFirst()) ?? 0
                    // let bookTitle = ldm.booksById[bookId]?.book ?? tableName
                    // labelCurrentTable.stringValue = "Scanning: \(bookTitle) (\(current)/\(total) rows)"

                    #if DEBUG
                        print(
                            "🔍 Row Progress [\(tableName)]: \(current)/\(total)"
                        )
                    #endif
                },
                completion: { [weak self] item in
                    guard let self = self else { return }
                    // Jika performa buruk dengan banyak hasil, pertimbangkan pembaruan batch di sini
                    // Untuk saat ini, asumsikan pembaruan per item masih dapat diterima
                    results.append(item)
                    tableView.insertRows(
                        at: IndexSet(integer: results.count - 1)
                    )
                },
                onComplete: { [weak self] in
                    guard let self = self else { return }
                    ldm.searchEngine.stop()
                    progressTable.doubleValue = progressTable.maxValue
                    progressRows.doubleValue = progressRows.maxValue

                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        // Hapus penundaan Task.sleep yang tidak perlu
                        // try? await Task.sleep(nanoseconds: 955_000_000)
                        updateStartButton(state: .off)
                        resetProgressBar()
                        // labelCurrentTable.isHidden = true
                    }
                    #if DEBUG
                        print("🎉 Search Complete!")
                    #endif
                }
            )
        }
    }

    func resetProgressBar() {
        progressTable.isHidden = true
        progressRows.isHidden = true
        progressTable.doubleValue = 0
        progressRows.doubleValue = 0
    }

    @IBAction func startSearch(_ sender: Any) {
        if searchText.isEmpty || (compactConfigured && bkId.isEmpty) { return }
        ReusableFunc.updateBuiltInRecents(with: searchText, in: searchField)
        let isPaused = ldm.searchEngine.currentlyPaused()
        let isRunning = ldm.searchEngine.isRunning()

        if isPaused {
            updateStartButton(systemSymbolName: "pause.fill", state: .on)
        } else {
            updateStartButton(state: .on)
        }

        // Ambil mode dari computed property searchOptions
        Task.detached { [weak self, isPaused, isRunning] in
            guard let self else { return }
            await startSearchEngine(
                currentMode: searchOptions,
                isPaused: isPaused,
                isRunning: isRunning
            )
        }
    }

    @IBAction func stopSearch(_ sender: Any?) {
        ldm.searchEngine.stop()
        startButton.state = .off
        startButton.image = NSImage(
            systemSymbolName: "play.fill",
            accessibilityDescription: .none
        )
        resetProgressBar()
        resultsLoadingTask?.cancel()  // Batalkan task jika sedang berjalan
    }

    @IBAction func optionsSegmentDidCange(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 1 {
            searchOptions = .contains
        } else {
            searchOptions = .phrase
        }
    }

    @IBAction func searchFieldDidChange(_ sender: NSSearchField) {
        searchText = sender.stringValue
    }

    @IBAction func helpSearchOpt(_ sender: NSButton) {
        ReusableFunc.helpSearchOpt(sender)
    }

    @IBAction func performFindPanelAction(_ sender: Any) {
        searchField.becomeFirstResponder()
    }

    deinit {
        #if DEBUG
            print("deinit OptionSearchVC")
        #endif
        resultsLoadingTask?.cancel()  // Pastikan task dibatalkan saat deinit
    }
}

// MARK: - NSTableViewDataSource & Delegate
extension OptionSearchVC: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return results.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard
            let cell = tableView.makeView(
                withIdentifier: NSUserInterfaceItemIdentifier(
                    CellIViewIdentifier.resultAndOutlineChild.rawValue
                ),
                owner: self
            ) as? NSTableCellView
        else {
            return nil
        }

        let item = results[row]

        guard let identifier = tableColumn?.identifier else { return nil }

        cell.textField?.allowsExpansionToolTips = true
        cell.textField?.lineBreakMode = .byTruncatingTail
        cell.textField?.usesSingleLineMode = true
        cell.textField?.maximumNumberOfLines = 1

        if identifier.rawValue == "Book" {
            cell.textField?.stringValue = item.bookTitle
            return cell
        } else if identifier.rawValue == "Content" {
            cell.textField?.attributedStringValue = item.attributedText
            return cell
        } else if identifier.rawValue == "Page" {
            cell.textField?.stringValue = "\(item.page)"
            return cell
        } else if identifier.rawValue == "Part" {
            cell.textField?.stringValue = "\(item.part)"
            return cell
        }

        return nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else {
            #if DEBUG
                print("result out of range")
            #endif
            return
        }
        // didSelectItem sekarang adalah fungsi async di LibraryViewDelegate
        Task { await didSelectItem(row) }
        if !bkId.isEmpty {
            view.window?.performClose(nil)
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        24
    }

}

extension OptionSearchVC: NSSearchFieldDelegate {
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.insertLineBreak(_:)):
            startSearch(commandSelector)
            return true
        default: return false
        }
    }
}

extension OptionSearchVC: LibraryViewDelegate {
    func didSelectItem(_ row: Int) async {  // Menjadikan ini async sesuai protokol
        let book = results[row]

        let table: String

        if book.tableName.first == "b" {
            table = String(book.tableName.dropFirst())
        } else {
            table = book.tableName
        }

        guard let tableInt = Int(table) else {
            #if DEBUG
                print("error convert to int")
            #endif
            return
        }

        guard let bookData = ldm.booksById[tableInt] else {
            #if DEBUG
                print("bookData not cached")
            #endif
            return
        }

        // Penggunaan Task sudah benar di sini, tidak perlu Task.detached lagi
        await delegate?.didSelectBook(for: bookData)
        await itemDelegate?.didSelectResult(
            for: book.bookId,
            highlightText: searchText
        )
        onSelectedItem?(book.bookId, searchField.stringValue)
    }
}

extension OptionSearchVC: ResultsDelegate {
    func didSelect(savedResults: [SavedResultsItem]) {
        results.removeAll()
        tableView.reloadData()
        stopSearch(nil)

        resultsLoadingTask?.cancel()

        guard let firstResult = savedResults.first else { return }

        searchText = firstResult.query
        searchField.stringValue = firstResult.query

        resultsLoadingTask = Task.detached { [weak self] in
            guard let self else { return }

            await setupProgress(total: savedResults.count)

            let groupedResults = Dictionary(
                grouping: savedResults,
                by: \.archive
            )
            var buffer = ResultBuffer()

            for (archiveId, itemsInArchive) in groupedResults {
                guard !Task.isCancelled, let arc = Int(archiveId) else {
                    return
                }

                await bkConn.connect(archive: arc)

                for item in itemsInArchive {
                    guard !Task.isCancelled else { return }

                    if let result = await processItem(item) {
                        buffer.add(result)

                        if buffer.isFull {
                            await commitBuffer(&buffer)
                        }
                    }
                }
            }

            // Commit sisa
            if !buffer.isEmpty {
                await commitBuffer(&buffer)
            }

            await finishProgress()
        }
    }

    // MARK: - Helper Methods

    private func setupProgress(total: Int) async {
        await MainActor.run { [weak self] in
            self?.progressTable.isHidden = false
            self?.progressTable.maxValue = Double(total)
        }
    }

    private func processItem(_ item: SavedResultsItem) async
        -> SearchResultItem?
    {
        guard
            let bookContent = bkConn.getContent(
                bkid: item.tableName,
                contentId: item.bookId
            )
        else {
            return nil
        }

        let snippet = bookContent.nash.snippetAround(
            keywords: [item.query],
            contextLength: 60
        )
        let attribute = snippet.highlightedAttributedText(keywords: [item.query]
        )

        return SearchResultItem(
            archive: item.archive,
            tableName: item.tableName,
            bookId: item.bookId,
            bookTitle: item.bookTitle,
            page: bookContent.page,
            part: bookContent.part,
            attributedText: attribute
        )
    }

    private func commitBuffer(_ buffer: inout ResultBuffer) async {
        let items = buffer.flush()
        let startIndex = results.count

        await MainActor.run { [weak self, items] in
            guard let self else { return }
            results.append(contentsOf: items)

            let indexSet = IndexSet(startIndex..<self.results.count)
            progressTable.doubleValue += Double(items.count)
            tableView.insertRows(at: indexSet)
        }
    }

    private func finishProgress() async {
        await MainActor.run { [weak self] in
            self?.progressTable.doubleValue = self?.progressTable.maxValue ?? 0
        }

        try? await Task.sleep(nanoseconds: 955_000_000)

        await MainActor.run { [weak self] in
            self?.resetProgressBar()
        }
    }
}

// MARK: - Result Buffer Helper
private struct ResultBuffer {
    private var items: [SearchResultItem] = []
    private let batchSize = 10

    var isEmpty: Bool { items.isEmpty }
    var isFull: Bool { items.count >= batchSize }

    mutating func add(_ item: SearchResultItem) {
        items.append(item)
    }

    mutating func flush() -> [SearchResultItem] {
        let flushed = items
        items.removeAll(keepingCapacity: true)
        return flushed
    }
}
