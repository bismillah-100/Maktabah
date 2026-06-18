//
//  RowiResultsSplitVC.swift
//  maktab
//
//  Created by MacBook on 10/12/25.
//

import Cocoa

enum RowiMode {
    case sidebar
    case fullSearch
}

class RowiResultsVC: NSViewController {
    @IBOutlet weak var tilmidz: NSButton!
    @IBOutlet weak var syaikh: NSButton!
    @IBOutlet weak var takdil: NSButton!
    @IBOutlet weak var mulakhosh: NSButton!
    @IBOutlet weak var rowiTextField: NSTextField!
    @IBOutlet weak var hStack: NSStackView!
    @IBOutlet weak var tableView: NSTableView!

    @IBOutlet weak var hStackOptions: NSStackView!
    @IBOutlet weak var hStackSearch: NSStackView!
    @IBOutlet weak var startBtn: NSButton!
    @IBOutlet weak var stopBtn: NSButton!
    @IBOutlet weak var searchField: DSFSearchField!

    @IBOutlet weak var optionSegment: NSSegmentedControl!

    weak var delegate: TarjamahBDelegate?
    weak var textView: IbarotTextView?

    var didClickButton: Bool = false
    var rowiMode: RowiMode = .sidebar
    var shouldClickButton: Bool = true

    // MARK: - ViewModel

    var viewModel: NarratorViewModel!

    // MARK: - Computed

    lazy var hStackButtons: [NSButton] = [tilmidz, syaikh, takdil, mulakhosh]
    weak var selectedButtons: NSButton?

    var nullText: String = "・・・"
    var windowTitle: String = "رواة التهذيبين"

    var tarjamahList: [TarjamahResult] {
        rowiMode == .sidebar ? viewModel.sidebarTarjamahList : viewModel.searchTarjamahList
    }

