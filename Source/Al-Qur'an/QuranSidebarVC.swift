//
//  QuranSidebarVC.swift
//  maktab
//
//  Created by MacBook on 23/12/25.
//

import Cocoa

class QuranSidebarVC: NSViewController {
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var scrollView: NSScrollView!
    @IBOutlet weak var searchField: DSFSearchField!
    @IBOutlet weak var searchContainer: NSView!
    @IBOutlet weak var xBtn: NSButton!

    private let manager: QuranDataManager = .shared

    weak var delegate: QuranDelegate?

    private var filteredSurahNodes: [SurahNode]? = nil

    var surahNodes: [SurahNode] {
        filteredSurahNodes ?? manager.surahNodes
    }

    private(set) var ayaLookup: [Int: [Int: Quran]] = [:]

    var enableDelegate = true

    override func loadView() {
        var topLevelObjects: NSArray? = nil
        Bundle.main.loadNibNamed("SidebarVC", owner: self, topLevelObjects: &topLevelObjects)

        if let views = topLevelObjects as? [Any],
           let sidebarView = views.first(where: { $0 is NSView }) as? NSView {
            self.view = sidebarView
        } else {
            self.view = NSView()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupAppereance()
        registerNib()
        setupOutlineView()
        // Do view setup here.
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        loadData()
        prepareLookup()
        outlineView.reloadData()
        setupSearchField()
    }

    func setupAppereance() {
        outlineView.backgroundColor = .clear
        outlineView.enclosingScrollView?.backgroundColor = .clear
        xBtn.isHidden = true
    }

    func setupOutlineView() {
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.allowsMultipleSelection = false
    }

    func loadData() {
        do {
            try manager.fetchSurahNodes()
        } catch {
            #if DEBUG
            print(error)
            #endif
        }
    }

    func registerNib() {
        ReusableFunc.registerNib(
            tableView: outlineView,
            nibName: .outlineChildNib,
            cellIdentifier: .resultAndOutlineChild
        )

        ReusableFunc.registerNib(
            tableView: outlineView,
            nibName: .outlineParentNib,
            cellIdentifier: .outlineParent
        )
    }

    func setupSearchField() {
        guard let toolbar = view.window?.toolbar,
              let searchField = toolbar.items.first(
                where: {$0.itemIdentifier.rawValue == "searchQuran"}
              )
        else { return }
        searchField.target = self
        searchField.action = #selector(unhideSearchField)
    }

    @IBAction func hideSearchFieldEsc(_ sender: Any?) {
        if !searchField.isHidden {
            unhideSearchField()
        }
    }

    @objc func unhideSearchField() {
        #if DEBUG
        print("unhideSearchField")
        #endif

        let hide = searchField.isHidden

        searchContainer.isHidden = !hide
        searchField.isHidden = !hide

        // 3. Buat Constraint yang Baru
        if hide {
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

    @IBAction func searchContents(_ sender: NSSearchField) {
        filteredSurahNodes = manager.searchSurah(searchField.stringValue)
        outlineView.reloadData()
        outlineView.collapseItem(nil)
    }

    func prepareLookup() {
        ayaLookup.removeAll()
        for surah in manager.surahNodes {
            var dict: [Int: Quran] = [:]
            for aya in surah.aya {
                dict[aya.aya] = aya
            }
            ayaLookup[surah.id] = dict
        }
    }

    func selectNode(aya: Int, surah: Int) {
        // 1. Ambil SurahNode (114 item masih sangat cepat pakai first)
        guard let surahNode = surahNodes.first(where: { $0.id == surah }),
              // 2. Ambil AyaNode INSTAN (O(1))
              let ayaNode = ayaLookup[surah]?[aya] else {
            return
        }

        // Pastikan surah visible (UI process)
        if !outlineView.isItemExpanded(surahNode) {
            outlineView.expandItem(surahNode)
        }

        // Dapatkan row
        let row = outlineView.row(forItem: ayaNode)
        guard row != -1 else { return }

        enableDelegate = false
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        enableDelegate = true
    }
}

extension QuranSidebarVC: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let surah = item as? SurahNode {
            return surah.aya.count
        }
        return surahNodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let surah = item as? SurahNode {
            return surah.aya[index]
        }
        return surahNodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is SurahNode
    }
}

extension QuranSidebarVC: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let item = item as? SurahNode,
           let parentCell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(CellIViewIdentifier.outlineParent.rawValue), owner: self) as? NSTableCellView {
            parentCell.textField?.stringValue = item.surah
            return parentCell
        }

        if let item = item as? Quran,
           let childCell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(CellIViewIdentifier.resultAndOutlineChild.rawValue), owner: self) as? NSTableCellView {
            childCell.textField?.stringValue = String(item.aya)
            return childCell
        }

        return nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard enableDelegate else { return }

        let row = outlineView.selectedRow

        if row == -1 { return }

        guard let item = outlineView.item(atRow: row) as? Quran,
              let parent = outlineView.parent(forItem: item) as? SurahNode
        else {
            #if DEBUG
            print("item or parent not found")
            #endif
            return
        }

        delegate?.didSelectAya(parent, aya: item)
    }
}
