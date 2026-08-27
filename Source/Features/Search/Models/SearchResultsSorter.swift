//
//  SearchResultsSorter.swift
//  Maktabah
//

import Foundation

enum SearchResultsSorter {
    static func sort(_ results: inout [SearchResultItem], by key: SearchSortKey, ascending asc: Bool) {
        switch key {
        case .bookTitle:
            results.sort {
                let cmp = $0.bookTitle.localizedStandardCompare($1.bookTitle)
                if cmp != .orderedSame { return asc ? cmp == .orderedAscending : cmp == .orderedDescending }
                if $0.part != $1.part { return asc ? $0.part < $1.part : $0.part > $1.part }
                return asc ? $0.page < $1.page : $0.page > $1.page
            }

        case .page:
            results.sort {
                let cmp = $0.bookTitle.localizedStandardCompare($1.bookTitle)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                if $0.part != $1.part { return $0.part < $1.part }
                return asc ? $0.page < $1.page : $0.page > $1.page
            }

        case .part:
            results.sort {
                let cmp = $0.bookTitle.localizedStandardCompare($1.bookTitle)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                if $0.part != $1.part { return asc ? $0.part < $1.part : $0.part > $1.part }
                return $0.page < $1.page
            }

        case .content:
            results.sort {
                let cmp = $0.attributedText.contentSortKey.localizedStandardCompare($1.attributedText.contentSortKey)
                return asc ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
    }
}
