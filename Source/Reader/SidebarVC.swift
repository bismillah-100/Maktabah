//
//  SidebarVC.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

import Cocoa

class SidebarVC: NSViewController {

    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var scrollView: NSScrollView!
    @IBOutlet weak var searchField: DSFSearchField!
    @IBOutlet weak var searchContainer: NSVisualEffectView!
    @IBOutlet weak var xBtn: NSButton!

    weak var delegate: SidebarDelegate?

    var tocTree: [TOCNode] = []
    var idToRow: [Int: Int] = [:]

    var filteredTree: [TOCNode] = []
    var flatNodes: [TOCNode] = []

    var isFiltering: Bool {
        !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var db: BookConnection!

    var previousSelectedRow: Int?

    var enableDelegate: Bool = true

    var searchFieldIsHidden: Bool = true {
        didSet {
            xBtn.isEnabled = !searchFieldIsHidden
        }
    }

    private var windowsObservation: NSKeyValueObservation?
    private var tabBarObservation: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        xBtn.isEnabled = false
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        ReusableFunc.setupSearchField(searchField)
        ReusableFunc.setupSearchField(
            searchField,
            systemSymbolName: "line.3.horizontal.decrease.circle"
        )

        outlineView.target = self
        outlineView.doubleAction = #selector(onDoubleClick(_:))

        searchField.searchSubmitCallback = { [weak self] query in
            self?.startSearch(query)
        }

        // Do view setup here.
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startWindowObservation()
    }

    deinit {
        windowsObservation = nil
        if let obs = tabBarObservation {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func startWindowObservation() {
        guard windowsObservation == nil,
              let window = view.window,
              let tabGroup = window.tabGroup
        else { return }

        windowsObservation = tabGroup.observe(
            \.windows,
             options: []
        ) { _,_ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                updateScrollViewInsets(searchContainer.isHidden)
            }
        }

        tabBarObservation = NotificationCenter.default.addObserver(
            forName: .windowTabBarDidChange,
            object: nil, queue: .main,
            using: { [weak self] _ in
                guard let self else { return }
                updateScrollViewInsets(searchContainer.isHidden)
            }
        )
    }

    @IBAction func performFindPanelAction(_ sender: Any) {
        unhideSearchField()
    }

    func applyBackgroundColor(_ color: BackgroundColor) {
        // Update scrollview background
        if let scrollView = outlineView.enclosingScrollView {
            scrollView.drawsBackground = true
            scrollView.backgroundColor = color.nsColor
        }
        // Update outline view
        outlineView.backgroundColor = .clear
        searchContainer.wantsLayer = true
        searchContainer.material = .fullScreenUI
        searchContainer.blendingMode = .withinWindow
    }

    @IBAction func hideSearchFieldEsc(_ sender: Any?) {
        if !searchFieldIsHidden {
            unhideSearchField()
        }
    }

    func unhideSearchField() {
        searchFieldIsHidden.toggle()
        let hide = searchFieldIsHidden

        searchContainer.isHidden = hide
        updateScrollViewInsets(hide)
    }

    func updateScrollViewInsets(_ searchFieldHidden: Bool) {
        if !searchFieldHidden {
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets.top = view.safeAreaInsets.top +
                                           searchContainer.frame.height
            searchField.becomeFirstResponder()
        } else {
            scrollView.automaticallyAdjustsContentInsets = true
        }
    }

    func updateTOC(_ nodes: [TOCNode]) {
        self.tocTree = nodes

        var flat: [TOCNode] = []
        func traverse(_ node: TOCNode) {
            flat.append(node)
            for child in node.children { traverse(child) }
        }
        for node in nodes { traverse(node) }
        self.flatNodes = flat

        self.outlineView.reloadData()
        Task { await self.rebuildLookupCache() }
    }

    @IBAction func searchContents(_ sender: NSSearchField) {
        let query = sender.stringValue.trimmingCharacters(in: .whitespaces)
        startSearch(query)
    }

    func startSearch(_ query: String) {
        if query.isEmpty {
            filteredTree = []
        } else {
            // perf: Use a single-pass filter on pre-flattened nodes to avoid recursive tree traversals on each search keystroke
            filteredTree = flatNodes.filter { $0.bab.localizedStandardContains(query) }
        }
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true) // supaya semua hasil terlihat
    }

