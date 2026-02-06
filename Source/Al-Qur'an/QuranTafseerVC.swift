//
//  QuranTafseerVC.swift
//  maktab
//
//  Created by MacBook on 23/12/25.
//

import Cocoa

class QuranTafseerVC: NSViewController {

    var didSelectBook: ((BooksData) -> Void)?

    lazy var tableView: NSTableView = {
        let table = NSTableView()
        table.enclosingScrollView?.autohidesScrollers = true
        table.dataSource = self
        table.delegate = self
        table.tableColumns.forEach { column in
            table.removeTableColumn(column)
        }
        table.addTableColumn(tableColumn)
        table.headerView = nil
        table.backgroundColor = .clear
        table.alignment = .right
        return table
    }()

    lazy var tableColumn: NSTableColumn = {
        let column = NSTableColumn()
        column.title = "التفاسير"
        column.headerCell.alignment = .right
        return column
    }()

    private var filteredData: [BooksData] = []

    var data: [BooksData] {
        filteredData.isEmpty
        ? QuranDataManager.shared.tafseerBooks
        : filteredData
    }

    override func loadView() {
        let view = NSView()
        let scrollView = NSScrollView()
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        view.addSubview(scrollView)
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ReusableFunc.registerNib(
            tableView: tableView,
            nibName: .outlineChildNib,
            cellIdentifier: .resultAndOutlineChild
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        QuranDataManager.shared.buildTafseerMap()
        tableView.reloadData()
        setupSearchField()
    }

    func setupSearchField() {
        guard let toolbar = view.window?.toolbar,
              let searchField = toolbar.items.first(
                where: {$0.itemIdentifier.rawValue == "searchTafseer"}
              )?.view as? NSSearchField
        else { return }
        
        searchField.delegate = self
        searchField.target = self
    }

    deinit {
        #if DEBUG
        print("deinit QuranTafseerVC")
        #endif
    }

}

extension QuranTafseerVC: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        data.count
    }
}

extension QuranTafseerVC: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(CellIViewIdentifier.resultAndOutlineChild.rawValue), owner: self) as? NSTableCellView, row < data.count
        else { return nil }

        let item = data[row]

        cell.textField?.stringValue = item.book
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow

        if row < 0 || row >= data.count { return }

        let book = data[row]

        didSelectBook?(book)
    }
}

extension QuranTafseerVC: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let searchField = obj.object as? NSSearchField else { return }

        filteredData = QuranDataManager.shared.searchTafseerBooks(
            searchField.stringValue
        )

        tableView.reloadData()
    }
}
