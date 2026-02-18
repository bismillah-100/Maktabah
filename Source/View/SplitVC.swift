//
//  SplitVC.swift
//  maktab
//
//  Unified container untuk semua mode (viewer, search, author)
//

import Cocoa

class SplitVC: NSSplitViewController {

    // MARK: - Managers
    /// Manager khusus untuk menangani state persistence
    let stateManager = ReaderStateManager()

    // MARK: - Shared Components
    lazy var ibarotTextVC: IbarotTextVC = {
        viewerSplitVC.ibarotVC
    }()

    lazy var viewerSplitVC: ViewerSplitVC = {
        // Setup ViewerSplitVC (SINGLETON)
        let containerVC = ViewerSplitVC()
        containerVC.rootSplitView = self
        return containerVC
    }()

    // MARK: - Child View Controllers
    // Mode-specific Sidebars
    private(set) var libraryVC: LibraryVC?
    private(set) var searchSidebarVC: SearchSidebarVC?
    private(set) var rowiSidebarVC: RowiSidebarVC?

    // Mode-specific Results
    private(set) var optionSearchVC: OptionSearchVC?

    lazy var rowiResultsVC: RowiResultsVC = {
        let rowiResultsVC = RowiResultsVC(nibName: "RowiResultsVC", bundle: nil)
        return rowiResultsVC
    }()

    // MARK: - Split View Items
    private(set) var sidebarItem: NSSplitViewItem!
    private(set) var contentItem: NSSplitViewItem!

    /// Persistent container sidebar split item supaya
    /// sidebarItem tidak dibuat ulang setiap kali switchToMode.
    private var sidebarContainerVC: NSViewController?

    // MARK: - Current Mode
    var currentMode: AppMode = .viewer

    // Akses ke state manager untuk VC lain jika dibutuhkan
    var currentState: ReaderState {
        get { stateManager.getState(for: currentMode) }
        set { stateManager.setState(newValue, for: currentMode) }
    }

    var optSearchPopover: NSPopover?
    var optSearch: OptionSearchVC?

    // MARK: - Lifecycle

    func setupAutoSave() {
        // Apply autosave configuration
        if !MainWindow.rtl {
            viewerSplitVC.splitView.autosaveName = "UnifiedViewerSplitView"
        }
        splitView.autosaveName = "UnifiedSplitView"
    }

    // MARK: - Mode Switching
    func components(for mode: AppMode) -> [ReaderStateComponent?] {
        switch mode {
        case .viewer:
            return [ibarotTextVC]  // Cuma init yang diperlukan
        case .search:
            return [ibarotTextVC, optionSearchVC]
        case .author:
            return [ibarotTextVC, rowiResultsVC]
        }
    }

    func switchToMode(_ mode: AppMode) {
        // Simpan title sebelum switch
        let savedTitle = view.window?.title ?? ""
        let savedSubtitle = view.window?.subtitle ?? ""

        stateManager.saveState(
            for: currentMode,
            components: components(for: currentMode)
        )

        ibarotTextVC.textView.string.removeAll()

        // Remove all split items except the persistent sidebar (if present).
        let itemsToRemove = splitViewItems.filter { $0 != sidebarItem }
        itemsToRemove.forEach { removeSplitViewItem($0) }

        setupForMode(mode)
        sidebarItem.isCollapsed =
            stateManager.getState(for: mode).isSidebarCollapsed

        // Pass rowiResultsVC untuk Author mode restore
        stateManager.restoreState(
            for: mode,
            components: components(for: currentMode)
        )

        setAnnotationsPanelDelegate()

        currentMode = mode

        ibarotTextVC.restoreWindowTitleAfterModeSwitch(oldTitle: savedTitle, oldSubtitle: savedSubtitle)
    }

    func persistCurrentStateToDisk() {
        stateManager.saveState(
            for: currentMode,
            components: components(for: currentMode)
        )

        stateManager.persisToDisk(for: currentMode)
    }

    // MARK: - Mode Setup Helpers

    func setupForMode(_ mode: AppMode) {
        switch mode {
        case .viewer:
            setupViewerMode()
        case .search:
            setupSearchMode()
        case .author:
            setupAuthorMode()
        }

        currentMode = mode
    }

    // MARK: - Viewer Mode Setup

