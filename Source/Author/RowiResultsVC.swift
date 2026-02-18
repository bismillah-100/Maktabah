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

    lazy var hStackButtons: [NSButton] = [
        tilmidz,
        syaikh,
        takdil,
        mulakhosh
    ]

    weak var selectedButtons: NSButton?

    let data: RowiDataManager = .shared

    var shouldClickButton: Bool = true

    var currentRowi: Rowi? {
        didSet {
            guard oldValue?.id != currentRowi?.id else { return }

            hideStackUtils()
            if let rowi = currentRowi {
                data.loadRowiData(rowi)
                rowiTextField.stringValue = rowi.isoName
            }
            if shouldClickButton {
                optionSegment.setSelected(true, forSegment: 0)
                selectedButtons?.performClick(nil)
            }
            rowiMode = .sidebar
        }
    }

    var nullText: String = "・・・"
    var windowTitle: String = "رواة التهذيبين"

    // Dependencies
    let manager = TarjamahGlobalManager.shared
    let pauseController = PauseController()

    // State
    var isSearching = false
    var isStopped = false
    var searchTask: Task<Void, Never>?

    var tarjamahList: [TarjamahResult] {
        rowiMode == .sidebar ? sidebarTarjamahList : searchTarjamahList
    }

    var sidebarTarjamahList: [TarjamahResult] = []
    var searchTarjamahList: [TarjamahResult] = []

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
            self?.stopSearch(nil)
            self?.startSearch(nil)
        }
        hStackOptions.addArrangedSubview(hStackSearch)
        if #available(macOS 26, *) {
            optionSegment.borderShape = .circle
            let btns = [tilmidz, syaikh, takdil, mulakhosh]
            btns.forEach { btn in
                btn?.borderShape = .circle
            }
            hStackSearch.subviews.forEach { view in
                if let v = view as? NSButton {
                    v.borderShape = .circle
                }
            }
        }
        // Do view setup here.
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateWindowTitle()
        ReusableFunc.setupSearchField(searchField)
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
        if isSearching {
            if pauseController.currentlyPaused() {
                pauseController.resume()
                updateStartButton(isPaused: false, isActive: true, state: .on)
            } else {
                pauseController.pause()
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

        // Reset State
        isSearching = true
        isStopped = false
        searchTarjamahList.removeAll()
        tableView.reloadData()
        pauseController.resume() // Pastikan tidak dalam keadaan pause dari session sebelumnya
        updateStartButton(isPaused: false, isActive: true, state: .on)

        searchTask?.cancel()
        searchTask = Task {
            await manager.searchTarjamah(
                query: query,
                limit: 100,
                pauseController: pauseController,
                stopFlag: { [weak self] in self?.isStopped ?? true },
                onBatchResult: { [weak self] newBatch in
                    guard let self = self else { return }

                    // Proses load content per batch
                    var resultsBatch = [TarjamahResult]()
                    await manager.loadMultipleTarjamahContent(
                        newBatch,
                        pauseController: self.pauseController // Teruskan pause controller ke sini juga!
                    ) { [isStopped] in
                        isStopped
                    } onBatchResult: { loadedResults in
                        resultsBatch.append(contentsOf: loadedResults)
                    } onProgress: { _, _ in }

                    // Update UI secara Batch
                    await MainActor.run { [resultsBatch] in
                        let startRow = self.tarjamahList.count
                        self.searchTarjamahList.append(contentsOf: resultsBatch)
                        let indices = IndexSet(integersIn: startRow..<(startRow + resultsBatch.count))
                        self.tableView.insertRows(at: indices, withAnimation: .effectFade)
                    }
                },
                onComplete: { [weak self] in
                    // Kembalikan tombol ke kondisi "Start"
                    Task { @MainActor in
                        self?.isSearching = false
                        self?.updateStartButton(isPaused: false, isActive: false, state: .off)
                    }
                }
            )
        }
    }

    @IBAction func stopSearch(_ sender: Any?) {
        isStopped = true
        pauseController.resume() // Resume agar loop yang tertahan bisa keluar dan membaca flag stop
        searchTask?.cancel()
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
        if let currentRowi {
            rowiTextField.stringValue = currentRowi.isoName
        }
    }

    private func hideRowiUtils() {
        hStack.isHidden = true
        rowiTextField.stringValue = "إسم الراوي من الشريط الجانبي"
        hStackSearch.isHidden = false
        rowiMode = .fullSearch
    }

    @IBAction func buttonDidClick(_ sender: NSButton) {
        // 1. Atur status ON/OFF
        selectedButtons = sender
        hStackButtons.forEach { btn in
            btn.state = (sender == btn) ? .on : .off
        }

        didClickButton = true

        guard let currentRowi else { return }

        // 2. Tentukan teks berdasarkan tombol yang diklik (sender)
        switch sender {
        case tilmidz: presentTilmidz(for: currentRowi)
        case syaikh: presentSyaikh(for: currentRowi)
        case takdil: presentTakdil(for: currentRowi)
        case mulakhosh: presentMulakhosh(for: currentRowi)
        default:
            break
        }
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

    func presentMulakhosh(for rowi: Rowi) {
        guard let rotba = rowi.rotba,
              let rZahbi = rowi.rZahbi
        else {
            return
        }
        textView?.displayAuthor(rotba, rZahbi: rZahbi, for: rowi)
    }

    func presentTakdil(for rowi: Rowi) {
        textView?.string = rowi.aqual ?? nullText
    }

    func presentSyaikh(for rowi: Rowi) {
        textView?.string = rowi.sheok ?? nullText
    }

    func presentTilmidz(for rowi: Rowi) {
        textView?.string = rowi.telmez ?? nullText
    }

    func turnOffStateButtons() {
        hStackButtons.forEach({ $0.state = .off })
    }
}

extension RowiResultsVC: RowiSidebarDelegate {
    func didSelect(rowi: Rowi) {
        data.loadRowiData(rowi)
        currentRowi = rowi
        Task.detached { [weak self] in
            guard let self else { return }
            let tarjamahList = await TarjamahGlobalManager.shared.loadAllTarjamahContent(forRowa: rowi.id)
            await MainActor.run { [tarjamahList] in
                self.sidebarTarjamahList = tarjamahList
                self.tableView.reloadData()
            }
        }
    }
}

extension RowiResultsVC: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tarjamahList.count
    }
}

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

