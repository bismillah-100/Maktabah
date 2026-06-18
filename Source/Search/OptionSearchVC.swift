//
//  OptionSearchVC.swift
//  maktab
//
//  Created by MacBook on 03/12/25.
//

import Cocoa
import Combine

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

    /// Menu Item Copy
    lazy var copyMenuItem: NSMenuItem = {
       let item = NSMenuItem()
        item.title = String(localized: "Copy")
        item.action = #selector(copy(_:))
        item.target = self
        return item
    }()

    lazy var viewModel: SearchViewModel = {
        .init()
    }()

    var results: [SearchResultItem] {
        viewModel.results
    }

    static var query: String = .init()

    var searchText: String = .init() {
        didSet {
            Self.query = searchText
            viewModel.query = searchText
        }
    }

    weak var delegate: LibraryDelegate?
    weak var itemDelegate: OptionSearchDelegate?
    weak var libraryViewManager: LibraryViewManager?

    var bkId: String = "" {
        didSet { viewModel.targetBookId = bkId }
    }
    var onSelectedItem: ((Int, String) -> Void)?
    var onCleanUp: (() -> Void)?

    var compactConfigured: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var resultsLoadingTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        resetProgressBar()
        searchField.focusRingType = .none
        searchField.recentsAutosaveName = "SearchInSelectedBooks"
        searchField.delegate = self
        tableView.userInterfaceLayoutDirection = .leftToRight
        ReusableFunc.setupSearchField(searchField)
        if #available(macOS 26.0, *) {
            progressTable.controlSize = .small
            progressRows.controlSize = .small
            optionsSegment.borderShape = .capsule
            let btn = [
                cleanUpButton, startButton, stopButton, insertNewResults,
                displayResults,
            ]
            btn.forEach { button in
                button?.borderShape = .capsule
            }
        } else {
            progressTable.controlSize = .regular
            progressRows.controlSize = .regular
            // Fallback on earlier versions
        }

        tableView.menu = NSMenu()
        tableView.menu?.addItem(copyMenuItem)
        tableView.menu?.delegate = self

        tableView.allowsMultipleSelection = true

        setupViewModelCallbacks()
        bindViewModelPublishers()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if viewModel.state == .loaded { return }
        setupUI()
    }

    private func setupViewModelCallbacks() {
        viewModel.searchDidReceiveResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                let newCount = viewModel.results.count
                if newCount > tableView.numberOfRows {
                    let indexSet = IndexSet(tableView.numberOfRows..<newCount)
                    tableView.insertRows(at: indexSet)
                }
            }
            .store(in: &cancellables)

        viewModel.searchProgressDidUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progressTable.doubleValue = Double(progress.completed)
            }
            .store(in: &cancellables)

        viewModel.searchDidComplete
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                updateStartButton(state: .off)
                resetProgressBar()
            }
            .store(in: &cancellables)

        viewModel.$state
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let loaded = state == .loaded
                loaded
                    ? resetIndeterminateProgress(loaded)
                    : setupUI()
            }
            .store(in: &cancellables)
    }

    private func setupUI() {
        setupIndeterminateProgress()
        viewModel.loadLibraryDataForDisplay(libraryViewManager: libraryViewManager) { [weak self] in
            self?.resetIndeterminateProgress(true)
        }
    }

    func compactButton() {
        if compactConfigured { return }
        guard let stackView = optionsSegment
            .superview as? NSStackView
        else { return }

        stackView.spacing = 4
        helpButton.isHidden = true
        searchField.placeholderString = "searchInThisBook".localized
        if let ismKitabColumn {
            tableView.removeTableColumn(ismKitabColumn)
        }
        tableView.sizeToFit()
        compactConfigured = true
    }

    private func bindViewModelPublishers() {
        viewModel.searchDidInitialize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] total in
                guard let self else { return }
                updateStartButton(systemSymbolName: "pause.fill", state: .on)

                progressTable.maxValue = Double(total)
                resetIndeterminateProgress(!bkId.isEmpty)
                progressTable.maxValue = 1
                progressTable.doubleValue = 0
                progressRows.isHidden = false
                progressRows.maxValue = 1
                progressRows.doubleValue = 0

                tableView.reloadData()
                tableView.sortDescriptors.removeAll()
            }
            .store(in: &cancellables)

        viewModel.searchDidReceiveResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                let prevCount = tableView.numberOfRows
                progressRows.doubleValue = progressRows.maxValue
                let newCount = viewModel.results.count
                if newCount > prevCount {
                    tableView.insertRows(at: IndexSet(prevCount..<newCount))
                }
            }
            .store(in: &cancellables)

        viewModel.searchProgressDidUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self else { return }
                progressTable.maxValue = Double(progress.total)
                progressTable.doubleValue = Double(progress.completed)
            }
            .store(in: &cancellables)

        viewModel.rowProgressDidUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self else { return }
                progressRows.maxValue = Double(progress.total)
                progressRows.doubleValue = Double(progress.completed)
            }
            .store(in: &cancellables)

        viewModel.searchDidComplete
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                progressTable.doubleValue = progressTable.maxValue
                progressRows.doubleValue = progressRows.maxValue
                updateStartButton(state: .off)
                resetProgressBar()
            }
            .store(in: &cancellables)
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
        viewModel.clearResults()
        tableView.removeRows(
            at: IndexSet(
                integersIn: 0..<tableView.numberOfRows
            )
        )
        tableView.sortDescriptors.removeAll()
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

    private func startSearchEngine() {
        if let lvm = libraryViewManager {
            viewModel.setSelectedBooks(lvm.viewModel.selectedBookIds)
        } else if !bkId.isEmpty {
            viewModel.setTargetBook(bkId)
        }

        viewModel.startSearch()
    }

    func resetProgressBar() {
        progressTable.isHidden = true
        progressRows.isHidden = true
        progressTable.doubleValue = 0
        progressRows.doubleValue = 0
    }

    func setupIndeterminateProgress() {
        progressTable.isIndeterminate = true
        progressTable.startAnimation(nil)
        progressTable.isHidden = false
    }

    func resetIndeterminateProgress(_ hide: Bool) {
        progressTable.stopAnimation(nil)
        progressTable.isIndeterminate = false
        progressTable.isHidden = hide
    }

    @IBAction func startSearch(_ sender: Any) {
            if searchText.isEmpty || (compactConfigured && bkId.isEmpty) { return }
            ReusableFunc.updateBuiltInRecents(with: searchText, in: searchField)

            let isPaused = viewModel.isPaused
            let isRunning = viewModel.isSearching

            if !isRunning, !isPaused {
                setupIndeterminateProgress()
            }

            startSearchEngine()

            if isPaused {
                updateStartButton(systemSymbolName: "pause.fill", state: .on)
            } else {
                updateStartButton(state: .on)
            }
        }

    @IBAction func stopSearch(_ sender: Any?) {
        viewModel.stopSearch()
        startButton.state = .off
        startButton.image = NSImage(
            systemSymbolName: "play.fill",
            accessibilityDescription: .none
        )
        resetProgressBar()
        resultsLoadingTask?.cancel()
    }

    @IBAction func optionsSegmentDidCange(_ sender: NSSegmentedControl) {
        viewModel.setSearchModeFromSegment(sender.selectedSegment)
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

    @IBAction func copy(_ sender: Any?) {
        ReusableFunc.copyResults(results, tableView: tableView)
    }

    deinit {
        #if DEBUG
        print("deinit OptionSearchVC")
        #endif
        cancellables.removeAll()
        resultsLoadingTask?.cancel()
        resultsLoadingTask = nil
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

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sd = tableView.sortDescriptors.first, let sdKey = sd.key,
              let key = SearchSortKey(rawValue: sdKey) else { return }
        viewModel.sortResults(by: key, ascending: sd.ascending)
        tableView.reloadData()
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
    func didSelectItem(_ row: Int) async {
        let book = results[row]

        guard let bookData = viewModel.resolveBook(from: book) else {
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
        viewModel.clearResults()
        tableView.reloadData()
        stopSearch(nil)
        resultsLoadingTask?.cancel()

        guard !savedResults.isEmpty else { return }

        searchField.stringValue = savedResults.first?.query ?? ""
        searchText = searchField.stringValue

        resultsLoadingTask = viewModel.loadSavedResults(
            savedResults,
            onProgress: { [weak self] total in
                self?.progressTable.isHidden = false
                self?.progressTable.maxValue = total
            },
            onInsert: { [weak self] prev, newCount in
                guard let self else { return }
                progressTable.doubleValue += Double(newCount - prev)
                tableView.insertRows(at: IndexSet(prev..<newCount))
            },
            onFinish: { [weak self] in
                guard let self else { return }
                progressTable.doubleValue = progressTable.maxValue
                Task {
                    try? await Task.sleep(nanoseconds: 955_000_000)
                    self.resetProgressBar()
                }
            }
        )
    }
}

extension OptionSearchVC: ReaderStateComponent {
    func updateState(_ state: inout ReaderState) {
        viewModel.updateState(&state)
    }

    func restore(from state: ReaderState) {
        guard let savedResults = state.searchResults,
              !savedResults.isEmpty else { return }

        viewModel.restore(from: state)

        tableView.reloadData()
        searchField.stringValue = viewModel.query
        searchText = viewModel.query
    }

    func cleanUpState() {
        viewModel.cleanUpState()
        searchField.stringValue = ""
        searchText = ""
        tableView.reloadData()
    }
}


extension OptionSearchVC: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let clickedRow = tableView.clickedRow
        copyMenuItem.isHidden = clickedRow < 0
    }
}
