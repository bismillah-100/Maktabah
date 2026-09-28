//
//  SearchSortKey.swift
//  Maktabah
//

import Foundation

enum SearchSortKey: String, CaseIterable {
    case bookTitle, page, part

    var label: String {
        switch self {
        case .bookTitle: "Kitab"
        case .page: "Halaman"
        case .part: "Juz"
        }
    }
}
