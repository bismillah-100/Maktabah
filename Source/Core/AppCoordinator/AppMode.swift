//
//  AppMode.swift
//  maktab
//
//  Created by MacBook on 07/12/25.
//

import Foundation

enum AppMode: Int {
    case viewer
    case search
    case narrator
    #if os(iOS)
    case annotations
    case history
    #endif
}

enum LibraryViewMode: Int {
    case category = 0
    case author = 1
}