extension RowiResultsVC: ReaderStateComponent {
    func updateState(_ state: inout ReaderState) {
        state.currentRowi = currentRowi
        state.authorTarjamahResults = tarjamahList
        state.authorRowiMode = (rowiMode == .sidebar) ? "sidebar" : "fullSearch"
        if rowiMode == .fullSearch {
            state.authorSearchQuery = searchField.stringValue
        }
        let sidebarSelection: Bool = hStackButtons.contains { $0.state == .on }
        state.authorDisplayMode = sidebarSelection ? .rowiInfo : .bookContent
    }

    func restore(from state: ReaderState) {
        guard let rowi = state.currentRowi else { return }

        shouldClickButton = false
        currentRowi = rowi

        // Restore mode pencarian penulis
        if let savedMode = state.authorRowiMode {
            rowiMode = (savedMode == "sidebar") ? .sidebar : .fullSearch

            if rowiMode == .sidebar {
                sidebarTarjamahList = state.authorTarjamahResults ?? []
            } else {
                searchTarjamahList = state.authorTarjamahResults ?? []
                searchField.stringValue = state.authorSearchQuery ?? ""
            }

            updateUIForRestoredMode()
            tableView.reloadData()
        }

        // Restore tampilan konten atau info bio
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
        currentRowi = nil
        sidebarTarjamahList.removeAll()
        searchTarjamahList.removeAll()
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
