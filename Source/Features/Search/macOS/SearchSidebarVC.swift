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
    @IBOutlet weak var selectAllButton: NSButton!
    @IBOutlet weak var scrollViewTopConstraint: NSLayoutConstraint!
    
    var dataVM: LibraryViewManager!

    override func viewDidLoad() {
        super.viewDidLoad()
        searchField.focusRingType = .none
        dataVM = LibraryViewManager(outlineView: outlineView, searchField: searchField, searchView: true)
        outlineView.delegate = dataVM
        outlineView.dataSource = dataVM
        ReusableFunc.setupSearchField(
            searchField,
            systemSymbolName: "line.3.horizontal.decrease.circle"
        )
    }

    @IBAction func selectAllBook(_ sender: NSButton) {
        let newState = (sender.state == .on)

        dataVM.viewModel.selectAllBook(state: newState)

        outlineView.reloadData()
    }
}
