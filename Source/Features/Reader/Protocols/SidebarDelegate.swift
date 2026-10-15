//
//  SidebarDelegate.swift
//  Maktabah
//

import Foundation

@MainActor
protocol SidebarDelegate: AnyObject {
    func didSelectItem(_ id: Int)
    func didSelectItem(_ id: Int, title: String)
}

extension SidebarDelegate {
    func didSelectItem(_ id: Int) {}
    func didSelectItem(_ id: Int, title: String) {
        didSelectItem(id)
    }
}
