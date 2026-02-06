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
    @IBOutlet weak var searchContainer: NSView!
    @IBOutlet weak var xBtn: NSButton!

    weak var delegate: SidebarDelegate?

    var tocTree: [TOCNode] = []
    var idToRow: [Int: Int] = [:]
    var ranges: [TOCRange] = []
    var tocLoader: TOCLoaderRefCount!

    var filteredTree: [TOCNode] = []

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

    private(set) var loadingTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        xBtn.isEnabled = false
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        ReusableFunc.setupSearchField(searchField)
        tocLoader = TOCLoaderRefCount(connFactory: {
            self.db
        })
        ReusableFunc.setupSearchField(
            searchField,
            systemSymbolName: "line.3.horizontal.decrease.circle"
        )

        searchField.searchSubmitCallback = { [weak self] query in
            self?.startSearch(query)
        }
        // Do view setup here.
    }

    override func viewDidAppear() {
        super.viewDidAppear()
//        guard let window = view.window,
//              let guide = window.contentLayoutGuide as? NSLayoutGuide
//        else { return }
//
//        let ve = NSVisualEffectView()
//        ve.material = .fullScreenUI
//        ve.blendingMode = .withinWindow
//        ve.state = .active
//        ve.translatesAutoresizingMaskIntoConstraints = false
//        view.addSubview(ve, positioned: .above, relativeTo: outlineView)
//
//        NSLayoutConstraint.activate([
//            ve.topAnchor.constraint(equalTo: view.topAnchor),
//            ve.bottomAnchor.constraint(equalTo: guide.topAnchor),
//            ve.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//            ve.trailingAnchor.constraint(equalTo: view.trailingAnchor)
//        ])
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
        searchContainer.wantsLayer = true
        searchContainer.layer?.backgroundColor = color.nsColor.cgColor
        // Update outline view
        outlineView.backgroundColor = .clear
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
        searchField.isHidden = hide

        // 3. Buat Constraint yang Baru
        if !hide {
            // KONDISI 1: TIDAK TERSEMBUNYI (Unhide)
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets.top = 88
            searchField.becomeFirstResponder()
        } else {
            // KONDISI 2: TERSEMBUNYI (Hide)
            // Hubungkan scrollView top ke superview top dengan constant 0
            // Asumsi superview dari scrollView adalah view utama ViewController
            scrollView.automaticallyAdjustsContentInsets = true
        }
    }

    @MainActor
    func reloadBook(book: BooksData) async {
        loadingTask?.cancel()
        loadingTask = Task { [weak self] in
            guard let self = self else { return }
            ReusableFunc.showProgressWindow(self.view)

            // Acquire shared work
            let taskHandle = await tocLoader.acquire(book: book)

            // Pastikan release dipanggil saat keluar (sukses, error, atau cancel)
            defer {
                Task { [weak self] in
                    await self?.tocLoader.release(bookId: book.id)
                }
            }

            do {
                let tree = try await taskHandle.value
                if Task.isCancelled { await cleanupUI(); return }

                self.tocTree = tree
                await MainActor.run { self.outlineView.reloadData() }

                let allNodes = await self.flattenNodes(tree)
                if Task.isCancelled { await cleanupUI(); return }

                await self.computeEndIDs(for: allNodes)
                self.ranges = await self.buildRanges(from: allNodes)
                await self.rebuildLookupCache()

                await cleanupUI()
            } catch {
                // handle error (show message, log), lalu cleanup UI
                await cleanupUI()
            }
        }

        _ = await loadingTask?.value
    }

    @MainActor
    private func cleanupUI() async {
        ReusableFunc.closeProgressWindow(view)
    }

    func flattenNodes(_ roots: [TOCNode]) async -> [TOCNode] {
        var result: [TOCNode] = []

        func traverse(_ node: TOCNode) {
            result.append(node)
            for child in node.children {
                traverse(child)
            }
        }

        for r in roots {
            traverse(r)
        }

        // Pastikan terurut berdasarkan ID
        return result.sorted { $0.id < $1.id }
    }

    func computeEndIDs(for allNodes: [TOCNode]) async {
        for (i, node) in allNodes.enumerated() {
            if i < allNodes.count - 1 {
                node.endID = allNodes[i+1].id - 1
            } else {
                node.endID = Int.max
            }
        }
    }

    @IBAction func searchContents(_ sender: NSSearchField) {
        let query = sender.stringValue.trimmingCharacters(in: .whitespaces)
        startSearch(query)
    }

    func startSearch(_ query: String) {
        if query.isEmpty {
            filteredTree = []
        } else {
            // filter semua node (termasuk child)
            let allNodes = ranges.map { $0.node }
            let matches = allNodes.filter { $0.bab.lowercased().contains(query) }

            // bikin tree baru hanya dengan node yang cocok
            filteredTree = matches
        }

        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true) // supaya semua hasil terlihat

    }
    
    struct TOCRange {
        let start: Int
        let end: Int
        let node: TOCNode
    }

    func buildRanges(from nodes: [TOCNode]) async -> [TOCRange] {
        return nodes.map { node in
            TOCRange(start: node.id, end: node.endID, node: node)
        }
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

    // MARK: — FIND / PATH
    func findNode(forPage pageID: Int) -> TOCNode? {
        // pilih node paling spesifik (range tersempit) yang mengandung pageID
        let matches = ranges.filter { pageID >= $0.start && pageID <= $0.end }
        return matches.min(by: { ($0.end - $0.start) < ($1.end - $1.start) })?.node
    }

    func findNodeById(_ id: Int) -> TOCNode? {
        // cari di ranges atau di tocTree (ranges seharusnya mencakup semua node)
        if let r = ranges.first(where: { $0.node.id == id }) { return r.node }
        return nil
    }

    // cari path dari root ke node (termasuk node itu sendiri)
    func pathToNode(_ target: TOCNode) -> [TOCNode]? {
        for root in tocTree {
            if let p = findPath(root, target) { return p }
        }
        return nil
    }

    private func findPath(_ current: TOCNode, _ target: TOCNode) -> [TOCNode]? {
        if current.id == target.id { return [current] }
        for child in current.children {
            if let p = findPath(child, target) {
                return [current] + p
            }
        }
        return nil
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
    func selectNode(withId id: Int) async {
        // cari node langsung (node id) — kalau tidak ada, coba cari berdasar page range
        let node = findNodeById(id) ?? findNode(forPage: id)

        guard let node = node, let outlineView else { return }

        enableDelegate = false

        // 1) expand semua parent agar row ada di outlineView
        if let path = pathToNode(node) {
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
}
