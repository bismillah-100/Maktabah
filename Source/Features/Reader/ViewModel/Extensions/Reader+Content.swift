//
//  Reader+Content.swift
//  Maktabah
//

import Foundation

extension ReaderViewModel {
    // MARK: - Book Loading

    /// Loads initial content, optionally restoring a specific contentId
    func loadInitialContent(initialContentId: Int? = nil) {
        guard let book = currentBook else { return }

        do {
            try bookConnection.connect(archive: book.archive)
        } catch {
            contentText = DatabaseError.bookNotFound(book.archive).localizedDescription
        }

        loadTOC(book: book)
        guard let initialContentId else {
            loadFromHistory(for: book)
            return
        }

        if let content = getContent(
            bkId: book.id,
            contentId: initialContentId
        ) {
            updateContentState(with: content)
        } else {
            contentText = "Content ID not found."
        }
    }

    func loadTOC(book: BooksData) {
        tocViewModel.loadTOC(book: book)
    }

    func getContent(bkId: Int, contentId: Int) -> BookContent? {
        bookConnection.getContent(bkid: String(bkId), contentId: contentId)
    }

    func loadFromHistory(for book: BooksData) {
        // Try to restore from history first
        guard let lastContentId = historyVM.entriesByBookId[book.id]?.lastContentId,
              let content = bookConnection.getContent(bkid: String(book.id), contentId: lastContentId)
        else {
            getFirstBookContent(for: book)
            return
        }

        updateContentState(with: content)
    }

    func getFirstBookContent(for book: BooksData) {
        if let content = bookConnection.getFirstContent(bkid: String(book.id)) {
            updateContentState(with: content)
        } else {
            contentText = "No content found for this book."
        }
    }

    func fetchBookInfo(completion: @escaping (BooksData?) -> Void) {
        guard let currentBook else {
            completion(nil)
            return
        }
        let dm = LibraryDataManager.shared
        guard let bookOnLibrary = dm.getBook([currentBook.id]).first else {
            completion(nil)
            return
        }
        self.currentBook = bookOnLibrary
        dm.loadBookInfo(bookOnLibrary.id) {
            completion(bookOnLibrary)
        }
    }
}