    private func setupViewerMode() {
        if libraryVC == nil {
            libraryVC = LibraryVC(nibName: "LibraryVC", bundle: nil)
            libraryVC?.delegate = ibarotTextVC
        }
        ensureSidebarContainerIfNeeded(thickness: 180)
        setSidebarChild(libraryVC!)

        contentItem = NSSplitViewItem(
            contentListWithViewController: viewerSplitVC
        )
        addAndConfigure(contentItem)
    }

    // MARK: - Search Mode Setup

    private func setupSearchMode() {
        if searchSidebarVC == nil {
            searchSidebarVC = SearchSidebarVC(
                nibName: "SearchSidebarVC",
                bundle: nil
            )
        }
        ensureSidebarContainerIfNeeded(thickness: 180)
        setSidebarChild(searchSidebarVC!)

        let containerSplit = createContentContainer(
            withResult: getSearchOptionsVC(),
            autosaveName: "SearchResultsSplit"
        )
        contentItem = NSSplitViewItem(viewController: containerSplit)
        addAndConfigure(contentItem)
    }

    private func getSearchOptionsVC() -> OptionSearchVC {
        if optionSearchVC == nil {
            optionSearchVC = OptionSearchVC()
            optionSearchVC?.delegate = ibarotTextVC
            optionSearchVC?.itemDelegate = ibarotTextVC
            optionSearchVC?.libraryViewManager = searchSidebarVC?.dataVM
        }
        return optionSearchVC!
    }

    // MARK: - Author Mode Setup

    private func setupAuthorMode() {
        if rowiSidebarVC == nil {
            rowiSidebarVC = RowiSidebarVC()
        }
        ensureSidebarContainerIfNeeded(thickness: 180)
        setSidebarChild(rowiSidebarVC!)

        let containerSplit = createContentContainer(
            withResult: rowiResultsVC,
            autosaveName: "AuthorResultsSplit"
        )
        contentItem = NSSplitViewItem(viewController: containerSplit)
        addAndConfigure(contentItem)

        // Extra connection for Author Mode
        rowiSidebarVC?.delegate = rowiResultsVC
        rowiResultsVC.delegate = ibarotTextVC
        rowiResultsVC.textView = ibarotTextVC.textView
    }

    // MARK: - Sidebar container helpers

    private func ensureSidebarContainerIfNeeded(thickness: CGFloat = 180) {
        if sidebarContainerVC != nil { return }

        let container = NSViewController()
        container.view = NSView()
        sidebarContainerVC = container

        sidebarItem = NSSplitViewItem(sidebarWithViewController: container)
        addAndConfigure(sidebarItem, thickness: thickness)
    }

    private func setSidebarChild(_ child: NSViewController) {
        guard let container = sidebarContainerVC else { return }

        // Remove existing children
        for existing in container.children {
            existing.view.removeFromSuperview()
            existing.removeFromParent()
        }

        // Embed new child
        container.addChild(child)
        child.view.frame = container.view.bounds
        child.view.autoresizingMask = [.width, .height]
        container.view.addSubview(child.view)
    }

    // MARK: - Layout Helpers

    private func createContentContainer(
        withResult resultVC: NSViewController,
        autosaveName: String
    ) -> NSSplitViewController {
        let container = NSSplitViewController()
        container.splitView.isVertical = false

        // Top: Viewer (Shared Instance)
        let viewerItem = NSSplitViewItem(viewController: viewerSplitVC)
        viewerItem.allowsFullHeightLayout = true
        container.addSplitViewItem(viewerItem)

        // Bottom: Results
        let resultsItem = NSSplitViewItem(viewController: resultVC)
        resultsItem.minimumThickness = 100
        resultsItem.holdingPriority = NSLayoutConstraint.Priority(260)
        container.addSplitViewItem(resultsItem)

        container.splitView.autosaveName = autosaveName
        return container
    }

    private func addAndConfigure(
        _ item: NSSplitViewItem,
        thickness: CGFloat? = nil
    ) {
        item.allowsFullHeightLayout = true
        item.titlebarSeparatorStyle = .automatic
        if let thick = thickness {
            item.minimumThickness = thick
        }
        if #available(macOS 26.0, *) {
            item.automaticallyAdjustsSafeAreaInsets = true
        }
        addSplitViewItem(item)
    }

    deinit {
        #if DEBUG
            print("SplitVC deinit")
        #endif
    }
}

// MARK: - Extensions

extension SplitVC {
    /*
    var currentSidebarVC: NSViewController? {
        switch currentMode {
        case .viewer: return libraryVC
        case .search: return searchSidebarVC
        case .author: return rowiSidebarVC
        }
    }
     */

