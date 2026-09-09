//
//  iOSLibrary.swift
//  Maktabah
//

import Foundation


// MARK: - iOS Only

extension LibraryViewModel {
    func selectBook(_ book: BooksData, using navigationManager: iOSNavigationManager) {
        let lastId = historyManager.entriesByBookId[book.id]?.lastContentId
        navigationManager.openBook(book, initialContentId: lastId)
    }

    func notifySelectionChanged() {
        selectedBookIds = selectedBookIds
    }
}
