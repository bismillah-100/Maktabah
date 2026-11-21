//
//  AnnotationsVC.swift
//  maktab
//
//  Created by MacBook on 15/12/25.
//  hide scopePanel on deactivate searchfield
//

import Cocoa
import OSLog
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
    var tagPopover: NSPopover?
    var tagFilterBar: NSStackView?
    var chipsStackView: NSStackView?
    var chipsScrollView: NSScrollView?
    var filterButton: NSButton?
    var modeButton: NSButton?
    var tagSelectionPopover: NSPopover?
    var hasPerformedInitialChipScroll = false

    var popover: Bool = true
    var isDataLoaded = false

    let defaults = UserDefaults.standard

    // MARK: - Sort State

    enum SortMenuTag {
        static let fieldCreatedAt = 101
        static let fieldContext = 102
        static let fieldPage = 103
        static let fieldPart = 104
        static let ascending = 201
        static let descending = 202
        static let groupingBook = 301
        static let groupingTag = 302
        static let groupingTimeline = 303
    }

    var selectedSortField: AnnotationSortField {
        get { defaults.selectedAnnSortField }
        set { defaults.selectedAnnSortField = newValue }
    }

    var selectedSortAscending: Bool {
        get { defaults.selectedAnnAscending }
        set { defaults.selectedAnnAscending = newValue }
    }

    var selectedGroupingMode: AnnotationGroupingMode {
        get { defaults.selectedAnnGroupingMode }
        set { defaults.selectedAnnGroupingMode = newValue }
    }

    lazy var scopePanel: NSPanel = {
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
        if #available(macOS 26, *) {
            scopeSegment.borderShape = .capsule
        }

        NSLayoutConstraint.activate([
            scopeSegment.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            scopeSegment.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            scopeSegment.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scopeSegment.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        ])

        panel.contentView = contentView
        return panel
    }()

    lazy var titlebarRootStack: NSStackView = {
        let stack = NSStackView()
        stack.edgeInsets.top = 10
        stack.edgeInsets.bottom = 6
        stack.orientation = .vertical
        stack.spacing = 6
        return stack
    }()

    lazy var scopeSegment: NSSegmentedControl = {
        let scopes = AnnotationSearchScope.allCases
        let segment = NSSegmentedControl(
            labels: scopes.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(searchScopeChanged(_:))
        )
        segment.segmentStyle = .texturedRounded
        segment.controlSize = .small
        segment.refusesFirstResponder = true
        return segment
    }()

    lazy var titlebarAccessoryVC: NSTitlebarAccessoryViewController = {
        let accessoryVC = NSTitlebarAccessoryViewController()
        accessoryVC.layoutAttribute = .bottom
        return accessoryVC
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        floatMenuItem.state = .on
        setupSortMenu()
        setupShareMenu()
        setupImportMenu()
        setupSearchField()
        setupOutlineView()
        setupRootStackView()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        searchField.refusesFirstResponder = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        searchField.refusesFirstResponder = false
        if isDataLoaded { return }
        isDataLoaded = true
        ReusableFunc.showProgressWindow(view)
        xBtn.isHidden = popover
        Task { [weak self] in
            guard let self else { return }
            setupMaxLine()
            reloadAnnotations(nil)
            dataSource.setupOutlineMenu()
            await MainActor.run { [weak self] in
                guard let self else { return }
                ReusableFunc.closeProgressWindow(view)
            }
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        removeScopePanelFromWindow()
    }

    // MARK: - Actions

    @IBAction func reloadAnnotations(_ sender: Any?) {
        if sender != nil {
            AnnotationStore.shared.connect()
        }
        outlineView.dataSource = dataSource
        outlineView.delegate = dataSource
        outlineView.usesAutomaticRowHeights = true
        selectedGroupingMode == .book
            ? dataSource.reload()
            : dataSource.updateGrouping(mode: selectedGroupingMode)
        dataSource.updateSorting(field: selectedSortField, isAscending: selectedSortAscending)
        if selectedGroupingMode == .timeline {
            outlineView.expandItem(nil, expandChildren: true)
        }
    }

    @IBAction func searchFieldDidChange(_ sender: NSSearchField) {
        dataSource.viewModel.searchText = sender.stringValue
    }

    private func setupSearchField() {
        ReusableFunc.setupSearchField(searchField)
        searchField.delegate = self
        searchField.refusesFirstResponder = true
        searchField.onBecomeFirstResponder = { [weak self] in
            self?.updateAndShowScopePanel()
        }
    }

    private func setupOutlineView() {
        outlineView.allowsMultipleSelection = true
        outlineView.tableColumns.first?.maxWidth = .greatestFiniteMagnitude
        dataSource.onAddTagsRequested = { [weak self] annotationIDs, anchorRect in
            self?.presentTagPopover(mode: .add, annotationIDs: annotationIDs, anchorRect: anchorRect)
        }
        dataSource.onRemoveTagsRequested = { [weak self] annotationIDs, anchorRect in
            self?.presentTagPopover(mode: .remove, annotationIDs: annotationIDs, anchorRect: anchorRect)
        }
        dataSource.viewModel.onTagsChanged = { [weak self] tags in
            self?.updateChips(allTags: tags)
        }
        dataSource.onSelectItem = { [weak self] row in
            self?.isRowUnselected = row == -1
        }
        dataSource.outlineView = outlineView
    }

    func openAsPanel() {
        loadViewIfNeeded()

        let initialSize = NSSize(
            width: max(view.frame.width, 376),
            height: max(view.frame.height, 500)
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Annotations".localized
        panel.delegate = self
        shareBtn.isHidden = false
        windowBtn.isHidden = true
        setting.isHidden = false
        floatMenuItem.isHidden = false
        hideOnMenuItem.isHidden = false
        floatMenuItem.state = floatPanel ? .on : .off
        hideOnMenuItem.state = hideOnPanel ? .on : .off

        setupPanelScrollView()
        panel.contentViewController = self
        if SharedPopover.annotationsPopover.contentViewController === self {
            SharedPopover.annotationsPopover.contentViewController = nil
        }

        panel.isFloatingPanel = floatPanel
        panel.hidesOnDeactivate = hideOnPanel
        panel.setFrameAutosaveName("AnnotationsPanel")
        setupPanelTitlebarAccessory(panel)
        panel.makeKeyAndOrderFront(nil)
        Self.panel = panel
        updateTitlebarAccessoryHeight()
    }

    // MARK: - LAYOUT

    private func setupRootStackView() {
        createRootTitlebarStack()
        if #unavailable(macOS 26) {
            let btmBox = NSBox()
            btmBox.boxType = .separator
            btmBox.translatesAutoresizingMaskIntoConstraints = false
            rootStackView.insertArrangedSubview(btmBox, at: 0)
        }
        rootStackView.insertArrangedSubview(titlebarRootStack, at: 0)
        NSLayoutConstraint.activate([
            titlebarRootStack.leadingAnchor.constraint(equalTo: rootStackView.leadingAnchor),
            titlebarRootStack.trailingAnchor.constraint(equalTo: rootStackView.trailingAnchor),
        ])
    }

    private func setupPanelScrollView() {
        rootStackView.removeArrangedSubview(scrollView)
        rootStackView.removeArrangedSubview(titlebarRootStack)
        scrollView.removeFromSuperview()
        titlebarRootStack.removeFromSuperview()
        rootStackView.removeFromSuperview()

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupPanelTitlebarAccessory(_ panel: NSPanel) {
        titlebarRootStack.edgeInsets.top = 0
        titlebarRootStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: panel.frame.width, height: 70))
        container.translatesAutoresizingMaskIntoConstraints = true
        container.autoresizingMask = [.width]
        container.addSubview(titlebarRootStack)

        let bottomConstraint = titlebarRootStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        bottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titlebarRootStack.topAnchor.constraint(equalTo: container.topAnchor),
            titlebarRootStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titlebarRootStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomConstraint,
        ])

        container.layoutSubtreeIfNeeded()
        let targetHeight = max(ceil(titlebarRootStack.fittingSize.height), 44)
        container.frame = NSRect(x: 0, y: 0, width: panel.frame.width, height: targetHeight)

        titlebarAccessoryVC.view = container
        if #available(macOS 26.1, *) {
            titlebarAccessoryVC.preferredScrollEdgeEffectStyle = .soft
        }
        panel.addTitlebarAccessoryViewController(titlebarAccessoryVC)
    }

    func updateTitlebarAccessoryHeight() {
        guard let panel = Self.panel,
              titlebarAccessoryVC.view.superview != nil
        else { return }

        titlebarRootStack.layoutSubtreeIfNeeded()
        let targetHeight = max(ceil(titlebarRootStack.fittingSize.height), 44)
        var frame = titlebarAccessoryVC.view.frame
        if abs(frame.height - targetHeight) > 0.5 || frame.width != panel.frame.width {
            frame.size = CGSize(width: panel.frame.width, height: targetHeight)
            titlebarAccessoryVC.view.frame = frame
        }
    }

    deinit {
        Logger.annotations.debug("annotationsVC deinit")
    }
}
