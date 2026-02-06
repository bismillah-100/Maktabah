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
    var isDataLoaded: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        searchField.focusRingType = .none
        dataVM = LibraryViewManager(outlineView: outlineView, searchField: searchField, searchView: true)
        ReusableFunc.setupSearchField(
            searchField,
            systemSymbolName: "line.3.horizontal.decrease.circle"
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !isDataLoaded else { return }

        ReusableFunc.showProgressWindow(view)

        Task.detached { [weak self] in
            await self?.data.loadData()
            await MainActor.run { [weak self] in
                guard let self else { return }
                outlineView.delegate = dataVM
                outlineView.dataSource = dataVM
                searchField.delegate = dataVM
                dataVM.prepareData()
                outlineView.reloadData()
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                ReusableFunc.closeProgressWindow(self.view)
                self.isDataLoaded = true
            }
        }
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
