//
//  AnnotationsVC.swift
//  maktab
//
//  Created by MacBook on 15/12/25.
//  Granular UI Update
//

import Cocoa

class AnnotationsVC: NSViewController {
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var shareBtn: NSPopUpButton!
    @IBOutlet weak var windowBtn: NSButton!
    @IBOutlet weak var setting: NSPopUpButton!
    @IBOutlet weak var sortingButton: NSPopUpButton!
    @IBOutlet weak var floatMenuItem: NSMenuItem!
    @IBOutlet weak var hideOnMenuItem: NSMenuItem!
    @IBOutlet weak var searchField: DSFSearchField!
    @IBOutlet weak var xBtn: NSButton!
    @IBOutlet weak var headerStackView: NSStackView!
    @IBOutlet weak var rootStackView: NSStackView!
    @IBOutlet weak var scrollView: NSScrollView!
    @IBOutlet weak var topConstraintHeaderStack: NSLayoutConstraint!
    
    @IBOutlet weak var annotationLineMenu: NSMenu!
    @IBOutlet weak var contextLineMenu: NSMenu!
    @objc dynamic var isRowUnselected: Bool = true

    var floatPanel: Bool {
        UserDefaults.standard.annotationFloatWindow
    }

    var hideOnPanel: Bool {
        UserDefaults.standard.annotationHideWindow
    }

    static var panel: NSPanel?

    let dataSource: AnnotationOutlineDataSource = .init()
    private var tagPopover: NSPopover?

    var popover: Bool = true
    var isDataLoaded = false

    private enum SortMenuTag {
        static let fieldCreatedAt = 101
        static let fieldContext = 102
        static let fieldPage = 103
        static let fieldPart = 104
        static let ascending = 201
        static let descending = 202
        static let groupingBook = 301
        static let groupingTag = 302
    }

    private let defaults = UserDefaults.standard

    private var selectedSortField: AnnotationSortField {
        get { defaults.selectedAnnSortField }
        set { defaults.selectedAnnSortField = newValue }
    }

    private var selectedSortAscending: Bool {
        get { defaults.selectedAnnAscending }
        set { defaults.selectedAnnAscending = newValue }
    }

