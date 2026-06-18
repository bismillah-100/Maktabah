//
//  LibraryViewManager.swift
//  maktab
//
//  Created by MacBook on 03/12/25.
//

import Cocoa
import Combine


@MainActor
class LibraryViewManager: NSObject {
    static let filterSegmentIndexKey = "LibraryFilterSegmentIndex"

    weak var outlineView: NSOutlineView!
    weak var delegate: LibraryViewDelegate?

    var searchView: Bool = false
    var downloadView: Bool = false
    var checkBoxToggle: (() -> Void)?

    weak var searchField: DSFSearchField!
    var viewModel: LibraryViewModel
    var initialLoad: Bool = true
    var isSetupComplete: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init(
        outlineView: NSOutlineView,
        searchField: DSFSearchField,
        searchView: Bool = false,
        downloadView: Bool = false
    ) {
        self.outlineView = outlineView
        self.viewModel = .init()
        if searchView {
            viewModel.showOnlyDownloaded = true
        }
        self.searchView = searchView || downloadView
        self.downloadView = downloadView
        self.searchField = searchField
        super.init()
        setupDSFSearchField()
        setupContextMenu()
        bindToViewModel()
    }

    private func bindToViewModel() {
        viewModel.updateSubject
            .filter({ [weak self] _ in
                self?.isSetupComplete == true
            })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self else { return }
                switch update {
                case .reloadData:
                    outlineView.reloadData()
                    if viewModel.searchQuery.isEmpty {
                        restoreSelection(byBookName: viewModel.selectedBookName)
                    }
                case .reloadItem(let item, let reloadChildren):
                    outlineView.reloadItem(item, reloadChildren: reloadChildren)
                case .expandItem(let item):
                    if let category = item as? CategoryData {
                        outlineView.expandItem(category, expandChildren: true)
                    } else if let bookName = item as? String {
                        restoreSelection(byBookName: bookName)
                    } else {
                        outlineView.expandItem(item, expandChildren: true)
                    }
                case .scrollRowToVisible(let item):
                    let row = outlineView.row(forItem: item)
                    if row >= 0 {
                        outlineView.scrollRowToVisible(row)
                    }
                case .beginUpdates:
                    outlineView.beginUpdates()
                case .endUpdates:
                    outlineView.endUpdates()
                case .removeItems(let indexes, let parent):
                    outlineView.removeItems(at: indexes, inParent: parent, withAnimation: [.slideUp])
                case .insertItems(let indexes, let parent):
                    outlineView.insertItems(at: indexes, inParent: parent, withAnimation: [.slideDown])
                case .moveItem(let from, let to, let parent):
                    outlineView.moveItem(at: from, inParent: parent, to: to, inParent: parent)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Passthrough to ViewModel

    func prepareData(completion: (@MainActor () -> Void)? = nil) async {
        if isSetupComplete { return }
        await viewModel.loadLibrary()
        completion?()
        await MainActor.run { [weak self] in
            guard let self else { return }
            reloadOutlineData()
            isSetupComplete = true
        }
    }

    func reloadOutlineData() {
        if initialLoad, searchView {
            viewModel.selectAllBook(state: true)
            initialLoad = false
        }
        outlineView.reloadData()
        let query = viewModel.searchQuery
        if !query.isEmpty {
            outlineView.expandItem(nil, expandChildren: true)
        } else {
            restoreSelection(byBookName: viewModel.selectedBookName)
        }
    }

    func applyFilter(_ mode: LibraryFilterMode) {
        viewModel.applyFilter(mode)
        if mode == .favorites || mode == .history {
            outlineView?.expandItem(nil, expandChildren: true)
        }
        if mode == .downloaded {
            outlineView?.allowsMultipleSelection = true
        } else {
            outlineView?.allowsMultipleSelection = false
        }
    }

    // MARK: - Selection Restore (UI)

    func restoreSelection(byBookName bookName: String?) {
        guard let bookName,
              let (category, book) = viewModel.restoreSelectionEntry(byBookName: bookName)
        else { return }
        outlineView.expandItem(category)
        let row = outlineView.row(forItem: book)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        }
    }

    // MARK: - Context Menu

    private func setupContextMenu() {
        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu
    }

    func setupDSFSearchField() {
        searchField.searchTermChangeCallback = { [weak self] query in
            self?.viewModel.searchQuery = query
        }
    }

    @objc func checkboxToggled(_ sender: NSButton) {
        let row = outlineView.row(for: sender)
        guard row != -1, let item = outlineView.item(atRow: row) else { return }
        
        if let category = item as? CategoryData {
            viewModel.toggleCategorySelection(category)
            outlineView.reloadItem(category, reloadChildren: true)

            var parent = outlineView.parent(forItem: category)
            while let currentParent = parent {
                outlineView.reloadItem(currentParent)
                parent = outlineView.parent(forItem: currentParent)
            }
        } else if let book = item as? BooksData {
            viewModel.toggleBookSelection(book)
            ReusableFunc.updateBuiltInRecents(with: book.book, in: searchField)

            var parent = outlineView.parent(forItem: book)
            while let currentParent = parent {
                outlineView.reloadItem(currentParent)
                parent = outlineView.parent(forItem: currentParent)
            }
        }
        checkBoxToggle?()
    }
}

// MARK: - NSOutlineViewDataSource
extension LibraryViewManager: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            if viewModel.isFlatMode, let firstCat = viewModel.displayedCategories.first {
                return firstCat.children.count
            }
            return viewModel.displayedCategories.count
        }
        if let category = item as? CategoryData { return category.children.count }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            if viewModel.isFlatMode, let firstCat = viewModel.displayedCategories.first {
                return firstCat.children[index]
            }
            return viewModel.displayedCategories[index]
        }
        if let category = item as? CategoryData { return category.children[index] }
        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let category = item as? CategoryData { return !category.children.isEmpty }
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
            if searchView, let checkbox = cell.subviews.first(where: { $0 is NSButton }) as? NSButton {
                let isSelected = viewModel.isCategorySelected(category)
                let isPartial = viewModel.isCategoryPartiallySelected(category)
                checkbox.state = isPartial ? .mixed : (isSelected ? .on : .off)
                checkbox.target = self
                checkbox.action = #selector(checkboxToggled(_:))
            }
            return cell
        } else if let book = item as? BooksData {
            guard let cell = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView else { return nil }
            cell.textField?.stringValue = book.book
            if searchView, let checkbox = cell.subviews.first(where: { $0 is NSButton }) as? NSButton {
                checkbox.state = viewModel.isBookSelected(book) ? .on : .off
                checkbox.target = self
                checkbox.action = #selector(checkboxToggled(_:))
            }
            return cell
        }
        return nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else { return }
        if outlineView.selectedRowIndexes.count > 1 { return }

        let selectedRow = outlineView.selectedRow
        Task { await delegate?.didSelectItem(selectedRow) }

        if let item = outlineView.item(atRow: selectedRow) as? BooksData {
            ReusableFunc.updateBuiltInRecents(with: item.book, in: searchField)
            viewModel.handleBookSelection(book: item)
        }

        if selectedRow == -1 {
            viewModel.selectedBookName = nil
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { 26 }

    @objc func deleteBookAction(_ sender: NSMenuItem) {
        guard let books = sender.representedObject as? [BooksData] else { return }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delete Download", comment: "")
        if books.count == 1 {
            alert.informativeText = String(localized: "Are you sure you want to delete the downloaded content for \"\(books[0].book)\"?")
        } else {
            alert.informativeText = String(localized: "Are you sure you want to delete the downloaded content for \(books.count) books?")
        }
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                for book in books {
                    try? await BookArchiveIntegrator.shared.removeBookFromArchive(book)
                }
            }
        }
    }
}

