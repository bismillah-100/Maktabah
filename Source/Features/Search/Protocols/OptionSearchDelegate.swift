//
//  OptionSearchDelegate.swift
//  Maktabah
//

import Foundation

@MainActor
protocol OptionSearchDelegate: AnyObject {
    func didSelectResult(
        for id: Int,
        highlightText: String,
        mode: SearchMode?,
        nearDistance: Int
    ) async
}
