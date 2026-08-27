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
    func didSelectBook(for book: BooksData, loadContent: Bool) async
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
    func didSelectResult(
        for id: Int,
        highlightText: String,
        mode: SearchMode?,
        nearDistance: Int
    ) async
}

#if os(macOS)
@MainActor
protocol SearchableLibrarySidebar: AnyObject {
    var searchField: DSFSearchField! { get set }
    func connectSearchField(_ field: DSFSearchField)
}

@MainActor
extension SearchableLibrarySidebar {
    func bindSearchField(
        _ field: DSFSearchField,
        setup: ((DSFSearchField) -> Void)? = nil,
        onConnected: (() -> Void)? = nil
    ) {
        guard let searchField else {
            print("searchField nil")
            return
        }
        field.delegate = searchField.delegate
        setup?(field)
        if searchField != field {
            searchField.removeFromSuperview()
        }
        self.searchField = field
        onConnected?()
    }

    func bindSearchField(
        _ field: DSFSearchField,
        withManager dataVM: LibraryViewManager,
        onConnected: (() -> Void)? = nil
    ) {
        bindSearchField(field, setup: { f in
            dataVM.searchField = f
            dataVM.setupDSFSearchField()
        }, onConnected: onConnected)
    }
}

/// LibraryVC
extension LibraryVC: SearchableLibrarySidebar {
    func connectSearchField(_ field: DSFSearchField) {
        bindSearchField(field, withManager: dataVM) { [weak self] in
            self?.updateContentInset()
        }
    }
}

/// SearchSidebarVC
extension SearchSidebarVC: SearchableLibrarySidebar {
    func connectSearchField(_ field: DSFSearchField) {
        bindSearchField(field, withManager: dataVM) { [weak self] in
            self?.scrollViewTopConstraint.constant = 0
        }
    }
}

/// atau buat computed var yang wrap-nya
extension RowiSidebarVC: SearchableLibrarySidebar {
    func connectSearchField(_ field: DSFSearchField) {
        bindSearchField(field)
    }
}
#endif