// MARK: - NSMenuDelegate
extension LibraryViewManager: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let clickedRow = outlineView.clickedRow
        let rowsToProcess = ReusableFunc.resolveRowsToProcess(
            selectedRows: outlineView.selectedRowIndexes,
            clickedRow: clickedRow
        )

        var integratedBooks: [BooksData] = []
        for row in rowsToProcess {
            if let book = outlineView.item(atRow: row) as? BooksData,
               BookArchiveIntegrator.shared.isBookIntegrated(book) {
                integratedBooks.append(book)
            }
        }

        guard !integratedBooks.isEmpty, AppConfig.isUsingBundleMode else {
            addFavoriteContextMenu(menu: menu, clickedRow: clickedRow)
            return
        }

        let deleteItem = NSMenuItem(
            title: NSLocalizedString("Delete Download", comment: ""),
            action: #selector(deleteBookAction(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.representedObject = integratedBooks
        menu.addItem(deleteItem)
        addFavoriteContextMenu(menu: menu, clickedRow: clickedRow)
    }

    private func addFavoriteContextMenu(menu: NSMenu, clickedRow: Int) {
        if clickedRow >= 0, let book = outlineView.item(atRow: clickedRow) as? BooksData {
            if !menu.items.isEmpty { menu.addItem(NSMenuItem.separator()) }
            let isFav = HistoryViewModel.shared.isFavorite(book.id)
            let title = isFav ? String(localized: "Remove Favorite") : String(localized: "Add Favorite")
            let favItem = NSMenuItem(title: title, action: #selector(toggleFavoriteAction(_:)), keyEquivalent: "")
            favItem.target = self
            favItem.representedObject = book
            menu.addItem(favItem)
        }
    }

    @objc func toggleFavoriteAction(_ sender: NSMenuItem) {
        guard let book = sender.representedObject as? BooksData else { return }
        HistoryViewModel.shared.toggleFavorite(book.id)
    }
}
