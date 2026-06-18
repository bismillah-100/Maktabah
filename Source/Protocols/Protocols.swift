//
//  Protocols.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

protocol SidebarDelegate: AnyObject {
    func didSelectItem(_ id: Int)
}

protocol LibraryDelegate: AnyObject {
    func didSelectBook(for book: BooksData) async
}


protocol ResultsDelegate: AnyObject {
    func didSelect(savedResults: [SavedResultsItem])
}

protocol TarjamahBDelegate: AnyObject {
    func didSelectRowi(rowi: Rowi)
    func didSelect(tarjamahB: TarjamahMen, query: String?) async
}

protocol LibraryViewDelegate: AnyObject {
    func didSelectItem(_ row: Int) async
}

protocol OptionSearchDelegate: AnyObject {
    func didSelectResult(for id: Int, highlightText: String) async
}

#if os(macOS)
protocol SearchableLibrarySidebar: AnyObject {
    var searchField: DSFSearchField! { get set }
    func connectSearchField(_ field: DSFSearchField)
}

// LibraryVC
extension LibraryVC: SearchableLibrarySidebar {
    func connectSearchField(_ field: DSFSearchField) {
        guard let searchField else {
            print("searchField nil")
            return
        }
        field.delegate = searchField.delegate
        dataVM.searchField = field
        if searchField != field {
            searchField.removeFromSuperview()
        }
        self.searchField = field
        dataVM.setupDSFSearchField()
        updateContentInset()
    }
}

// SearchSidebarVC
extension SearchSidebarVC: SearchableLibrarySidebar {
    func connectSearchField(_ field: DSFSearchField) {
        guard let searchField else {
            print("searchField nil")
            return
        }

        field.delegate = searchField.delegate
        dataVM.searchField = field
        if searchField != field {
            searchField.removeFromSuperview()
        }
        self.searchField = field
        dataVM.setupDSFSearchField()
        scrollViewTopConstraint.constant = 0
    }
}

// atau buat computed var yang wrap-nya
extension RowiSidebarVC: SearchableLibrarySidebar {
    func connectSearchField(_ field: DSFSearchField) {
        guard let searchField else {
            print("searchField nil")
            return
        }
        field.delegate = searchField.delegate
        if searchField != field {
            searchField.removeFromSuperview()
        }
        self.searchField = field
    }
}
#endif