    @MainActor
    func rebuildLookupCache() async {
        guard let outlineView = outlineView else { return }
        idToRow.removeAll()

        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? TOCNode {
                idToRow[node.id] = row
            }
        }
    }

    func cleanUpOutlineView() {
        filteredTree.removeAll()
        tocTree.removeAll()
        flatNodes.removeAll()
        idToRow.removeAll()
        searchField.stringValue.removeAll()
        outlineView.reloadData()
    }
}

extension SidebarVC: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView,
                     numberOfChildrenOfItem item: Any?) -> Int {
        let source = isFiltering ? filteredTree : tocTree
        if item == nil {
            return source.count
        }
        return (item as? TOCNode)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView,
                     child index: Int,
                     ofItem item: Any?) -> Any {
        let source = isFiltering ? filteredTree : tocTree
        if item == nil {
            return source[index]
        }
        return (item as! TOCNode).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView,
                     isItemExpandable item: Any) -> Bool {
        guard let node = item as? TOCNode else { return false }
        return !node.children.isEmpty
    }
}

extension SidebarVC: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? TOCNode else { return nil }

        // Tentukan cell berdasarkan level atau kriteria lain
        // Misalnya: level 0 (root) pakai HeaderCell, sisanya DataCell

        let isRootLevel = (node.level == tocTree.first?.level) // atau cek apakah punya parent
        let identifier = isRootLevel ? "HeaderCell" : "DataCell"

        guard let cell = outlineView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier(rawValue: identifier),
            owner: nil
        ) as? NSTableCellView else {
            return nil
        }

        // Set text
        cell.textField?.stringValue = node.bab

        // PENTING: Set warna awal berdasarkan status seleksi row saat ini
        let currentRow = outlineView.row(forItem: node)
        let isSelected = outlineView.selectedRowIndexes.contains(currentRow)

        if identifier == "HeaderCell" {
            cell.textField?.textColor = isSelected ? .controlTextColor : (NSColor(named: "HeaderColor") ?? .controlTextColor)
        }

        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard enableDelegate, let outlineView = notification.object as? NSOutlineView else { return }

        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0 else { return }

        // Get selected node
        let item = outlineView.item(atRow: selectedRow)

        guard let node = item as? TOCNode else { return }

        #if DEBUG
        print("Selected: \(node.bab), id: \(node.id)")
        #endif

        delegate?.didSelectItem(node.id)

        updateTextColor(selectedRow: selectedRow)
    }

    func updateTextColor(selectedRow: Int) {
        if let previousSelectedRow,
           let (_, cellView) = isHeaderCell(previousSelectedRow),
           let cellView {
            cellView.textField?.textColor = NSColor(named: "HeaderColor") ?? .controlTextColor
        }

        if let (_, cellView) = isHeaderCell(selectedRow),
           let cellView
        {
            cellView.textField?.textColor = .controlTextColor
        }

        previousSelectedRow = selectedRow
    }

    func isHeaderCell(_ row: Int) -> (Bool, NSTableCellView?)? {
        guard let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              cellView.identifier?.rawValue == "HeaderCell"
        else {
            return (false, nil)
        }
        return (true, cellView)
    }
}

extension SidebarVC {
    func selectNode(_ node: TOCNode, path: [TOCNode]?) async {
        guard let outlineView else { return }

        enableDelegate = false

        // 1) expand semua parent agar row ada di outlineView
        if let path {
            // expand parents (exclude the node itself)
            for parent in path.dropLast() {
                outlineView.expandItem(parent)
            }
            // 2) rebuild cache karena jumlah rows berubah akibat expand
            await rebuildLookupCache()
        }

        // 3) ambil row dan select
        if let row = self.idToRow[node.id] {
            // hindari re-select jika sudah selected
            if outlineView.selectedRow != row {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
            }
        } else {
            outlineView.deselectAll(nil)
        }

        enableDelegate = true
    }

    @objc private func onDoubleClick(_ sender: AnyObject) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow != -1, let item = outlineView.item(atRow: clickedRow) as? TOCNode else { return }
        if !item.children.isEmpty {
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
        }
    }
}
