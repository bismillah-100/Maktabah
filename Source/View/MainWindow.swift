//
//  MainWindow.swift
//  maktab
//
//  Simplified window dengan single container
//

import Cocoa

class MainWindow: NSWindow {
    private var toolbarConfigured = false
    private weak var modeSelectorControl: NSSegmentedControl?

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

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        self.setFrameAutosaveName("MainWindow")
    }

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func becomeKey() {
        super.becomeKey()
        updateUI()
    }

    func setupContentView(restoreState: Bool = true) {
        let currentFrame = frame
        // Restore last mode
        if !restoreState {
            splitVC.setupForMode(currentMode)
            splitVC.setupAutoSave()
            splitVC.stateManager.setState(ReaderState(), for: currentMode)
        }
        contentViewController = splitVC
        splitVC.currentMode = currentMode

        configureToolbarIfNeeded()

        // Restore frame
        setFrame(currentFrame, display: true, animate: false)

        if !restoreState {
            setupView()
        }
    }

    func setupView() {
        // Setup targets tanpa yield yang terlalu lama agar sinkron dengan restorasi
        setupToolbarTargets()
        updateUI()
    }

    func configureToolbarIfNeeded() {
        guard !toolbarConfigured else { return }

        let mainToolbar = NSToolbar(identifier: "MainToolbar")
        mainToolbar.autosavesConfiguration = true // Ini yang menangani simpan/restore otomatis
        mainToolbar.delegate = self
        mainToolbar.allowsUserCustomization = true
        
        if #available(macOS 15, *) {
            #if compiler(>=6.0)
            mainToolbar.allowsDisplayModeCustomization = true
            #endif
        }
        
        toolbar = mainToolbar
        toolbarConfigured = true
    }

    private func setupToolbarTargets() {
        guard let toolbar = toolbar else { return }

        // Set target/action langsung ke view dari masing-masing item
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
        updateDelegateAndSegment()
    }

    private func updateDelegateAndSegment() {
        setAnnotationsPanelDelegate()
        let selector =
            modeSelectorControl
            ?? (toolbar?.item(with: .modeSelector)?.view as? NSSegmentedControl)
        selector?.selectedSegment = currentMode.rawValue
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

// MARK: - Toolbar (Programmatic)
extension MainWindow: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var items: [NSToolbarItem.Identifier] = [
            .modeSelector,
            .sidebarTrackingSeparator,
            .sidebarLeading,
            .searchSidebarLeadingContent,
            .bookInfo,
            .navSegment,
            .copyDetails,
            .displayNotations,
            .searchField,
            .pageSlider,
            .textViewOptions,
        ]

        if #available(macOS 26, *) {
            items.append(.trackingSeparator)
        }

        items.append(contentsOf: [
            .searchContents,
            .sidebarTrailing,
            .flexibleSpace,
            .space
        ])

        return items
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var items: [NSToolbarItem.Identifier] = [
            .sidebarLeading,
            .searchSidebarLeadingContent,
            .sidebarTrackingSeparator,
            .modeSelector,
            .bookInfo,
            .textViewOptions,
            .copyDetails,
            .navSegment,
            .searchField,
            .pageSlider,
            .displayNotations,
        ]

        // Menyisipkan tepat setelah .displayNotations
        if #available(macOS 26.0, *) {
            items.append(.trackingSeparator)
        }

        // Melanjutkan sisa item setelah separator
        items.append(contentsOf: [
            .searchContents,
            .sidebarTrailing
        ])

        return items
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .sidebarTrackingSeparator:
            guard let rootSplitVC = contentViewController as? SplitVC else {
                return NSToolbarItem(itemIdentifier: itemIdentifier)
            }
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: rootSplitVC.splitView,
                dividerIndex: 0
            )

        case .trackingSeparator:
            // Pastikan pengecekan macOS yang benar (TrackingSeparator muncul di macOS 13+)
            guard let rootSplitVC = contentViewController as? SplitVC else {
                return NSToolbarItem(itemIdentifier: itemIdentifier)
            }

            let viewerContainer = rootSplitVC.viewerSplitVC
            let trackingSeparator = NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: viewerContainer.splitView,
                dividerIndex: 0
            )
            return trackingSeparator

        case .modeSelector:
            let control = makeModeSelector()
            modeSelectorControl = control
            return makeViewToolbarItem(
                identifier: .modeSelector,
                label: "Mode",
                paletteLabel: "Switch Mode",
                toolTip: nil,
                view: control,
                image: nil,
                isNavigational: true
            )

        case .navSegment:
            let control = makeNavSegment()
            return makeViewToolbarItem(
                identifier: .navSegment,
                label: "Navigasi",
                paletteLabel: "Navigasi",
                toolTip: nil,
                view: control,
                image: nil,
                isNavigational: false
            )

        case .sidebarLeading:
            return makeButtonToolbarItem(
                identifier: .sidebarLeading,
                label: "Library",
                paletteLabel: "Library",
                systemImageName: "sidebar.leading",
                action: #selector(sidebarLeadingToggle(_:)),
                isNavigational: false
            )

        case .searchSidebarLeadingContent:
            return makeButtonToolbarItem(
                identifier: .searchSidebarLeadingContent,
                label: "Search Book",
                paletteLabel: "Search Book",
                systemImageName: "line.3.horizontal.decrease.circle",
                action: #selector(hideLibrarySearchField(_:)),
                isNavigational: false
            )

        case .bookInfo:
            return makeButtonToolbarItem(
                identifier: .bookInfo,
                label: "Info",
                paletteLabel: "Book Info",
                systemImageName: "info.circle",
                action: #selector(bookInfo(_:)),
                isNavigational: false
            )

        case .searchField:
            return makeButtonToolbarItem(
                identifier: .searchField,
                label: "Search In Book",
                paletteLabel: "Search Current Book",
                systemImageName: "doc.text.magnifyingglass",
                action: #selector(searchPopover(_:)),
                isNavigational: false
            )

        case .pageSlider:
            return makeButtonToolbarItem(
                identifier: .pageSlider,
                label: "Page",
                paletteLabel: "Page",
                systemImageName: "slider.horizontal.below.rectangle",
                action: #selector(navigationPage(_:)),
                isNavigational: false
            )

        case .textViewOptions:
            return makeButtonToolbarItem(
                identifier: .textViewOptions,
                label: "View",
                paletteLabel: "View",
                systemImageName: "textformat.size.ar",
                action: #selector(viewOptions(_:)),
                isNavigational: false
            )

        case .copyDetails:
            return makeButtonToolbarItem(
                identifier: .copyDetails,
                label: "Copy",
                paletteLabel: "Copy + Detail",
                systemImageName: "doc.on.clipboard",
                action: #selector(copyWith(_:)),
                isNavigational: false
            )

        case .displayNotations:
            return makeButtonToolbarItem(
                identifier: .displayNotations,
                label: "Annotations",
                paletteLabel: "Annotations",
                systemImageName: "quote.closing",
                action: #selector(displayAllNotations(_:)),
                isNavigational: false
            )

        case .searchContents:
            return makeButtonToolbarItem(
                identifier: .searchContents,
                label: "Search Contents",
                paletteLabel: "Search Contents",
                systemImageName: "rectangle.and.text.magnifyingglass.rtl",
                action: #selector(searchSidebarTrailingContent(_:)),
                isNavigational: Self.rtl
            )

        case .sidebarTrailing:
            return makeButtonToolbarItem(
                identifier: .sidebarTrailing,
                label: "Contents",
                paletteLabel: "Contents",
                systemImageName: "sidebar.trailing",
                action: #selector(sidebarTrailing(_:)),
                isNavigational: Self.rtl
            )

        default:
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
    }

    private func makeModeSelector() -> NSSegmentedControl {
        let images = [
            ReusableFunc.systemImage(named: "book"),
            ReusableFunc.systemImage(named: "text.viewfinder"),
            ReusableFunc.systemImage(named: "person.text.rectangle")
        ]

        let control = NSSegmentedControl()
        control.segmentCount = images.count
        control.segmentStyle = .automatic
        control.trackingMode = .selectOne
        for (index, image) in images.enumerated() {
            control.setImage(image, forSegment: index)
            control.setWidth(23, forSegment: index)
        }
        control.selectedSegment = currentMode.rawValue
        control.target = self
        control.action = #selector(modeSelectorChanged(_:))
        return control
    }

    private func makeNavSegment() -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = 2
        control.trackingMode = .momentary
        control.userInterfaceLayoutDirection = .leftToRight
        control.setImage(ReusableFunc.systemImage(named: "arrow.left"), forSegment: 0)
        control.setImage(ReusableFunc.systemImage(named: "arrow.right"), forSegment: 1)
        control.setWidth(23, forSegment: 0)
        control.setWidth(23, forSegment: 1)
        control.target = self
        control.action = #selector(pageControl(_:))
        return control
    }

    private func makeButtonToolbarItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        paletteLabel: String,
        systemImageName: String,
        action: Selector,
        isNavigational: Bool
    ) -> NSToolbarItem {
        let image = ReusableFunc.systemImage(named: systemImageName)
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown

        return makeViewToolbarItem(
            identifier: identifier,
            label: label,
            paletteLabel: paletteLabel,
            toolTip: nil,
            view: button,
            image: image,
            isNavigational: isNavigational
        )
    }

    private func makeViewToolbarItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        paletteLabel: String,
        toolTip: String?,
        view: NSView,
        image: NSImage?,
        isNavigational: Bool
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = paletteLabel
        item.toolTip = toolTip
        item.view = view
        item.isNavigational = isNavigational

        let menuItem = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        menuItem.image = image
        item.menuFormRepresentation = menuItem
        return item
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
