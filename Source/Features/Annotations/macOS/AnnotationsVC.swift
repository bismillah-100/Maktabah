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
        if #available(macOS 26, *) { scopeSegment.borderShape = .capsule }

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
        segment.segmentStyle = .roundRect
        segment.controlSize = .small
        segment.refusesFirstResponder = true
        return segment
    }()

    // MARK: - Lifecycle

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
            self?.presentTagPopover(mode: .add, annotationIDs: annotationIDs, anchorRect: anchorRect)
        }
        dataSource.onRemoveTagsRequested = { [weak self] annotationIDs, anchorRect in
            self?.presentTagPopover(mode: .remove, annotationIDs: annotationIDs, anchorRect: anchorRect)
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
        dataSource.onSelectItem = { [weak self] row in self?.isRowUnselected = row == -1 }
        outlineView.deselectAll(nil)
        dataSource.outlineView = outlineView
        createRootTitlebarStack()
        if #unavailable(macOS 26) {
            let btmBox = NSBox()
            btmBox.boxType = .separator
            btmBox.translatesAutoresizingMaskIntoConstraints = false
            rootStackView.insertArrangedSubview(btmBox, at: 0)
        }
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

    // MARK: - Actions

    @IBAction func reloadAnnotations(_ sender: Any?) {
        if sender != nil { AnnotationManager.shared.connect() }
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

        let oldF = titlebarAccessoryView.view.frame
        if #available(macOS 26.1, *) {
            titlebarAccessoryView.preferredScrollEdgeEffectStyle = .soft
            if oldF.height < 70 {
                titlebarAccessoryView.view.frame = NSRect(
                    origin: oldF.origin,
                    size: CGSize(width: oldF.width, height: 70)
                )
            }
        } else {
            titlebarAccessoryView.view.frame = NSRect(
                origin: oldF.origin,
                size: CGSize(width: oldF.width, height: oldF.height + 42)
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
