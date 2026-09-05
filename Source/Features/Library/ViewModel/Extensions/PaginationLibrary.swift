//
//  PaginationLibrary.swift
//  Maktabah
//

import Foundation

extension LibraryViewModel {
    // MARK: - Authors Pagination (Unified)

    var hasMoreAuthors: Bool {
        let total = showOnlyDownloaded
            ? _cachedDisplayedCategories.count
            : (searchQuery.isEmpty ? _authorHierarchy.count : _allFilteredAuthors.count)
        let displayed = searchQuery.isEmpty ? _displayedAuthorCount : _displayedFilteredCount
        return viewMode == .author && displayed < total
    }

    var totalAuthorCount: Int {
        searchQuery.isEmpty
            ? (showOnlyDownloaded ? _cachedDisplayedCategories.count : _authorHierarchy.count)
            : _allFilteredAuthors.count
    }

    func resetAuthorPagination() {
        _displayedAuthorCount = authorPageSize
        _displayedFilteredCount = authorPageSize
    }

    func loadMoreAuthors() {
        let total = showOnlyDownloaded
            ? _cachedDisplayedCategories.count
            : (searchQuery.isEmpty ? _authorHierarchy.count : _allFilteredAuthors.count)
        if searchQuery.isEmpty {
            _displayedAuthorCount = min(_displayedAuthorCount + authorPageSize, total)
        } else {
            _displayedFilteredCount = min(_displayedFilteredCount + authorPageSize, _allFilteredAuthors.count)
        }
        updateDisplayedCategories()
    }
}
