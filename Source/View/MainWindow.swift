//
//  MainWindow.swift
//  maktab
//
//  Created by MacBook on 08/12/25.
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

    private(set) var currentMode: AppMode = .viewer

    // View Controllers untuk setiap mode
    private(set) var currentSplitVC: ToolbarActionDelegate?
    private(set) var viewerSplitVC: SplitView?
    private(set) var searchSplitVC: SearchSplitView?
    private(set) var authorSplitVC: RowiSplitVC?

    static var rtl: Bool {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        let isRTL = Locale.Language(identifier: languageCode).characterDirection == .rightToLeft
        return isRTL
    }

    override func awakeFromNib() {
        sidebarTrailing.isNavigational = Self.rtl
        searchSidebarTrailing.isNavigational = Self.rtl

        Task { @MainActor in
            // Restore last mode dari UserDefaults
            if let lastMode = UserDefaults.standard.object(forKey: "LastAppMode") as? Int,
               let mode = AppMode(rawValue: lastMode) {
                currentMode = mode  // Set dulu sebelum switchToMode
                await switchToMode(mode, force: true)  // Force load

                if let modeSelector = toolbar?.item(with: .modeSelector)?.view as? NSSegmentedControl {
                    modeSelector.selectedSegment = lastMode
                }
            } else {
                // Default viewer mode - force load pertama kali
                await switchToMode(.viewer, force: true)
            }
        }
    }

    override func becomeKey() {
        super.becomeKey()
        updateToolbar()
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
        if let rootSplitVC = currentSplitVC as? RootSplitView,
           let annVC = SharedPopover.annotationsVC {
            annVC.dataSource.delegate = rootSplitVC.ibarotTextVC
        }
    }

    func switchMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? AppMode,
              mode != currentMode else {
            return
        }

        // Save preference
        currentMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "LastAppMode")
        let currentFrame = frame

        switch mode {
        case .viewer: viewReader()
        case .search: viewFinder()
        case .author: viewAuthor()
        }

        rebuildWindow(currentFrame: currentFrame)
    }

    func viewReader() {
        if viewerSplitVC == nil {
            viewerSplitVC = SplitView(nibName: "SplitView", bundle: nil)
        }
        contentViewController = viewerSplitVC
        currentSplitVC = viewerSplitVC
        modeSegment?.selectedSegment = 0
    }

    func viewFinder() {
        if searchSplitVC == nil {
            searchSplitVC = SearchSplitView(nibName: "SearchSplitView", bundle: nil)
        }
        contentViewController = searchSplitVC
        currentSplitVC = searchSplitVC
        modeSegment?.selectedSegment = 1
    }

    func viewAuthor() {
        if authorSplitVC == nil {
            authorSplitVC = RowiSplitVC(nibName: "RowiSplitVC", bundle: nil)
        }
        contentViewController = authorSplitVC
        currentSplitVC = authorSplitVC
        modeSegment?.selectedSegment = 2
    }

    @MainActor
    func switchToMode(_ mode: AppMode, force: Bool = false) async {
        guard force || currentMode != mode else { return }  // Tambah force parameter

        currentMode = mode

        // Save preference
        UserDefaults.standard.set(mode.rawValue, forKey: "LastAppMode")

        let currentFrame = frame

        // Switch content view controller
        switch mode {
        case .viewer: viewReader()
        case .search: viewFinder()
        case .author: viewAuthor()
        }

        rebuildWindow(currentFrame: currentFrame)
    }

    func rebuildWindow(currentFrame: NSRect) {
        // Rebuild toolbar items
        setFrame(currentFrame, display: true, animate: false)
        setAnnotationsPanelDelegate()
        updateToolbar()
        setupToolbarTargets()
    }

    func removeToolbarItem(_ identifier: NSToolbarItem.Identifier, from toolbar: NSToolbar) {
        if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == identifier }) {
            toolbar.removeItem(at: index)
        }
    }

    private func updateToolbar() {
        guard let toolbar, toolbar.customizationPaletteIsRunning == false else { return }
        /*
        if currentMode == .search {
            removeToolbarItem(.searchSidebarLeadingContent, from: toolbar)

            if !toolbar.items.contains(where: { $0.itemIdentifier == .bookmark }),
               let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == .textViewOptions }) {
                toolbar.insertItem(withItemIdentifier: .bookmark, at: index - 1)
            }

            if !toolbar.items.contains(where: { $0.itemIdentifier == .insertBookmark }),
               let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == .textViewOptions }) {
                toolbar.insertItem(withItemIdentifier: .insertBookmark, at: index - 1)
            }

        } else {
            if !toolbar.items.contains(where: { $0.itemIdentifier == .searchSidebarLeadingContent }),
               let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == .sidebarLeading }) {
                toolbar.insertItem(withItemIdentifier: .searchSidebarLeadingContent, at: index + 1)
            }
            removeToolbarItem(.bookmark, from: toolbar)
            removeToolbarItem(.insertBookmark, from: toolbar)
        }
         */

        removeToolbarItem(.trackingSeparator, from: toolbar)
        if #available(macOS 26, *), !Self.rtl,
           let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == .searchContents }),
           index >= 0, index < toolbar.items.count
        {
            toolbar.insertItem(withItemIdentifier: .trackingSeparator, at: index)
        }
    }

    /*
    private func updateToolbar() {
        guard let toolbar else { return }
        let keep: Set<NSToolbarItem.Identifier> = [
            .modeSelector,
            NSToolbarItem.Identifier.sidebarTrackingSeparator
        ]

        // Hapus semua item kecuali yang dipertahankan
        for (index, item) in toolbar.items.enumerated().reversed() {
            if keep.contains(item.itemIdentifier) == false {
                toolbar.removeItem(at: index)
            }
        }

        // Tambahkan item baru sesuai mode, tetapi jangan masukkan item yang sudah dipertahankan
        let itemIdentifiers = toolbarItemsForMode(currentMode)
        for identifier in itemIdentifiers where keep.contains(identifier) == false {
            toolbar.insertItem(withItemIdentifier: identifier, at: toolbar.items.count)
        }
    }
     */

    override func close() {
        #if DEBUG
        print("MainWindow close() called")
        #endif
        // Hanya cleanup jika ini adalah tab terakhir atau window benar-benar close
        // Lepaskan semua view controllers
        super.close()

        contentViewController = nil
        viewerSplitVC = nil
        searchSplitVC = nil
        authorSplitVC = nil
        contentView = nil

        // Lepaskan delegate
        delegate = nil
    }

    deinit {
        #if DEBUG
        print("MainWindow deinit")
        #endif
    }
}

