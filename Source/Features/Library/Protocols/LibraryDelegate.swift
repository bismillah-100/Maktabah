//
//  LibraryDelegate.swift
//  Maktabah
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

protocol LibraryDelegate: AnyObject {
    func didSelectBook(for book: BooksData, loadContent: Bool) async
}
