//
//  LibraryViewDelegate.swift
//  Maktabah
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
protocol LibraryViewDelegate: AnyObject {
    func didSelectItem(_ row: Int) async
    func openBookInNewTab(_ book: BooksData)
}

extension LibraryViewDelegate {
    func openBookInNewTab(_ book: BooksData) {}
}
