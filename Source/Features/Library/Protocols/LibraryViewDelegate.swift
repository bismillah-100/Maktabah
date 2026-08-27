//
//  LibraryViewDelegate.swift
//  Maktabah
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

protocol LibraryViewDelegate: AnyObject {
    func didSelectItem(_ row: Int) async
}
