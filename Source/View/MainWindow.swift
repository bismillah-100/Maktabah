//
//  MainWindow.swift
//  maktab
//
//  Simplified window dengan single container
//

import Cocoa

class MainWindow: NSWindow {
    @IBOutlet weak var modeSegment: NSSegmentedControl!
    @IBOutlet weak var modeSegmentToolbarItem: NSToolbarItem!
    @IBOutlet weak var sidebarLeading: NSToolbarItem!
    @IBOutlet weak var searchSidebarLeading: NSToolbarItem!
    @IBOutlet weak var bookInfo: NSToolbarItem!
    @IBOutlet weak var navSegment: NSToolbarItem!
    @IBOutlet weak var copyWith: NSToolbarItem!
    @IBOutlet weak var displayAnnotations: NSToolbarItem!
    @IBOutlet weak var searchBook: NSToolbarItem!
    @IBOutlet weak var viewOpt: NSToolbarItem!
    @IBOutlet weak var navigationPage: NSToolbarItem!
    @IBOutlet weak var searchSidebarTrailing: NSToolbarItem!
    @IBOutlet weak var sidebarTrailing: NSToolbarItem!

    // MARK: - Single Container (state terjaga)
    lazy var splitVC: SplitVC = {
        SplitVC()
    }()

    var currentMode: AppMode {
        UserDefaults.standard.lastAppMode
    }

    static var rtl: Bool {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        let isRTL = Locale.Language(identifier: languageCode).characterDirection == .rightToLeft
        return isRTL
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        sidebarTrailing.isNavigational = Self.rtl
        searchSidebarTrailing.isNavigational = Self.rtl
    }

    override func becomeKey() {
        super.becomeKey()
        updateToolbar()
    }

    func setupContentView(restoreState: Bool = true) {
        let currentFrame = frame
        // Restore last mode
        if !restoreState {
            splitVC.setupForMode(currentMode)
            splitVC.setupAutoSave()
        }
        contentViewController = splitVC
        splitVC.currentMode = currentMode
        // Restore frame
        setFrame(currentFrame, display: true, animate: false)

        if !restoreState {
            setupView()
        }
    }

    func setupView() {
        Task { @MainActor in
            await Task.yield()
            // Setup toolbar once
            setupToolbarTargets()
            updateUI()
        }
    }

    private func setupToolbarTargets() {
        guard let toolbar = toolbar else { return }

        toolbar.item(with: .sidebarLeading)?
            .view?
            .setTargetAction(self, #selector(sidebarLeadingToggle(_:)))

        toolbar.item(with: .navSegment)?
            .view?
            .setTargetAction(self, #selector(pageControl(_:)))

        toolbar.item(with: .textViewOptions)?
            .view?
            .setTargetAction(self, #selector(viewOptions(_:)))

        toolbar.item(with: .bookInfo)?
            .view?
            .setTargetAction(self, #selector(bookInfo(_:)))

        toolbar.item(with: .copyDetails)?
            .view?
            .setTargetAction(self, #selector(copyWith(_:)))

        toolbar.item(with: .searchSidebarLeadingContent)?
            .view?
            .setTargetAction(self, #selector(hideLibrarySearchField(_:)))

        toolbar.item(with: .sidebarTrailing)?
            .view?
            .setTargetAction(self, #selector(sidebarTrailing(_:)))

        toolbar.item(with: .searchContents)?.view?.setTargetAction(
            self, #selector(searchSidebarTrailingContent(_:))
        )

        toolbar.item(with: .displayNotations)?.view?.setTargetAction(
            self, #selector(displayAllNotations(_:))
        )

        toolbar.item(with: .searchField)?.view?.setTargetAction(
            self, #selector(searchPopover(_:))
        )
    }

    func setAnnotationsPanelDelegate() {
        splitVC.setAnnotationsPanelDelegate()
    }

    // MARK: - Mode Switching (Simplified)

    func switchMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? AppMode,
              mode != currentMode else {
            return
        }

        switchToMode(mode)
    }

    private func switchToMode(_ mode: AppMode) {
        guard mode != currentMode else { return }

        // Save preference
        UserDefaults.standard.lastAppMode = mode

        splitVC.switchToMode(mode)
        updateDelegateAndSegment()
    }

    private func updateUI() {
        // Update UI
        updateToolbar()
        updateDelegateAndSegment()
    }

    private func updateDelegateAndSegment() {
        // Update segment control
        setAnnotationsPanelDelegate()
        if let modeSelector = toolbar?.item(with: .modeSelector)?.view as? NSSegmentedControl {
            modeSelector.selectedSegment = currentMode.rawValue
        }
    }

    // MARK: - Toolbar Update (Simplified - hanya sekali)

    private func updateToolbar() {
        guard let toolbar, toolbar.customizationPaletteIsRunning == false else { return }

        removeToolbarItem(.trackingSeparator, from: toolbar)

        if #available(macOS 26, *), !Self.rtl,
           let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == .searchContents }),
           index >= 0, index < toolbar.items.count
        {
            toolbar.insertItem(withItemIdentifier: .trackingSeparator, at: index)
        }
    }

    private func removeToolbarItem(_ identifier: NSToolbarItem.Identifier, from toolbar: NSToolbar)
    {
        if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == identifier }) {
            toolbar.removeItem(at: index)
        }
    }

    // MARK: - Cleanup

    override func close() {
        #if DEBUG
        print("MainWindow close() called")
        #endif

        splitVC.persistCurrentStateToDisk()

        super.close()

        contentViewController = nil
        contentView = nil
        delegate = nil
    }

    deinit {
        #if DEBUG
        print("MainWindow deinit")
        #endif
    }
}

// MARK: - Toolbar Actions (Delegasi ke SplitVC)
extension MainWindow {
    @IBAction func modeSelectorChanged(_ sender: NSSegmentedControl) {
        if let mode = AppMode(rawValue: sender.selectedSegment) {
            switchToMode(mode)
        }
    }

    // MARK: - Navigation Actions

    @IBAction func sidebarLeadingToggle(_ sender: Any) {
        splitVC.sidebarLeadingToggle()
    }

    @IBAction func sidebarTrailing(_ sender: Any) {
        splitVC.sidebarTrailing()
    }

    @IBAction func pageControl(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: splitVC.nextPage()
        case 1: splitVC.prevPage()
        default: break
        }
    }

    @IBAction func navigationPage(_ sender: Any) {
        splitVC.navigationPage(sender)
    }

    // MARK: - View Options

    @IBAction func viewOptions(_ sender: Any) {
        splitVC.viewOptions(sender)
    }

    @IBAction func bookInfo(_ sender: NSButton) {
        splitVC.bookInfo(sender)
    }

    @IBAction func copyWith(_ sender: NSButton) {
        splitVC.copyDetails()
    }

    // MARK: - Search Actions

    @IBAction func hideLibrarySearchField(_ sender: Any) {
        // Implementation di SplitVC
        splitVC.hideLibrarySearchField()
    }

    @IBAction func searchSidebarTrailingContent(_ sender: Any) {
        splitVC.searchSidebarTrailing()
    }

    @IBAction func displayAllNotations(_ sender: Any?) {
        splitVC.displayAnnotations(sender)
    }

    @IBAction func searchPopover(_ sender: NSButton) {
        splitVC.searchCurrentBook(sender)
    }
}