    lazy var copyMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = String(localized: "Copy")
        item.action = #selector(copy(_:))
        return item
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        rowiTextField.allowsExpansionToolTips = true
        selectedButtons = mulakhosh
        tableView.dataSource = self
        tableView.delegate = self
        tableView.userInterfaceLayoutDirection = .leftToRight
        ReusableFunc.registerNib(tableView: tableView, nibName: .resultNib, cellIdentifier: .resultAndOutlineChild)
        hStackSearch.isHidden = true
        searchField.focusRingType = .none
        searchField.recentsAutosaveName = "RowiResultsSearchField"
        searchField.searchSubmitCallback = { [weak self] query in
            self?.viewModel.stopSearch()
            self?.startNewSearch()
        }
        hStackOptions.addArrangedSubview(hStackSearch)
        if #available(macOS 26, *) {
            optionSegment.borderShape = .capsule
            [tilmidz, syaikh, takdil, mulakhosh].forEach { $0?.borderShape = .capsule }
            hStackSearch.subviews.forEach { ($0 as? NSButton)?.borderShape = .capsule }
        }

        tableView.allowsMultipleSelection = true
        // TableView Menu
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(copyMenuItem)
        tableView.menu = menu

        bindViewModel()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateWindowTitle()
        ReusableFunc.setupSearchField(searchField)
    }

    // MARK: - ViewModel Binding

    private func bindViewModel() {
        viewModel.onCurrentRowiChanged = { [weak self] rowi in
            guard let self else { return }
            hideStackUtils()
            if let rowi {
                rowiTextField.stringValue = rowi.isoName
            }
            if shouldClickButton {
                optionSegment.setSelected(true, forSegment: 0)
                selectedButtons?.performClick(nil)
            }
            rowiMode = .sidebar
        }

        viewModel.onRowiContentUpdated = { [weak self] text in
            self?.textView?.displayAuthor(text)
        }

        viewModel.onSidebarTarjamahLoaded = { [weak self] _ in
            self?.tableView.reloadData()
        }

        viewModel.onSearchBatchAppended = { startIndex, count in
            let indices = IndexSet(integersIn: startIndex..<(startIndex + count))
            Task { @MainActor [weak self] in
                guard let self else { return }
                tableView.insertRows(at: indices, withAnimation: .effectFade)
            }
        }

        viewModel.onSearchComplete = { [weak self] in
            self?.updateStartButton(isPaused: false, isActive: false, state: .off)
        }
    }

    // MARK: - Actions

    @IBAction func copy(_ sender: Any?) {
        ReusableFunc.copyResults(tarjamahList, tableView: tableView)
    }

    @MainActor
    func updateStartButton(isPaused: Bool, isActive: Bool, state: NSButton.StateValue) {
        if !isActive {
            // Keadaan Idle / Belum Start
            startBtn.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        } else {
            // Keadaan sedang mencari
            let icon = isPaused ? "play.fill" : "pause.fill"
            startBtn.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        }
        startBtn.state = state
    }

    @IBAction func startSearch(_ sender: Any?) {
        // MODUL 1: Jika sudah berjalan, maka tombol ini berfungsi sebagai Pause/Resume
        if viewModel.isSearching {
            if viewModel.isPaused {
                viewModel.resumeSearch()
                updateStartButton(isPaused: false, isActive: true, state: .on)
            } else {
                viewModel.pauseSearch()
                updateStartButton(isPaused: true, isActive: true, state: .off)
            }
            return // Keluar, jangan jalankan ulang Task di bawah
        }

        // MODUL 2: Jika belum berjalan (Start Baru)
        startNewSearch()
    }

    func startNewSearch() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        ReusableFunc.updateBuiltInRecents(with: query, in: searchField)
        tableView.reloadData()
        updateStartButton(isPaused: false, isActive: true, state: .on)
        viewModel.startSearch(query: query)
    }

    @IBAction func stopSearch(_ sender: Any?) {
        viewModel.stopSearch()
        updateStartButton(isPaused: false, isActive: false, state: .off)
    }

    @IBAction func searchBtnDidClick(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: hideStackUtils()
        case 1: hideRowiUtils()
        default: break
        }
        tableView.reloadData()
    }

    private func hideStackUtils() {
        hStackSearch.isHidden = true
        hStack.isHidden = false
        rowiMode = .sidebar
        if let rowi = viewModel.currentRowi {
            rowiTextField.stringValue = rowi.isoName
        }
    }

    private func hideRowiUtils() {
        hStack.isHidden = true
        rowiTextField.stringValue = "إسم الراوي من الشريط الجانبي"
        hStackSearch.isHidden = false
        rowiMode = .fullSearch
    }

    @IBAction func buttonDidClick(_ sender: NSButton) {
        selectedButtons = sender
        hStackButtons.forEach { btn in
            btn.state = (sender == btn) ? .on : .off
        }

        didClickButton = true

        guard let currentRowi = viewModel.currentRowi else { return }

        // Tentukan mode display berdasarkan tombol
        switch sender {
        case tilmidz: viewModel.setDisplayMode(.tilmidz)
        case syaikh: viewModel.setDisplayMode(.syaikh)
        case takdil: viewModel.setDisplayMode(.takdil)
        case mulakhosh: viewModel.setDisplayMode(.mulakhosh)
        default: break
        }

        // Mulakhosh: tampilkan di textView via displayAuthor (menggunakan macOS renderMulakhosh di VM)
        // onRowiContentUpdated callback sudah handle update textView
        // Untuk mode lain, string langsung via callback

        updateWindowTitle()
        didClickButton = false

        delegate?.didSelectRowi(rowi: currentRowi)

        if tableView.selectedRow != -1 {
            tableView.deselectAll(nil)
        }
    }

    func updateWindowTitle(_ force: Bool = false) {
        if !force, hStackButtons.allSatisfy({ $0.state == .off }) {
            return
        }

        view.window?.title = windowTitle
        view.window?.subtitle.removeAll()
    }

    func turnOffStateButtons() {
        hStackButtons.forEach({ $0.state = .off })
    }
}

