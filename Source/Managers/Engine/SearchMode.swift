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
}
