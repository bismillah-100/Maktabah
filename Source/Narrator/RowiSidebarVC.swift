//
//  RowiSidebarVC.swift
//  maktab
//
//  Created by MacBook on 10/12/25.
//

import Cocoa

class RowiSidebarVC: NSViewController {
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var searchField: DSFSearchField!
    @IBOutlet weak var scrollView: NSScrollView!
    @IBOutlet weak var scrollViewTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var scrollViewBottomConstraint: NSLayoutConstraint!

    private let folderCellIdentifier = NSUserInterfaceItemIdentifier(
        CellIViewIdentifier.outlineParent.rawValue
    )

    private let resultCellIdentifier = NSUserInterfaceItemIdentifier(
        CellIViewIdentifier.resultAndOutlineChild.rawValue
    )

    private let loadMoreIdentifier     = NSUserInterfaceItemIdentifier("LoadMoreCell")

    // MARK: - ViewModel

    var viewModel: NarratorViewModel!

    weak var delegate: RowiSidebarDelegate?

    var isDataLoaded: Bool = false
    var searchFieldIsHidden: Bool = true
    var searchWork: DispatchWorkItem?

    override var nibName: NSNib.Name? {
        "LibraryVC"
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        registerNib()
        ReusableFunc.setupSearchField(searchField)
        searchField.recentsAutosaveName = "RecentsRowiSidebarSearchField"
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !isDataLoaded else {
            return
        }
        ReusableFunc.showProgressWindow(view)
        setupOutlineView()
        searchField.placeholderString = "البحث في رواة الحديث"
        Task.detached { [weak self] in
            await self?.loadData()
        }
    }

    func unhideSearchField() {
        ReusableFunc.unhideSearchField(
            searchFieldIsHidden: searchFieldIsHidden,
            searchField: searchField,
            scrollViewTopConstraint: scrollViewTopConstraint)
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

        outlineView.register(NSNib(nibNamed: "LoadMoreCell", bundle: nil), forIdentifier: loadMoreIdentifier)
    }

    func setupOutlineView() {
        outlineView.dataSource = self
        outlineView.delegate = self
        searchField.delegate = self
    }

    func loadData() async {
        await viewModel.loadData()
        await MainActor.run { [weak self] in
            guard let self else { return }
            outlineView.reloadData()
            ReusableFunc.closeProgressWindow(view)
            isDataLoaded = true
        }
    }

    @IBAction func searchFieldChanged(_ sender: NSSearchField) {
        searchWork?.cancel()
        let query = sender.stringValue

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            viewModel.searchRowis(query: query)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                outlineView.reloadData()
                if !sender.stringValue.isEmpty {
                    outlineView.expandItem(nil, expandChildren: true)
                }
            }
        }

        searchWork = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    @objc func loadMoreTapped(_ sender: NSButton) {
        let row = outlineView.row(for: sender)
        // Item yang diklik adalah tombol "Load More", jadi parent adalah induk item tersebut.
        let parent = outlineView.parent(forItem: outlineView.item(atRow: row))

        guard let group = parent as? TabaqaGroup else {
            // Ini seharusnya tidak terjadi jika logika Data Source benar
            return
        }

        // Hitung di mana baris baru akan dimulai
        let startingIndex = group.displayedRowis.count

        // Panggil loadMore untuk memperbarui data model.
        viewModel.loadMore(group: group) { [weak self] itemsLoadedCount in // itemsLoadedCount adalah data baru yang di-pass dari loadMore
            guard let self, let itemsLoaded = itemsLoadedCount else { return }

            outlineView.beginUpdates()

            // 1. Buat IndexSet yang benar
            var indicesToInsert = IndexSet()
            let endIndex = startingIndex + itemsLoaded

            for i in startingIndex..<endIndex {
                indicesToInsert.insert(i)
            }

            // 2. Jika ada baris "Load More" (asumsi selalu ada di akhir), hapus dulu.
            // Asumsi item "Load More" berada di indeks terakhir (startingIndex)
            // Jika group.hasMore == false setelah loadMore, artinya baris "Load More" harus dihapus.
            let needsDeleteLoadMoreRow = !group.hasMore

            // 3. Sisipkan item baru di bawah item yang sudah ada.
            self.outlineView.insertItems(at: indicesToInsert, inParent: group, withAnimation: .slideDown)

            if needsDeleteLoadMoreRow {
                self.outlineView.removeItems(at: IndexSet(integer: endIndex), inParent: group)
            }
            outlineView.endUpdates()
        }
    }
}

// MARK: - OutlineView DataSource
extension RowiSidebarVC: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let group = item as? TabaqaGroup {
            return group.displayedRowis.count + (group.hasMore ? 1 : 0)  // +1 untuk tombol
        }
        return viewModel.tabaqaGroups.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let group = item as? TabaqaGroup {
            if index < group.displayedRowis.count {
                return group.displayedRowis[index]
            } else {
                return "LoadMore"  // Marker untuk load more button
            }
        }
        return viewModel.tabaqaGroups[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is TabaqaGroup
    }
}

// MARK: - OutlineView Delegate
extension RowiSidebarVC: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if item is String && (item as! String) == "LoadMore" {
            let cell = outlineView.makeView(withIdentifier: loadMoreIdentifier, owner: self) as! LoadMoreCell
            cell.loadButton.target = self
            cell.loadButton.action = #selector(loadMoreTapped)
            return cell
        }

        if let group = item as? TabaqaGroup {
            // Header cell for tabaqa group
            guard let cell = outlineView.makeView(withIdentifier: folderCellIdentifier, owner: self) as? NSTableCellView else {
                return nil
            }
            cell.textField?.stringValue = "\(group.name)"
            return cell

        } else if let rowi = item as? Rowi {
            // Data cell for individual rowi
            guard let cell = outlineView.makeView(withIdentifier: resultCellIdentifier, owner: self) as? NSTableCellView else {
                return nil
            }
            cell.textField?.stringValue = rowi.isoName
            return cell
        }

        return nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0 else { return }

        let item = outlineView.item(atRow: selectedRow)
        if let rowi = item as? Rowi {
            delegate?.didSelect(rowi: rowi)
            ReusableFunc.updateBuiltInRecents(with: rowi.isoName, in: searchField)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 26
    }
}

extension RowiSidebarVC: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let searchField = obj.object as? NSSearchField else { return }
        searchFieldChanged(searchField)
    }
}