// MARK: - RowiSidebarDelegate

extension RowiResultsVC: RowiSidebarDelegate {
    func didSelect(rowi: Rowi) {
        viewModel.selectRowi(rowi)
    }
}

// MARK: - NSTableViewDataSource

extension RowiResultsVC: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tarjamahList.count
    }
}

// MARK: - NSTableViewDelegate

extension RowiResultsVC: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < tarjamahList.count,
              let cell = tableView.makeView(
                withIdentifier: NSUserInterfaceItemIdentifier(
                    CellIViewIdentifier
                        .resultAndOutlineChild
                        .rawValue
                ), owner: self) as? NSTableCellView
        else { return nil }

        let data = tarjamahList[row]

        switch tableColumn?.identifier.rawValue {
        case "Content":
            cell.textField?.stringValue = data.content
        case "Book":
            cell.textField?.stringValue = data.tarjamah.bookTitle ?? ""
        default:
            break
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard !didClickButton, row != -1 else {
            selectedButtons?.performClick(nil)
            return
        }

        turnOffStateButtons()

        let data = tarjamahList[row]

        Task.detached { [weak self] in
            await self?.delegate?.didSelect(tarjamahB: data.tarjamah, query: self?.searchField.stringValue)
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        24
    }
}

// MARK: - ReaderStateComponent

extension RowiResultsVC: ReaderStateComponent {
    func updateState(_ state: inout ReaderState) {
        viewModel.updateState(&state)
        
        state.authorTarjamahResults = tarjamahList
        state.authorRowiMode = (rowiMode == .sidebar) ? "sidebar" : "fullSearch"
        
        let sidebarSelection: Bool = hStackButtons.contains { $0.state == .on }
        state.authorDisplayMode = sidebarSelection ? .rowiInfo : .bookContent
    }

    func restore(from state: ReaderState) {
        guard let rowi = state.currentRowi else { return }

        shouldClickButton = false
        viewModel.restore(from: state)

        if let savedMode = state.authorRowiMode {
            rowiMode = (savedMode == "sidebar") ? .sidebar : .fullSearch

            let sidebar = state.authorTarjamahResults ?? []
            let search: [TarjamahResult] = (rowiMode == .fullSearch) ? sidebar : []
            viewModel.restoreTarjamahLists(
                sidebar: (rowiMode == .sidebar) ? sidebar : [],
                search: search
            )

            if rowiMode == .fullSearch {
                searchField.stringValue = viewModel.searchText
            }

            updateUIForRestoredMode()
            tableView.reloadData()
        }

        // Restore tampilan konten atau info bio
        rowiTextField.stringValue = rowi.isoName

        if let displayMode = state.authorDisplayMode {
            if displayMode == .rowiInfo, let btn = selectedButtons {
                buttonDidClick(btn)
            } else if displayMode == .bookContent {
                turnOffStateButtons()
            }
        }

        shouldClickButton = true
    }

    func cleanUpState() {
        viewModel.cleanUpState()
        searchField.stringValue = ""
        rowiTextField.stringValue = ""
        tableView.reloadData()
        updateWindowTitle(true)
    }

    // MARK: - UI Update for Restored State

    /// Update UI berdasarkan rowiMode yang di-restore
    func updateUIForRestoredMode() {
        switch rowiMode {
        case .sidebar:
            hStackSearch.isHidden = true
            hStack.isHidden = false
            optionSegment.setSelected(true, forSegment: 0)
        case .fullSearch:
            hStack.isHidden = true
            hStackSearch.isHidden = false
            optionSegment.setSelected(true, forSegment: 1)
        }

        rowiTextField.stringValue = "إسم الراوي من الشريط الجانبي"

        #if DEBUG
            print("🔄 Updated UI for restored mode: \(rowiMode)")
        #endif
    }
}

// MARK: - NSMenuDelegate

extension RowiResultsVC: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        copyMenuItem.isHidden = tableView.clickedRow < 0
    }
}
