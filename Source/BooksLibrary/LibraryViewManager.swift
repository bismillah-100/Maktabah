//
//  LibraryViewManager.swift
//  maktab
//
//  Created by MacBook on 03/12/25.
//

import Cocoa

class LibraryViewManager: NSObject {

    weak var outlineView: NSOutlineView!
    weak var delegate: LibraryViewDelegate?
    let data: LibraryDataManager = .shared

    var searchView: Bool = false

    var displayedCategories: [CategoryData] = []

    weak var searchField: DSFSearchField!

    private var selectedBookName: String?
    private var bookLookup: [String: (category: CategoryData, book: BooksData)] = [:]

    init(outlineView: NSOutlineView, searchField: DSFSearchField, searchView: Bool = false) {
        self.outlineView = outlineView
        self.searchView = searchView
        self.searchField = searchField
        super.init()
        self.setupDSFSearchField()
    }

    func prepareData() {
        for data in data.allRootCategories {
            displayedCategories.append(data)
        }
        buildBookLookup()
    }

    func buildBookLookup() {
        bookLookup.removeAll()
        for category in displayedCategories {
            for child in category.children {
                if let book = child as? BooksData {
                    bookLookup[book.book] = (category, book)
                }
            }
        }
    }


    func setupDSFSearchField() {
        // Di dalam LibraryViewManager atau View Controller Anda:
        searchField.searchTermChangeCallback = { [weak self] query in
            // Panggil fungsi pencarian data yang sebenarnya di sini
            self?.startSearch(query)
        }
    }

    var searchWork: DispatchWorkItem?

    @objc func checkboxToggled(_ sender: NSButton) {
        // Ambil row dari button
        let row = outlineView.row(for: sender)
        guard row != -1, let item = outlineView.item(atRow: row) else { return }

        let newState = (sender.state == .on)

        if let category = item as? CategoryData {
            // Logic: Jika kategori dicentang, centang semua anak-anaknya (Cascade)
            setCategoryChecked(category, state: newState)
            // Reload item ini dan anak-anaknya agar visual update
            outlineView.reloadItem(category, reloadChildren: true)
        } else if let book = item as? BooksData {
            book.isChecked = newState
            ReusableFunc.updateBuiltInRecents(with: book.book, in: searchField)
        }
    }

    // Helper rekursif untuk mencentang category & children
    func setCategoryChecked(_ category: CategoryData, state: Bool) {
        category.isChecked = state
        for child in category.children {
            if let subCat = child as? CategoryData {
                setCategoryChecked(subCat, state: state)
            } else if let book = child as? BooksData {
                book.isChecked = state
            }
        }
    }
}

extension LibraryViewManager: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return displayedCategories.count
        }

        if let category = item as? CategoryData {
            return category.children.count
        }

        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return displayedCategories[index]
        }

        if let category = item as? CategoryData {
            return category.children[index]
        }

        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let category = item as? CategoryData {
            return !category.children.isEmpty
        }
        return false
    }
}

// MARK: - NSOutlineViewDelegate
extension LibraryViewManager: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier("DataCell")
        let headerIdentifier = NSUserInterfaceItemIdentifier("HeaderCell")

        if let category = item as? CategoryData {
            guard let cell = outlineView.makeView(withIdentifier: headerIdentifier, owner: self) as? NSTableCellView else { return nil }
            cell.textField?.stringValue = category.name
            if searchView,
               let checkbox = cell.subviews.first(where: { $0 is NSButton }) as? NSButton {
                checkbox.state = category.isChecked ? .on : .off
                checkbox.target = self
                checkbox.action = #selector(checkboxToggled(_:))
            }
            return cell
        } else if let book = item as? BooksData {
            guard let cell = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView else { return nil }
            cell.textField?.stringValue = book.book
            if searchView,
                let checkbox = cell.subviews.first(where: { $0 is NSButton }) as? NSButton {
                checkbox.state = book.isChecked ? .on : .off
                checkbox.target = self
                checkbox.action = #selector(checkboxToggled(_:))
            }
            return cell
        }

        return nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else {
            return
        }

        let selectedRow = outlineView.selectedRow
        Task {
            await delegate?.didSelectItem(selectedRow)
        }

        if let item = outlineView.item(atRow: selectedRow) as? BooksData {
            ReusableFunc.updateBuiltInRecents(with: item.book, in: searchField)
            selectedBookName = item.book // Simpan nama buku
        }

        if selectedRow == -1 {
            selectedBookName = nil
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        26
    }
}

extension LibraryViewManager: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let searchField = obj.object as? NSSearchField else { return }
        let query = searchField.stringValue
        startSearch(query)
    }

    func startSearch(_ query: String) {
        searchWork?.cancel()

        let workItem = DispatchWorkItem { [weak self, query] in
            guard let self else { return }
            let foundData = data.filterContent(with: query, displayedCategories: &displayedCategories)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                outlineView.reloadData()

                if foundData {
                    outlineView.expandItem(nil, expandChildren: true)
                }

                // Restore seleksi jika query kosong
                if query.isEmpty, let bookName = selectedBookName {
                    self.restoreSelection(byBookName: bookName)
                }
            }
        }

        searchWork = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    // Helper function untuk restore seleksi berdasarkan nama buku
    private func restoreSelection(byBookName bookName: String) {
        guard let (category, book) = bookLookup[bookName] else { return }

        outlineView.expandItem(category)
        let row = outlineView.row(forItem: book)

        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        }
    }
}

