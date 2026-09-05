//
//  Search+Library.swift
//  Maktabah
//

import Foundation

extension SearchViewModel {
    // MARK: - Library

    func loadLibraryData() {
        Task { [weak self] in
            guard let self, state == .loading else { return }
            await ldm.loadData()
            await ldm.buildArchive()
            await MainActor.run {
                self.state = .loaded
                #if os(iOS)
                self.updateDisplayedCategories()
                #endif
            }
        }
    }

    func getCheckedTables(from categories: [CategoryData]) -> Set<String> {
        ldm.getCheckedTables(categories)
    }

    func getBookTitle(for bookId: Int) -> String? {
        ldm.booksById[bookId]?.book
    }

    /// Resolve `BooksData` dari `SearchResultItem`. Returns nil jika tidak ditemukan.
    func resolveBook(from result: SearchResultItem) -> BooksData? {
        let table = result.tableName.hasPrefix("b")
            ? String(result.tableName.dropFirst())
            : result.tableName
        guard let tableInt = Int(table) else { return nil }
        return ldm.getBook([tableInt]).first
    }
}
