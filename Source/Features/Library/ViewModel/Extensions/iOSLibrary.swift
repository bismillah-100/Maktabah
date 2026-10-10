//
//  iOSLibrary.swift
//  Maktabah
//

import Foundation


// MARK: - iOS Only

extension LibraryViewModel {
    func selectBook(_ book: BooksData, using navigationManager: iOSNavigationManager) {
        let lastId = historyManager.entriesByBookId[book.id]?.lastContentId
        navigationManager.openBook(book, options: OpenBookOptions(contentId: lastId))
    }

    func notifySelectionChanged() {
        selectedBookIds = selectedBookIds
    }
}
