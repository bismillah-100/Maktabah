//
//  SidebarDelegate.swift
//  Maktabah
//

import Foundation

@MainActor
protocol SidebarDelegate: AnyObject {
    func didSelectItem(_ id: Int)
}
