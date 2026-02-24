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
    @IBOutlet weak var shareBtn: NSButton!
    @IBOutlet weak var windowBtn: NSButton!
    @IBOutlet weak var setting: NSPopUpButton!
    @IBOutlet weak var sortingButton: NSPopUpButton!
    @IBOutlet weak var floatMenuItem: NSMenuItem!
    @IBOutlet weak var hideOnMenuItem: NSMenuItem!
    @IBOutlet weak var searchField: DSFSearchField!
    @IBOutlet weak var xBtn: NSButton!

    @objc dynamic var isRowUnselected: Bool = true

    var floatPanel: Bool {
        UserDefaults.standard.annotationFloatWindow
    }

    var hideOnPanel: Bool {
        UserDefaults.standard.annotationHideWindow
    }

    static var panel: NSPanel?

    let dataSource: AnnotationOutlineDataSource = .init()
    var workItem: DispatchWorkItem?

    var popover: Bool = true
    var isDataLoaded = false

    private enum SortMenuTag {
        static let fieldCreatedAt = 101
        static let fieldContext = 102
        static let fieldPage = 103
        static let fieldPart = 104
        static let ascending = 201
        static let descending = 202
    }

    private var selectedSortField: AnnotationSortField = .createdAt
    private var selectedSortAscending = false

    override func viewDidLoad() {
        super.viewDidLoad()
        floatMenuItem.state = .on
        setupSortMenu()
        ReusableFunc.setupSearchField(searchField)
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

        Task { [weak self] in
            guard let self else { return }
            reloadAnnotations(nil)
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
        dataSource.reload()
        outlineView.dataSource = dataSource
        outlineView.delegate = dataSource
        outlineView.usesAutomaticRowHeights = true
        dataSource.updateSorting(field: selectedSortField, isAscending: selectedSortAscending)
    }

    @IBAction func searchFieldDidChange(_ sender: NSSearchField) {
        workItem?.cancel()
        let query = sender.stringValue
        workItem = DispatchWorkItem { [weak self, query] in
            guard let self else { return }
            dataSource.applySearchFilter(text: query)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                outlineView.reloadData()
                if !sender.stringValue.isEmpty {
                    outlineView.expandItem(nil, expandChildren: true)
                }
                ReusableFunc.updateBuiltInRecents(with: sender.stringValue, in: searchField)
            }
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: workItem!)
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
        sortingButton.image = NSImage(
            systemSymbolName: "arrow.up.arrow.down.circle",
            accessibilityDescription: "Sort"
        )
        sortingButton.title = ""
        updateSortMenuState()
    }

    @objc private func selectSortField(_ sender: NSMenuItem) {
        switch sender.tag {
        case SortMenuTag.fieldCreatedAt: selectedSortField = .createdAt
        case SortMenuTag.fieldContext: selectedSortField = .context
        case SortMenuTag.fieldPage: selectedSortField = .page
        case SortMenuTag.fieldPart: selectedSortField = .part
        default: return
        }
        applySorting()
    }

    @objc private func selectSortOrder(_ sender: NSMenuItem) {
        selectedSortAscending = sender.tag == SortMenuTag.ascending
        applySorting()
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
        // Jika VC masih di popover, lepas first responder dulu lalu tutup popover.
        // Re-parent view dilakukan di run loop berikutnya agar tidak bentrok window ownership.
        if let window = view.window {
            window.makeFirstResponder(nil)
        }

        SharedPopover.annotationsPopover.performClose(sender)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let panel = NSPanel()
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
            panel.makeKeyAndOrderFront(sender)
            panel.setFrameAutosaveName("AnnotationsPanel")
            Self.panel = panel
        }
    }

    deinit {
        #if DEBUG
        print("annotationsVC deinit")
        #endif
    }
}

extension AnnotationsVC: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        SharedPopover.annotationsVC = nil
        SharedPopover.annotationsPopover.contentViewController = nil
        Self.panel?.delegate = nil
        Self.panel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        outlineView.deselectAll(nil)
    }
}
