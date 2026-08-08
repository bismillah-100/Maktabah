//
//  SearchMode.swift
//  maktab
//
//  Created by MacBook on 09/12/25.
//

import Foundation

enum SearchMode: Int, CaseIterable, Identifiable {
    case phrase
    case contains
    case or
    case near

    var id: Int { rawValue }

    static func imageNameForMode(_ searchMode: SearchMode) -> String {
        return switch searchMode {
        case .phrase: "text.quote"
        case .contains: "checklist.checked"
        case .or: "checklist"
        case .near: "text.word.spacing"
        }
    }
}
