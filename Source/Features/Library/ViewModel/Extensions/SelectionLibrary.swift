//
//  SelectionLibrary.swift
//  Maktabah
//

import Foundation

extension LibraryViewModel {
    // MARK: - Selection Operations

    func enterSelectionMode(selecting book: BooksData? = nil) {
        isSelectionMode = true
        if let book {
            toggleBookSelection(book)
        }
    }

    func exitSelectionMode() {
        isSelectionMode = false
        selectedBookIds.removeAll()
    }

    func isBookSelected(_ book: BooksData) -> Bool {
        selectedBookIds.contains(book.id)
    }

    func toggleBookSelection(_ book: BooksData) {
        if selectedBookIds.contains(book.id) {
            selectedBookIds.remove(book.id)
        } else {
            selectedBookIds.insert(book.id)
        }
    }

    func isCategorySelected(_ category: CategoryData) -> Bool {
        let books = getAllBooks(in: category)
        return !books.isEmpty && books.allSatisfy { selectedBookIds.contains($0.id) }
    }

    func isCategoryPartiallySelected(_ category: CategoryData) -> Bool {
        let books = getAllBooks(in: category)
        guard !books.isEmpty else { return false }
        return books.contains { selectedBookIds.contains($0.id) } && books.contains { !selectedBookIds.contains($0.id) }
    }

    func toggleCategorySelection(_ category: CategoryData) {
        let books = getAllBooks(in: category)
        guard !books.isEmpty else { return }
        var currentSelection = selectedBookIds
        if books.allSatisfy({ currentSelection.contains($0.id) }) {
            books.forEach { currentSelection.remove($0.id) }
        } else {
            books.forEach { currentSelection.insert($0.id) }
        }
        selectedBookIds = currentSelection
    }

    func selectAllBook(state: Bool) {
        if state {
            var newSelection = selectedBookIds
            for category in displayedCategories {
                let books = getAllBooks(in: category)
                books.forEach { newSelection.insert($0.id) }
            }
            selectedBookIds = newSelection
        } else {
            selectedBookIds.removeAll()
        }
    }

    // MARK: - Helpers

    func getAllBooks(in category: CategoryData) -> [BooksData] {
        category.allBooks
    }

    var selectedDeleteBooks: [BooksData] {
        booksForSelectedIds(in: displayedCategories).filter { isBookDownloaded($0) }
    }

    var selectedDeleteCount: Int {
        selectedDeleteBooks.count
    }

    var selectedDownloadBooks: [BooksData] {
        booksForSelectedIds(in: displayedCategories).filter { !isBookDownloaded($0) }
    }

    var selectedDownloadCount: Int {
        selectedDownloadBooks.count
    }

    func booksForSelectedIds(in categories: [CategoryData]) -> [BooksData] {
        categories.flatMap { getAllBooks(in: $0).filter { selectedBookIds.contains($0.id) } }
    }

    // MARK: - Actions

    func handleBookSelection(book: BooksData) {
        if selectedBookName == book.book {
            return
        }
        selectedBookName = book.book

        historySelectionTask?.cancel()
        historySelectionTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.historyManager.addBookToHistory(book.id)
            }
        }
    }

    func startBulkDeletion(onFinished: @escaping () -> Void) {
        let books = selectedDeleteBooks
        guard !books.isEmpty else { return }
        Task { [weak self] in
            for book in books {
                try? await BookArchiveIntegrator.shared.removeBookFromArchive(book)
            }
            self?.exitSelectionMode()
            onFinished()
        }
    }

    func deleteSingleBook(_ book: BooksData) async {
        try? await BookArchiveIntegrator.shared.removeBookFromArchive(book)
    }

    func restoreSelectionEntry(byBookName bookName: String) -> (category: CategoryData, book: BooksData)? {
        bookLookup[bookName]
    }
}