// MARK: - WindowController Toolbar Actions Extension
extension MainWindow {
    @IBAction func modeSelectorChanged(_ sender: NSSegmentedControl) {
        if let mode = AppMode(rawValue: sender.selectedSegment) {
            Task {
                await switchToMode(mode)
            }
        }
    }

    // MARK: - Computed Properties untuk akses VC
    private var viewerSplit: SplitView? {
        viewerSplitVC
    }

    // MARK: - Navigation Actions
    @IBAction func sidebarLeadingToggle(_ sender: Any) {
        currentSplitVC?.sidebarLeadingToggle()
    }

    @IBAction func sidebarTrailing(_ sender: Any) {
        currentSplitVC?.sidebarTrailing()
    }

    @IBAction func pageControl(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            nextPage()
        case 1:
            prevPage()
        default:
            break
        }
    }

    private func prevPage() {
        currentSplitVC?.nextPage()
    }

    private func nextPage() {
        currentSplitVC?.prevPage()
    }

    @IBAction func navigationPage(_ sender: Any) {
        currentSplitVC?.navigationPage(sender)
    }

    // MARK: - View Options
    @IBAction func viewOptions(_ sender: Any) {
        currentSplitVC?.viewOptions(sender)
    }

    @IBAction func bookInfo(_ sender: NSButton) {
        currentSplitVC?.bookInfo(sender)
    }

    @IBAction func copyWith(_ sender: NSButton) {
        currentSplitVC?.copyDetails(sender)
    }

    // MARK: - Search Actions

    @IBAction func hideLibrarySearchField(_ sender: Any) {
        switch currentMode {
        case .viewer:
            if let libraryVC = viewerSplit?.libraryItem?.viewController as? LibraryVC {
                libraryVC.searchFieldIsHidden.toggle()
                libraryVC.unhideSearchField()

            }
        case .author:
            if let libraryVC = authorSplitVC?.sidebarVC {
                libraryVC.searchFieldIsHidden.toggle()
                libraryVC.unhideSearchField()
            }
        case .search:
            if let searchSidebarVC = searchSplitVC?.searchSidebarVC {
                searchSidebarVC.searchField.becomeFirstResponder()
            }
        }
    }

    @IBAction func searchSidebarTrailingContent(_ sender: Any) {
        currentSplitVC?.searchSidebarTrailing()
    }

    @IBAction func displayAllNotations(_ sender: Any?) {
        currentSplitVC?.displayAnnotations(sender)
    }

    @IBAction func searchPopover(_ sender: NSButton) {
        currentSplitVC?.searchCurrentBook(sender)
    }
}
