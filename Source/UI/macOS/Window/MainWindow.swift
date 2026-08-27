//
//  MainWindow.swift
//  maktab
//
//  Fix SegmentedControl State on Multi Window
//

import Cocoa

class MainWindow: NSWindow {
    private var toolbarConfigured = false
    private weak var modeSelectorControl: NSSegmentedControl?

    // MARK: - Single Container (state terjaga)

    lazy var splitVC: SplitVC = .init()

    var currentMode: AppMode {
        splitVC.currentMode
    }

    static var rtl: Bool {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale.Language(identifier: languageCode).characterDirection == .rightToLeft
    }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        setFrameAutosaveName("MainWindow")
    }

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func becomeKey() {
        super.becomeKey()
        updateUI()
    }

    override func newWindowForTab(_ sender: Any?) {
        let newWindowController = WindowController()

        // Tambahkan sebagai tab
        if let newWindow = newWindowController.window as? MainWindow {
            addTabbedWindow(newWindow, ordered: .above)
            newWindow.setupContentView(restoreState: false)
            newWindow.makeKeyAndOrderFront(nil)
        }
    }

    override func toggleTabBar(_ sender: Any?) {
        super.toggleTabBar(sender)
        NotificationCenter.default.post(
            name: .windowTabBarDidChange, object: nil
        )
    }

    func setupContentView(restoreState: Bool = true) {
        let currentFrame = frame
        // Restore last mode
        splitVC.currentMode = UserDefaults.standard.lastAppMode

        if !restoreState {
            splitVC.setupForMode(currentMode)
            splitVC.setupAutoSave()
            splitVC.stateManager.setState(ReaderState(), for: currentMode)
        }
        contentViewController = splitVC

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
        mainToolbar.displayMode = .iconOnly

        if #available(macOS 15, *) {
            #if compiler(>=6.0)
            mainToolbar.allowsDisplayModeCustomization = true
            #endif
        }

        toolbar = mainToolbar
        toolbarConfigured = true
    }

    private func setupToolbarTargets() {
        guard let toolbar else { return }

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
              mode != currentMode
        else {
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

        if #available(macOS 26, *), !Self.rtl {
            items.append(.trackingSeparator)
        }

        items.append(contentsOf: [
            .searchContents,
            .sidebarTrailing,
            .flexibleSpace,
            .space,
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
        if #available(macOS 26.0, *), !Self.rtl {
            items.append(.trackingSeparator)
        }

        // Melanjutkan sisa item setelah separator
        items.append(contentsOf: [
            .searchContents,
            .sidebarTrailing,
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
            guard let rootSplitVC = contentViewController as? SplitVC, !Self.rtl else {
                return NSToolbarItem(itemIdentifier: itemIdentifier)
            }

            let viewerContainer = rootSplitVC.viewerSplitVC
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: viewerContainer.splitView,
                dividerIndex: 0
            )

        case .modeSelector:
            let control = makeModeSelector()
            modeSelectorControl = control
            let config = ViewToolbarItemConfig(
                identifier: .modeSelector,
                label: "Mode",
                paletteLabel: "Switch Mode",
                toolTip: control.toolTip,
                view: control,
                image: nil,
                isNavigational: true
            )
            return makeViewToolbarItem(config: config)

        case .navSegment:
            let control = makeNavSegment()
            let config = ViewToolbarItemConfig(
                identifier: .navSegment,
                label: "Navigasi",
                paletteLabel: "Navigasi",
                toolTip: control.toolTip,
                view: control,
                image: nil,
                isNavigational: false
            )
            return makeViewToolbarItem(config: config)

        default:
            return makeActionButtonToolbarItem(identifier: itemIdentifier) ?? NSToolbarItem(itemIdentifier: itemIdentifier)
        }
    }

    private struct ActionButtonConfig {
        let label: String
        let paletteLabel: String
        let systemImageName: String
        let action: Selector
        let tooltip: String
        let isNavigational: Bool
    }

    private static var actionButtonConfigs: [NSToolbarItem.Identifier: ActionButtonConfig] {
        [
            .sidebarLeading: ActionButtonConfig(
                label: "Library",
                paletteLabel: "Library",
                systemImageName: "sidebar.leading",
                action: #selector(MainWindow.sidebarLeadingToggle(_:)),
                tooltip: String(localized: "Library"),
                isNavigational: false
            ),
            .searchSidebarLeadingContent: ActionButtonConfig(
                label: "Search Book",
                paletteLabel: "Search Book",
                systemImageName: "line.3.horizontal.decrease.circle",
                action: #selector(MainWindow.hideLibrarySearchField(_:)),
                tooltip: String(localized: "Search Book"),
                isNavigational: false
            ),
            .bookInfo: ActionButtonConfig(
                label: "Info",
                paletteLabel: "Book Info",
                systemImageName: "info.circle",
                action: #selector(MainWindow.bookInfo(_:)),
                tooltip: String(localized: "Book Info"),
                isNavigational: false
            ),
            .searchField: ActionButtonConfig(
                label: "Search In Book",
                paletteLabel: "Search Current Book",
                systemImageName: "doc.text.magnifyingglass",
                action: #selector(MainWindow.searchPopover(_:)),
                tooltip: String(localized: .searchInThisBook),
                isNavigational: false
            ),
            .pageSlider: ActionButtonConfig(
                label: "Page",
                paletteLabel: "Page",
                systemImageName: "slider.horizontal.below.rectangle",
                action: #selector(MainWindow.navigationPage(_:)),
                tooltip: String(localized: "Navigation Page"),
                isNavigational: false
            ),
            .textViewOptions: ActionButtonConfig(
                label: "View",
                paletteLabel: "View",
                systemImageName: "textformat.size.ar",
                action: #selector(MainWindow.viewOptions(_:)),
                tooltip: String(localized: "View Options"),
                isNavigational: false
            ),
            .copyDetails: ActionButtonConfig(
                label: "Copy",
                paletteLabel: "Copy + Detail",
                systemImageName: "doc.on.clipboard",
                action: #selector(MainWindow.copyWith(_:)),
                tooltip: String(localized: "Copy"),
                isNavigational: false
            ),
            .displayNotations: ActionButtonConfig(
                label: "Annotations",
                paletteLabel: "Annotations",
                systemImageName: "quote.closing",
                action: #selector(MainWindow.displayAllNotations(_:)),
                tooltip: String(localized: "All Anotations"),
                isNavigational: false
            ),
            .searchContents: ActionButtonConfig(
                label: "Search Contents",
                paletteLabel: "Search Contents",
                systemImageName: "rectangle.and.text.magnifyingglass.rtl",
                action: #selector(MainWindow.searchSidebarTrailingContent(_:)),
                tooltip: String(localized: "Search Contents"),
                isNavigational: rtl
            ),
            .sidebarTrailing: ActionButtonConfig(
                label: "Contents",
                paletteLabel: "Contents",
                systemImageName: "sidebar.trailing",
                action: #selector(MainWindow.sidebarTrailing(_:)),
                tooltip: String(localized: "Contents"),
                isNavigational: rtl
            ),
        ]
    }

    private struct ViewToolbarItemConfig {
        let identifier: NSToolbarItem.Identifier
        let label: String
        let paletteLabel: String
        let toolTip: String?
        let view: NSView
        var image: NSImage? = nil
        var isNavigational: Bool = false
    }

    private func makeActionButtonToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        guard let config = Self.actionButtonConfigs[identifier] else { return nil }
        return makeButtonToolbarItem(
            identifier: identifier,
            config: config
        )
    }

    private func makeModeSelector() -> NSSegmentedControl {
        let images = [
            ReusableFunc.systemImage(named: "book"),
            ReusableFunc.systemImage(named: "text.viewfinder"),
            ReusableFunc.systemImage(named: "person.text.rectangle"),
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
        control.setAccessibilityLabel(String(localized: "Switch Mode"))
        control.toolTip = String(localized: "Switch Mode")
        control.setToolTip(String(localized: "Reader"), forSegment: 0)
        control.setToolTip(String(localized: "Search..."), forSegment: 1)
        control.setToolTip(String(localized: "Narrators"), forSegment: 2)
        return control
    }

    private func makeNavSegment() -> NSSegmentedControl {
        NSSegmentedControl.makeNavigationControl(
            target: self,
            action: #selector(pageControl(_:))
        )
    }

    private func makeButtonToolbarItem(
        identifier: NSToolbarItem.Identifier,
        config: ActionButtonConfig
    ) -> NSToolbarItem {
        let image = ReusableFunc.systemImage(named: config.systemImageName)
        let button = NSButton(image: image, target: self, action: config.action)
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown

        let viewConfig = ViewToolbarItemConfig(
            identifier: identifier,
            label: config.label,
            paletteLabel: config.paletteLabel,
            toolTip: config.tooltip,
            view: button,
            image: image,
            isNavigational: config.isNavigational
        )

        return makeViewToolbarItem(config: viewConfig)
    }

    private func makeViewToolbarItem(config: ViewToolbarItemConfig) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: config.identifier)
        item.label = config.label
        item.paletteLabel = config.paletteLabel
        item.toolTip = config.toolTip
        item.view = config.view
        item.isNavigational = config.isNavigational

        let menuItem = NSMenuItem(title: config.label, action: nil, keyEquivalent: "")
        menuItem.image = config.image
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
