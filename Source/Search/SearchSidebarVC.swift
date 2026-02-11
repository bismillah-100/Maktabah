//
//  SearchSidebarVC.swift
//  maktab
//
//  Created by MacBook on 03/12/25.
//

import Cocoa

class SearchSidebarVC: NSViewController {
    @IBOutlet weak var searchField: DSFSearchField!
    @IBOutlet weak var outlineView: NSOutlineView!

    var data: LibraryDataManager = .shared
    var dataVM: LibraryViewManager!

    override func viewDidLoad() {
        super.viewDidLoad()
        searchField.focusRingType = .none
        dataVM = LibraryViewManager(outlineView: outlineView, searchField: searchField, searchView: true)
        outlineView.delegate = dataVM
        outlineView.dataSource = dataVM
        searchField.delegate = dataVM
        ReusableFunc.setupSearchField(
            searchField,
            systemSymbolName: "line.3.horizontal.decrease.circle"
        )
    }
    
    @IBAction func selectAllBook(_ sender: NSButton) {
        let newState = (sender.state == .on)

        // Ambil semua root category yang sedang ditampilkan
        for category in dataVM.displayedCategories {
            dataVM.setCategoryChecked(category, state: newState)
        }

        outlineView.reloadData()
    }
}
