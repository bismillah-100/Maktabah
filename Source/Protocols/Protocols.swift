//
//  Protocols.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

import Cocoa

protocol SidebarDelegate: AnyObject {
    func didSelectItem(_ id: Int)
}

protocol LibraryDelegate: AnyObject {
    func didSelectBook(for book: BooksData) async
}

protocol NavigationDelegate: AnyObject {
    func sliderDidNavigateInto(content: BookContent)
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