    func setAnnotationsPanelDelegate() {
        if let annVC = SharedPopover.annotationsVC {
            annVC.dataSource.delegate = ibarotTextVC
        }
    }
}

extension SplitVC {
    func sidebarLeadingToggle() {
        // Asumsi 'toggleSidebar' tersedia di Self (yaitu SearchSplitView/SplitView)
        toggleSidebar(nil)
        currentState.toggleSidebar(sidebarItem.isCollapsed)
    }

    func sidebarTrailing() {
        viewerSplitVC.hideTableOfContents(nil)
    }

    func hideLibrarySearchField() {
        switch currentMode {
        case .viewer:
            if let libraryVC = libraryVC {
                libraryVC.searchFieldIsHidden.toggle()
                libraryVC.unhideSearchField()
            }
        case .search:
            if let libraryVC = searchSidebarVC {
                libraryVC.searchField.becomeFirstResponder()
            }
        case .author:
            if let libraryVC = rowiSidebarVC {
                libraryVC.searchFieldIsHidden.toggle()
                libraryVC.unhideSearchField()
            }
        }
    }

    func prevPage() {
        // Mengakses properti ibarotTextVC dari RootSplitView
        ibarotTextVC.previousPage(nil)
    }

    func nextPage() {
        ibarotTextVC.nextPage(nil)
    }

    func viewOptions(_ sender: Any) {
        viewerSplitVC.viewOptions(sender)
    }

    func bookInfo(_ sender: Any) {
        ibarotTextVC.bookInfo(sender)
    }

    func navigationPage(_ sender: Any) {
        ibarotTextVC.navigationPage(sender)
    }

    func copyDetails() {
        ibarotTextVC.copyWith()
    }

    func searchSidebarTrailing() {
        viewerSplitVC.sidebarVC.unhideSearchField()
    }

    func displayAnnotations(_ sender: Any?) {
        if let panel = AnnotationsVC.panel {
            panel.makeKeyAndOrderFront(sender)
            return
        }

        let vc: AnnotationsVC

        if SharedPopover.annotationsVC == nil {
            vc = AnnotationsVC()
            SharedPopover.annotationsVC = vc
        } else {
            vc = SharedPopover.annotationsVC!
        }

        vc.dataSource.delegate = ibarotTextVC

        if sender as? NSButton == nil,
            AnnotationsVC.panel == nil
        {
            let panel = NSPanel()
            panel.styleMask.insert([.utilityWindow, .resizable, .closable])
            panel.isFloatingPanel = true
            panel.title = "Annotations".localized
            panel.delegate = vc
            panel.contentViewController = vc
            panel.makeKeyAndOrderFront(sender)
            vc.shareBtn.isHidden = false
            vc.windowBtn.isHidden = true
            vc.setting.isHidden = false
            panel.setFrameAutosaveName("AnnotationsPanel")
            AnnotationsVC.panel = panel
            return
        } else if let panel = AnnotationsVC.panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        guard let button = sender as? NSButton else {
            return
        }

        let popover = SharedPopover.annotationsPopover
        popover.contentViewController = vc
        popover.show(relativeTo: button.frame, of: button, preferredEdge: .minY)
    }

    func searchCurrentBook(_ sender: NSButton) {
        if optSearchPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            optSearchPopover = popover
        }

        guard let optSearchPopover else { return }

        if optSearch == nil {
            let vc = OptionSearchVC()
            vc.view.frame = NSRect(x: 0, y: 0, width: 350, height: 300)
            optSearch = vc
        }

        guard let optSearch,
            let bkId = ibarotTextVC.textView.bkId
        else {
            ReusableFunc.showAlert(
                title: NSLocalizedString("noBookSelectedTitle", comment: ""),
                message: NSLocalizedString("noBookSelectedDesc", comment: "")
            )
            return
        }

        optSearch.bkId = "b\(bkId)"

        optSearchPopover.contentViewController = optSearch

        optSearchPopover.show(
            relativeTo: sender.bounds,
            of: sender,
            preferredEdge: .maxY
        )
        optSearch.compactButton()

        optSearch.onSelectedItem = { id, query in
            Task.detached { [weak self] in
                await self?.ibarotTextVC.didSelectResult(
                    for: id,
                    highlightText: query
                )
            }
        }

        optSearch.onCleanUp = { [weak self] in
            self?.optSearchPopover?.performClose(sender)
            self?.optSearch = nil
            self?.optSearchPopover = nil
        }
    }
}