    private var selectedGroupingMode: AnnotationGroupingMode {
        get { defaults.selectedAnnGroupingMode }
        set { defaults.selectedAnnGroupingMode = newValue }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        floatMenuItem.state = .on
        setupSortMenu()
        ReusableFunc.setupSearchField(searchField)
        outlineView.allowsMultipleSelection = true
        dataSource.onAddTagsRequested = { [weak self] annotationIDs, anchorRect in
            self?.presentTagPopover(
                mode: .add,
                annotationIDs: annotationIDs,
                anchorRect: anchorRect
            )
        }
        dataSource.onRemoveTagsRequested = { [weak self] annotationIDs, anchorRect in
            self?.presentTagPopover(
                mode: .remove,
                annotationIDs: annotationIDs,
                anchorRect: anchorRect
            )
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if isDataLoaded { return }
        ReusableFunc.showProgressWindow(view)
        xBtn.isHidden = popover
        dataSource.onSelectItem = { [weak self] row in
            self?.isRowUnselected = row == -1
        }
        outlineView.deselectAll(nil)
        dataSource.outlineView = outlineView
        rootStackView.insertArrangedSubview(headerStackView, at: 0)
        Task { [weak self] in
            guard let self else { return }
            setupMaxLine()
            reloadAnnotations(nil)
            dataSource.setupOutlineMenu()
            await MainActor.run { [weak self] in
                guard let self else { return }
                ReusableFunc.closeProgressWindow(view)
                isDataLoaded = true
            }
        }
    }

    @IBAction func reloadAnnotations(_ sender: Any?) {
        if sender != nil {
            AnnotationManager.shared.connect()
        }
        outlineView.dataSource = dataSource
        outlineView.delegate = dataSource
        outlineView.usesAutomaticRowHeights = true
        selectedGroupingMode == .book
            ? dataSource.reload()
            : dataSource.updateGrouping(mode: selectedGroupingMode)

        dataSource.updateSorting(field: selectedSortField, isAscending: selectedSortAscending)
    }

    @IBAction func searchFieldDidChange(_ sender: NSSearchField) {
        dataSource.viewModel.searchText = sender.stringValue
    }

    @objc func contextMenuAction(_ sender: NSMenuItem) {
        guard let lineLimit = Int(sender.title) else { return }
        defaults.ctxMaxNumberOfLines = lineLimit
        updateLineMenuState()
        refreshAnnotationRowHeights()
    }

    @objc func annotationMenuAction(_ sender: NSMenuItem) {
        guard let lineLimit = Int(sender.title) else { return }
        defaults.annMaxNumberOfLines = lineLimit
        updateLineMenuState()
        refreshAnnotationRowHeights()
    }

    private func setupMaxLine() {
        for i in 1...2 {
            let menuItem = NSMenuItem(
                title: "\(i)",
                action: #selector(contextMenuAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            // 'at' menentukan posisi index di dalam menu
            contextLineMenu.addItem(menuItem)
        }

        for i in 1...4 {
            let menuItem = NSMenuItem(
                title: "\(i)",
                action: #selector(annotationMenuAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self

            annotationLineMenu.addItem(menuItem)
        }

        updateLineMenuState()
    }

    private func updateLineMenuState() {
        for item in contextLineMenu.items {
            item.state = item.title == "\(defaults.ctxMaxNumberOfLines)"
                ? .on : .off
        }

        for item in annotationLineMenu.items {
            item.state = item.title == "\(defaults.annMaxNumberOfLines)"
                ? .on : .off
        }
    }

    private func refreshAnnotationRowHeights() {
        outlineView.reloadData()
        guard outlineView.numberOfRows > 0 else { return }
        outlineView.noteHeightOfRows(
            withIndexesChanged: IndexSet(integersIn: 0..<outlineView.numberOfRows)
        )
    }

    private func setupSortMenu() {
        guard let menu = sortingButton.menu else { return }

        let items: [(String, Int, AnnotationSortField)] = [
            ("Context".localized, SortMenuTag.fieldContext, .context),
            ("Date Created".localized, SortMenuTag.fieldCreatedAt, .createdAt),
            ("Page".localized, SortMenuTag.fieldPage, .page),
            ("Part".localized, SortMenuTag.fieldPart, .part),
        ]
        for (title, tag, _) in items {
            let item = NSMenuItem(
                title: title,
                action: #selector(selectSortField(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = tag
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let orders: [(String, Int)] = [
            ("Ascending".localized, SortMenuTag.ascending),
            ("Descending".localized, SortMenuTag.descending),
        ]
        for (title, tag) in orders {
            let item = NSMenuItem(
                title: title,
                action: #selector(selectSortOrder(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = tag
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let groupingItems: [(String, Int)] = [
            ("Group by Book".localized, SortMenuTag.groupingBook),
            ("Group by Tag".localized, SortMenuTag.groupingTag),
        ]
        for (title, tag) in groupingItems {
            let item = NSMenuItem(
                title: title,
                action: #selector(selectGroupingMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = tag
            menu.addItem(item)
        }
        sortingButton.image = NSImage(
            systemSymbolName: "arrow.up.arrow.down.circle",
            accessibilityDescription: "Sort"
        )
        sortingButton.title = ""
        updateSortMenuState()
    }

    @objc private func selectSortField(_ sender: NSMenuItem) {
        selectedSortField = switch sender.tag {
        case SortMenuTag.fieldCreatedAt: .createdAt
        case SortMenuTag.fieldContext: .context
        case SortMenuTag.fieldPage: .page
        case SortMenuTag.fieldPart: .part
        default: .createdAt
        }
        applySorting()
    }

    @objc private func selectSortOrder(_ sender: NSMenuItem) {
        selectedSortAscending = sender.tag == SortMenuTag.ascending
        applySorting()
    }

    @objc private func selectGroupingMode(_ sender: NSMenuItem) {
        switch sender.tag {
        case SortMenuTag.groupingBook:
            selectedGroupingMode = .book
        case SortMenuTag.groupingTag:
            selectedGroupingMode = .tag
        default:
            return
        }

        dataSource.updateGrouping(mode: selectedGroupingMode)
        if !searchField.stringValue.isEmpty {
            outlineView.expandItem(nil, expandChildren: true)
        }
        updateSortMenuState()
    }

    private func applySorting() {
        dataSource.updateSorting(
            field: selectedSortField,
            isAscending: selectedSortAscending
        )
        if !searchField.stringValue.isEmpty {
            outlineView.expandItem(nil, expandChildren: true)
        }
        updateSortMenuState()
    }

    private func updateSortMenuState() {
        guard let menu = sortingButton.menu else { return }
        for item in menu.items { item.state = .off }
        menu.item(
            withTag: selectedSortAscending
                ? SortMenuTag.ascending : SortMenuTag.descending
        )?.state = .on
        menu.item(
            withTag: selectedGroupingMode == .book
                ? SortMenuTag.groupingBook : SortMenuTag.groupingTag
        )?.state = .on
        let fieldTag: Int = {
            switch selectedSortField {
            case .createdAt: return SortMenuTag.fieldCreatedAt
            case .context: return SortMenuTag.fieldContext
            case .page: return SortMenuTag.fieldPage
            case .part: return SortMenuTag.fieldPart
            }
        }()
        menu.item(withTag: fieldTag)?.state = .on
    }

    private func presentTagPopover(
        mode: AnnotationTagVC.Mode,
        annotationIDs: [Int64],
        anchorRect: NSRect
    ) {
        tagPopover?.performClose(nil)

        let tagVC = AnnotationTagVC()
        tagVC.mode = mode
        tagVC.annotationIDs = annotationIDs
        tagVC.availableTags = switch mode {
        case .add:
            AnnotationManager.shared.allTagNames()
        case .remove:
            commonTags(for: annotationIDs)
        }
        tagVC.onSubmit = { [weak self] mode, tags, annotationIDs in
            self?.applyTags(tags, mode: mode, to: annotationIDs)
        }
        tagVC.onCancel = { [weak self] in
            self?.tagPopover = nil
        }

        let popover = NSPopover()
        popover.contentViewController = tagVC
        popover.behavior = .transient
        popover.show(relativeTo: anchorRect, of: outlineView, preferredEdge: .maxY)
        tagPopover = popover
    }

    private func applyTags(
        _ tags: [String],
        mode: AnnotationTagVC.Mode,
        to annotationIDs: [Int64]
    ) {
        guard !annotationIDs.isEmpty else { return }

        do {
            switch mode {
            case .add:
                for tag in tags {
                    try AnnotationManager.shared.addTag(tag, toAnnotationIDs: annotationIDs)
                }
            case .remove:
                for tag in tags {
                    try AnnotationManager.shared.removeTag(tag, fromAnnotationIDs: annotationIDs)
                }
            }
            tagPopover?.performClose(nil)
        } catch {
            ReusableFunc.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private func commonTags(for annotationIDs: [Int64]) -> [String] {
        let annotations = annotationIDs.compactMap {
            AnnotationManager.shared.loadAnnotationById($0)
        }
        guard let firstAnnotation = annotations.first else { return [] }

        let commonNormalized = annotations.dropFirst().reduce(
            Set(firstAnnotation.tags.map(normalizedTagName))
        ) { partialResult, annotation in
            partialResult.intersection(Set(annotation.tags.map(normalizedTagName)))
        }

        return firstAnnotation.tags.filter {
            commonNormalized.contains(normalizedTagName($0))
        }
    }

    private func normalizedTagName(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    @IBAction func saveRTFToFile(_ sender: Any?) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.rtf]
        savePanel.nameFieldStringValue = "Exported_Annotations.rtf"

        savePanel.begin { [weak self] response in
            if let self, response == .OK, let url = savePanel.url {
                // Ambil data dari semua root nodes
                if let data = dataSource.exportToRTF() {
                    do {
                        try data.write(to: url)
                        #if DEBUG
                        print("Berhasil ekspor ke: \(url.path)")
                        #endif
                    } catch {
                        ReusableFunc.showAlert(title: "Error", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    @IBAction func floatPanel(_ sender: NSMenuItem) {
        let currentState = floatMenuItem.state
        floatMenuItem.state = currentState == .on ? .off : .on

        let on = floatMenuItem.state == .on ? true : false
        Self.panel?.isFloatingPanel = on
        UserDefaults.standard.annotationFloatWindow = on
    }

    @IBAction func hideOnPanel(_ sender: NSMenuItem) {
        let currentState = hideOnMenuItem.state
        hideOnMenuItem.state = currentState == .on ? .off : .on

        let on = sender.state == .on ? true : false
        Self.panel?.hidesOnDeactivate = on
        UserDefaults.standard.annotationHideWindow = on
    }

    @IBAction func revealInFinder(_ sender: Any?) {
        if let annotationsFolder = AppConfig.folder(
                for: AppConfig.annotationsAndResultsFolder
            ) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: annotationsFolder.path)
        }
    }

    @IBAction func openInNewWindow(_ sender: Any) {
        if let window = view.window {
            window.makeFirstResponder(nil)
        }

        SharedPopover.annotationsPopover.performClose(sender)

        DispatchQueue.main.async { [weak self] in
            self?.openAsPanel()
        }
    }

    func openAsPanel() {
        let panel = NSPanel()
        panel.styleMask.insert([.fullSizeContentView, .titled])
        panel.styleMask.insert([.utilityWindow, .resizable, .closable])
        panel.title = "Annotations".localized
        panel.delegate = self
        shareBtn.isHidden = false
        windowBtn.isHidden = true
        setting.isHidden = false
        floatMenuItem.isHidden = false
        hideOnMenuItem.isHidden = false
        floatMenuItem.state = floatPanel ? .on : .off
        hideOnMenuItem.state = hideOnPanel ? .on : .off
        panel.contentViewController = self
        panel.isFloatingPanel = floatPanel
        panel.hidesOnDeactivate = hideOnPanel
        panel.makeKeyAndOrderFront(nil)
        panel.setFrameAutosaveName("AnnotationsPanel")
        Self.panel = panel

        setupLayoutPanel(panel)
    }

    func setupLayoutPanel(_ panel: NSPanel) {
        rootStackView.removeArrangedSubview(scrollView)
        rootStackView.removeArrangedSubview(headerStackView)
        rootStackView.removeFromSuperview()

        topConstraintHeaderStack.isActive = false

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.widthAnchor.constraint(equalTo: view.widthAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let titlebarAccessoryView = NSTitlebarAccessoryViewController()
        titlebarAccessoryView.view = headerStackView
        titlebarAccessoryView.layoutAttribute = .bottom
        if #available(macOS 26.1, *) {
            titlebarAccessoryView.preferredScrollEdgeEffectStyle = .soft
        } else {
            let oldF = titlebarAccessoryView.view.frame
            titlebarAccessoryView.view.frame = NSRect(
                origin: oldF.origin,
                size: CGSize(
                    width: oldF.width,
                    height: oldF.height + 14
                )
            )
        }

        panel.addTitlebarAccessoryViewController(titlebarAccessoryView)
    }

    deinit {
        #if DEBUG
        print("annotationsVC deinit")
        #endif
    }
}

extension AnnotationsVC: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        tagPopover?.performClose(nil)
        SharedPopover.annotationsVC = nil
        SharedPopover.annotationsPopover.contentViewController = nil
        Self.panel?.delegate = nil
        Self.panel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        outlineView.deselectAll(nil)
    }
}
