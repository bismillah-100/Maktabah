//
//  AnnotationsVC.swift
//  maktab
//
//  Created by MacBook on 15/12/25.
//  Granular UI Update
//

import Cocoa
import SwiftUI

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
    private var tagFilterBar: NSStackView?
    private var chipsStackView: NSStackView?
    private var chipsScrollView: NSScrollView?
    private var filterButton: NSButton?
    private var modeButton: NSButton?
    private var tagSelectionPopover: NSPopover?
    private var hasPerformedInitialChipScroll = false

    var popover: Bool = true
    var isDataLoaded = false

    private lazy var scopePanel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .windowBackgroundColor
        panel.level = .popUpMenu

        let contentView = NSView()
        contentView.addSubview(scopeSegment)

        scopeSegment.translatesAutoresizingMaskIntoConstraints = false
        scopeSegment.trackingMode = .selectOne
        if #available(macOS 26, *) { scopeSegment.borderShape = .capsule }

        NSLayoutConstraint.activate([
            scopeSegment.centerXAnchor.constraint(
                equalTo: contentView.centerXAnchor
            ),
            scopeSegment.centerYAnchor.constraint(
                equalTo: contentView.centerYAnchor
            ),
            scopeSegment.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 8
            ),
            scopeSegment.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -8
            ),
        ])

        panel.contentView = contentView
        return panel
    }()

    private lazy var titlebarRootStack: NSStackView = {
        let titlebarRootStack = NSStackView()
        titlebarRootStack.edgeInsets.top = 10
        titlebarRootStack.edgeInsets.bottom = 2
        titlebarRootStack.orientation = .vertical
        titlebarRootStack.spacing = 6
        return titlebarRootStack
    }()

    private lazy var scopeSegment: NSSegmentedControl = {
        let scopes = AnnotationSearchScope.allCases
        let segment = NSSegmentedControl(
            labels: scopes.map(\.title),
            trackingMode: .selectOne, target: self,
            action: #selector(searchScopeChanged(_:))
        )
        segment.segmentStyle = .roundRect
        segment.controlSize = .small
        segment.refusesFirstResponder = true
        return segment
    }()

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
        setupShareMenu()
        setupImportMenu()
        ReusableFunc.setupSearchField(searchField)
        outlineView.allowsMultipleSelection = true
        searchField.delegate = self
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
        dataSource.viewModel.onTagsChanged = { [weak self] tags in
            self?.updateChips(allTags: tags)
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
        createRootTitlebarStack()
        rootStackView.insertArrangedSubview(titlebarRootStack, at: 0)
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

    override func viewDidDisappear() {
        super.viewDidDisappear()
        removeScopePanelFromWindow()
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
        for i in 1 ... 2 {
            let menuItem = NSMenuItem(
                title: "\(i)",
                action: #selector(contextMenuAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            // 'at' menentukan posisi index di dalam menu
            contextLineMenu.addItem(menuItem)
        }

        for i in 1 ... 4 {
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
            withIndexesChanged: IndexSet(integersIn: 0 ..< outlineView.numberOfRows)
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
        for item in menu.items {
            item.state = .off
        }
        menu.item(
            withTag: selectedSortAscending
                ? SortMenuTag.ascending : SortMenuTag.descending
        )?.state = .on
        menu.item(
            withTag: selectedGroupingMode == .book
                ? SortMenuTag.groupingBook : SortMenuTag.groupingTag
        )?.state = .on
        let fieldTag: Int = switch selectedSortField {
        case .createdAt: SortMenuTag.fieldCreatedAt
        case .context: SortMenuTag.fieldContext
        case .page: SortMenuTag.fieldPage
        case .part: SortMenuTag.fieldPart
        }
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
            updateChips(allTags: dataSource.viewModel.availableTags)
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

    private func setupImportMenu() {
        guard let menu = setting.menu,
              menu.items.count >= 5
        else { return }

        menu.insertItem(.separator(), at: 5)

        let importJSONItem = NSMenuItem(
            title: "Import from JSON...".localized,
            action: #selector(importJSON(_:)),
            keyEquivalent: ""
        )
        importJSONItem.target = self
        menu.insertItem(importJSONItem, at: 6)
    }

    private func setupShareMenu() {
        guard let menu = shareBtn.menu else { return }
        let exportJSONItem = NSMenuItem(
            title: "Export to JSON...".localized,
            action: #selector(exportSelectedJSON(_:)),
            keyEquivalent: ""
        )
        exportJSONItem.target = self
        menu.addItem(exportJSONItem)
    }

    private func selectedOrEffectiveNodes() -> [AnnotationNode] {
        let selectedIndexes = outlineView.selectedRowIndexes
        if !selectedIndexes.isEmpty {
            return selectedIndexes.compactMap { outlineView.item(atRow: $0) as? AnnotationNode }
        }
        let clickedRow = outlineView.clickedRow
        if clickedRow >= 0, let item = outlineView.item(atRow: clickedRow) as? AnnotationNode {
            return [item]
        }
        return []
    }

    private func extractAnnotations(from nodes: [AnnotationNode]) -> [Annotation] {
        var result: [Annotation] = []
        var seenKeys = Set<String>()

        func collect(node: AnnotationNode) {
            if let ann = node.annotation {
                let key = "\(ann.bkId)_\(ann.contentId)_\(ann.range.location)_\(ann.range.length)"
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    result.append(ann)
                }
            }
            for child in node.children {
                collect(node: child)
            }
        }

        for node in nodes {
            collect(node: node)
        }
        return result
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

    @IBAction func exportSelectedJSON(_ sender: Any?) {
        let nodes = selectedOrEffectiveNodes()
        let annotations = extractAnnotations(from: nodes)
        guard !annotations.isEmpty else {
            ReusableFunc.showAlert(
                title: "No Selection".localized,
                message: "Please select one or more annotations or books to export.".localized
            )
            return
        }

        guard let jsonString = AnnotationJsonSerializer.encode(annotations: annotations),
              let jsonData = jsonString.data(using: .utf8)
        else {
            ReusableFunc.showAlert(
                title: "Error".localized,
                message: "Failed to encode annotations to JSON.".localized
            )
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "maktabah_annotations.json"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try jsonData.write(to: url)
                #if DEBUG
                print("Exported \(annotations.count) annotations to: \(url.path)")
                #endif
            } catch {
                ReusableFunc.showAlert(title: "Error".localized, message: error.localizedDescription)
            }
        }
    }

    @IBAction func importJSON(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        openPanel.begin { response in
            guard response == .OK, let url = openPanel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let decoded = try AnnotationJsonSerializer.decode(from: data)
                guard !decoded.isEmpty else {
                    ReusableFunc.showAlert(
                        title: "Import Annotations".localized,
                        message: "No annotations found in the selected file.".localized
                    )
                    return
                }

                let alert = NSAlert()
                alert.messageText = "Import Annotations".localized
                alert.informativeText = "Some annotations may already exist. How would you like to handle duplicates?".localized
                alert.addButton(withTitle: "Overwrite Existing".localized)
                alert.addButton(withTitle: "Skip Duplicates".localized)
                alert.addButton(withTitle: "Cancel".localized)

                let alertResponse = alert.runModal()
                guard alertResponse != .alertThirdButtonReturn else { return }

                let overwrite = (alertResponse == .alertFirstButtonReturn)
                let count = try AnnotationManager.shared.importAnnotations(decoded, overwrite: overwrite)

                let successMsg = String(format: "%d annotations imported successfully".localized, count)
                ReusableFunc.showAlert(
                    title: "Import Annotations".localized,
                    message: successMsg
                )
            } catch {
                ReusableFunc.showAlert(
                    title: "Import Failed".localized,
                    message: error.localizedDescription
                )
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

    private func createRootTitlebarStack() {
        if !titlebarRootStack.arrangedSubviews.isEmpty { return }
        titlebarRootStack.addArrangedSubview(headerStackView)
        let filterBar = createTagFilterBar()
        titlebarRootStack.addArrangedSubview(filterBar)

        dataSource.viewModel.onTagsChanged = { [weak self] tags in
            self?.updateChips(allTags: tags)
        }

        updateChips(allTags: dataSource.viewModel.availableTags)
    }

    private func createTagFilterBar() -> NSStackView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.userInterfaceLayoutDirection = .rightToLeft
        bar.spacing = 8
        bar.alignment = .centerY
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 34).isActive = true

        // Filter button
        let filterBtn = NSButton()
        filterBtn.bezelStyle = .toolbar
        filterBtn.image = .init(
            systemSymbolName: "tag",
            accessibilityDescription: "Filter Tags"
        )
        filterBtn.isBordered = false
        filterBtn.target = self
        filterBtn.action = #selector(showTagSelectionPopover(_:))
        filterBtn.toolTip = "Filter Tags".localized
        filterBtn.setContentHuggingPriority(.required, for: .horizontal)
        filterBtn.translatesAutoresizingMaskIntoConstraints = false
        filterBtn.widthAnchor.constraint(
            equalToConstant: 23
        ).isActive = true
        filterButton = filterBtn

        // Mode button (AND/OR toggle)
        let modeBtn = NSButton()
        modeBtn.bezelStyle = .accessoryBar
        modeBtn.setButtonType(.pushOnPushOff)
        let isAnd = dataSource.viewModel.tagFilterMode == .and
        modeBtn.image = NSImage(
            systemSymbolName: "line.3.horizontal.decrease",
            accessibilityDescription: "Filter Mode"
        )
        modeBtn.isBordered = false
        modeBtn.target = self
        modeBtn.action = #selector(toggleFilterMode(_:))
        modeBtn.toolTip = .init(localized: isAnd ? .and : .or)
        modeBtn.setContentHuggingPriority(.required, for: .horizontal)
        modeBtn.translatesAutoresizingMaskIntoConstraints = false
        modeBtn.widthAnchor.constraint(
            equalToConstant: 23
        ).isActive = true
        modeButton = modeBtn

        // Chips scroll view
        let chipsStack = NSStackView()
        chipsStack.userInterfaceLayoutDirection = .rightToLeft
        chipsStack.orientation = .horizontal
        chipsStack.alignment = .centerY
        chipsStack.spacing = 4
        chipsStack.translatesAutoresizingMaskIntoConstraints = true
        chipsStack.autoresizingMask = [.height]
        chipsStackView = chipsStack

        let chipScroll = NSScrollView()
        chipScroll.userInterfaceLayoutDirection = .rightToLeft
        chipScroll.hasHorizontalScroller = false
        chipScroll.hasVerticalScroller = false
        chipScroll.horizontalScrollElasticity = .allowed
        chipScroll.verticalScrollElasticity = .none
        chipScroll.drawsBackground = false
        chipScroll.translatesAutoresizingMaskIntoConstraints = false
        chipScroll.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let clipView = RightAlignedClipView()
        clipView.userInterfaceLayoutDirection = .rightToLeft
        clipView.drawsBackground = false
        chipScroll.contentView = clipView
        chipScroll.documentView = chipsStack

        chipsScrollView = chipScroll

        bar.addArrangedSubview(filterBtn)
        bar.addArrangedSubview(modeBtn)
        bar.addArrangedSubview(chipScroll)

        tagFilterBar = bar
        return bar
    }

    private func makeChipButton(for tag: String) -> NSButton {
        let btn = NSButton()
        btn.title = tag
        btn.setButtonType(.pushOnPushOff)
        btn.bezelStyle = .badge
        btn.isBordered = true
        btn.font = .systemFont(ofSize: 12)
        btn.target = self
        btn.action = #selector(chipToggled(_:))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setContentHuggingPriority(.required, for: .vertical)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .vertical)
        btn.heightAnchor.constraint(equalToConstant: 20).isActive = true

        if #available(macOS 26, *) {
            btn.borderShape = .capsule
        }
        return btn
    }

    /// Incrementally update chips: add new, remove stale, preserve existing
    private func updateChips(allTags: [String]) {
        guard let chipsStack = chipsStackView else { return }

        let existingChips = chipsStack.arrangedSubviews.compactMap { $0 as? NSButton }
        let existingTitles = Set(existingChips.map(\.title))
        let newTagsSet = Set(allTags)
        let isFirstLoad = !hasPerformedInitialChipScroll && !allTags.isEmpty

        // Remove chips whose tags no longer exist
        for chip in existingChips where !newTagsSet.contains(chip.title) {
            chipsStack.removeArrangedSubview(chip)
            chip.removeFromSuperview()
        }

        // Add new chips (insert in sorted order)
        for tag in allTags where !existingTitles.contains(tag) {
            let chip = makeChipButton(for: tag)
            chip.state = dataSource.viewModel.selectedTags.contains(tag) ? .on : .off
            // Find sorted insertion position
            let insertIdx = chipsStack
                .arrangedSubviews.compactMap { $0 as? NSButton }.enumerated()
                .first { tag.localizedCaseInsensitiveCompare($0.element.title) == .orderedAscending }?
                .offset ?? chipsStack.arrangedSubviews.count
            chipsStack.insertArrangedSubview(chip, at: insertIdx)
        }

        // Sync selection state of existing chips
        for chip in chipsStack.arrangedSubviews.compactMap({ $0 as? NSButton }) {
            chip.state = dataSource.viewModel.selectedTags.contains(chip.title) ? .on : .off
        }

        // Show/hide bar based on whether tags exist
        tagFilterBar?.isHidden = allTags.isEmpty

        (chipsScrollView?.contentView as? RightAlignedClipView)?.updateDocumentFrame()

        if isFirstLoad {
            hasPerformedInitialChipScroll = true
            DispatchQueue.main.async { [weak self] in
                self?.scrollToRightEdge()
            }
        }
    }

    private func scrollToRightEdge() {
        guard let chipScroll = chipsScrollView,
              let docView = chipScroll.documentView else { return }
        (chipScroll.contentView as? RightAlignedClipView)?.updateDocumentFrame()
        let docWidth = docView.frame.width
        let clipWidth = chipScroll.contentView.bounds.width
        let targetX = max(0, docWidth - clipWidth)
        chipScroll.contentView.scroll(to: NSPoint(x: targetX, y: 0))
        chipScroll.reflectScrolledClipView(chipScroll.contentView)
    }

    @objc private func chipToggled(_ sender: NSButton) {
        dataSource.viewModel.toggleTagSelection(sender.title)
    }

    @objc private func toggleFilterMode(_ sender: NSButton) {
        dataSource.viewModel.toggleTagFilterMode()
        let and = dataSource.viewModel.tagFilterMode == .and
        sender.toolTip = .init(localized: and ? .and : .or)
        let color: NSColor = and ? .controlAccentColor : .controlTextColor
        let config = NSImage.SymbolConfiguration(hierarchicalColor: color)
        sender.image = NSImage(
            systemSymbolName: "line.3.horizontal.decrease",
            accessibilityDescription: "Filter Mode"
        )?.withSymbolConfiguration(config)
    }

    @objc private func showTagSelectionPopover(_ sender: NSButton) {
        tagSelectionPopover?.performClose(nil)

        let allTags = dataSource.viewModel.allTags
        guard !allTags.isEmpty else { return }

        let isAndMode = dataSource.viewModel.tagFilterMode == .and
        let selectedTags = dataSource.viewModel.selectedTags
        let hostingVC = NSHostingController(
            rootView: TagFilterSelectionView(
                allTags: allTags,
                selectedTags: selectedTags,
                isAndMode: isAndMode,
                availableTagsProvider: { [weak self] tags in
                    self?.dataSource.viewModel.availableTags(for: tags) ?? []
                },
                onToggle: { [weak self] tag in
                    self?.dataSource.viewModel.toggleTagSelection(tag)
                    self?.updateChips(allTags: self?.dataSource.viewModel.availableTags ?? [])
                },
                onSelectAll: { [weak self] in
                    guard let self else { return }
                    let allSet = Set(dataSource.viewModel.availableTags)
                    dataSource.viewModel.selectedTags = allSet
                    updateChips(allTags: dataSource.viewModel.availableTags)
                },
                onDeselectAll: { [weak self] in
                    guard let self else { return }
                    dataSource.viewModel.selectedTags = []
                    updateChips(allTags: dataSource.viewModel.availableTags)
                }
            )
        )
        hostingVC.preferredContentSize = NSSize(width: 250, height: 300)

        let popover = NSPopover()
        popover.contentViewController = hostingVC
        popover.behavior = .transient
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        tagSelectionPopover = popover
    }

    func setupLayoutPanel(_ panel: NSPanel) {
        rootStackView.removeArrangedSubview(scrollView)
        rootStackView.removeArrangedSubview(titlebarRootStack)
        rootStackView.removeFromSuperview()
        titlebarRootStack.edgeInsets.top = 8

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.widthAnchor.constraint(equalTo: view.widthAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let titlebarAccessoryView = NSTitlebarAccessoryViewController()
        titlebarAccessoryView.view = titlebarRootStack
        titlebarAccessoryView.layoutAttribute = .bottom

        if #available(macOS 26.1, *) {
            titlebarAccessoryView.preferredScrollEdgeEffectStyle = .soft
        }

        let oldF = titlebarAccessoryView.view.frame
        titlebarAccessoryView.view.frame = NSRect(
            origin: oldF.origin,
            size: CGSize(
                width: oldF.width,
                height: oldF.height + 42
            )
        )

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
        removeScopePanelFromWindow()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if !searchField.stringValue.isEmpty { updateAndShowScopePanel() }
    }
}

extension AnnotationsVC: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let obj = obj.object as? DSFSearchField,
              obj === searchField
        else { return }

        searchField.stringValue.isEmpty
            ? removeScopePanelFromWindow()
            : updateAndShowScopePanel()
    }

    private func updateAndShowScopePanel() {
        guard !scopePanel.isVisible else { return }

        scopeSegment.selectedSegment = dataSource.viewModel.searchScope.rawValue

        let fittingSize = scopeSegment.fittingSize
        let panelWidth = max(fittingSize.width + 16, searchField.bounds.width)
        let panelHeight = fittingSize.height + 12

        let bounds = searchField.bounds
        let rectInWindow = searchField.convert(bounds, to: nil)
        guard let screenRect = searchField.window?.convertToScreen(rectInWindow) else { return }

        let x = MainWindow.rtl ? (screenRect.maxX - panelWidth) : screenRect.minX
        let y = screenRect.minY - panelHeight - 8

        scopePanel.setFrame(
            NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            display: true
        )

        view.window?.addChildWindow(scopePanel, ordered: .above)
    }

    @objc private func searchScopeChanged(_ sender: NSSegmentedControl) {
        guard let scope = AnnotationSearchScope(rawValue: sender.selectedSegment) else { return }
        dataSource.viewModel.searchScope = scope
    }

    private func removeScopePanelFromWindow() {
        guard let window = view.window,
              let windows = window.childWindows,
              windows.contains(scopePanel)
        else { return }
        scopePanel.orderOut(nil)
        window.removeChildWindow(scopePanel)
    }
}
