//
//  LibraryVC.swift
//  maktab
//
//  Created by MacBook on 30/11/25.
//

import Cocoa

class LibraryVC: NSViewController {
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var scrollView: NSScrollView!
    @IBOutlet weak var scrollViewTopConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var searchField: DSFSearchField!

    var dataVM: LibraryViewManager!

    var data: LibraryDataManager = .shared

    var searchFieldIsHidden: Bool = true

    weak var delegate: LibraryDelegate?

    var isDataLoaded: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        dataVM = LibraryViewManager(
            outlineView: outlineView,
            searchField: searchField
        )
        dataVM.delegate = self
        searchField.focusRingType = .none
        // Do view setup here.
        setupOutlineView()
        ReusableFunc.setupSearchField(
            searchField,
            systemSymbolName: "line.3.horizontal.decrease.circle"
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !isDataLoaded else { return }
        ReusableFunc.showProgressWindow(view)
        searchField.delegate = dataVM
        Task.detached { [weak self] in
            guard let self else { return }
            await self.data.loadData()
            await MainActor.run { [weak self] in
                guard let self else { return }
                dataVM.prepareData()
                outlineView.reloadData()
                ReusableFunc.closeProgressWindow(view)
                isDataLoaded = true
            }
        }
    }

    func setupOutlineView() {
        outlineView.delegate = dataVM
        outlineView.dataSource = dataVM
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

    func unhideSearchField() {
        ReusableFunc.unhideSearchField(
            searchFieldIsHidden: searchFieldIsHidden,
            searchField: searchField,
            scrollViewTopConstraint: scrollViewTopConstraint)
    }
}

extension LibraryVC: LibraryViewDelegate {
    func didSelectItem(_ row: Int) async {
        if row >= 0 {
            let item = outlineView.item(atRow: row)
            if let book = item as? BooksData {
                print("Buku dipilih: \(book.book) (ID: \(book.id))")
                await delegate?.didSelectBook(for: book)
            } else if let category = item as? CategoryData {
                print("Kategori dipilih: \(category.name)")
            }
        }
    }
}
