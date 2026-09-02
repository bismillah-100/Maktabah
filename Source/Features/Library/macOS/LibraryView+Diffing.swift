//
//  LibraryView+Diffing.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 03/09/26.
//

import Cocoa

extension LibraryViewManager {
    func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .historyDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                updateFlatList(
                    for: .history,
                    newBooks: historyManager.historyBooks,
                    categoryId: -2,
                    categoryName: String(localized: "History")
                )
                updateFlatList(
                    for: .favorites,
                    newBooks: historyManager.favoriteBooks,
                    categoryId: -1,
                    categoryName: String(localized: "Favorites")
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .bookIntegrated)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                if let bookId = notification.object as? Int {
                    self?.reloadParentCategory(ofBookId: bookId)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .booksChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleBooksChanged(notification)
            }
            .store(in: &cancellables)
    }

    private func updateFlatList(
        for mode: LibraryFilterMode,
        newBooks: [BooksData],
        categoryId: Int,
        categoryName: String
    ) {
        guard viewModel.isFlatMode, viewModel.filterMode == mode else { return }
        updateFlatListIncrementally(
            newBooks: newBooks,
            fallbackCategoryId: categoryId,
            fallbackCategoryName: categoryName
        )
    }

    private func updateFlatListIncrementally(
        newBooks: [BooksData],
        fallbackCategoryId: Int,
        fallbackCategoryName: String
    ) {
        guard let firstCat = viewModel.displayedCategories.first else {
            viewModel.displayedCategories = newBooks.isEmpty ? [] : [{
                let cat = CategoryData(id: fallbackCategoryId, name: fallbackCategoryName, level: 1, order: 0)
                cat.children = newBooks
                return cat
            }()]
            outlineView.reloadData()
            return
        }

        let oldBooks = firstCat.children.compactMap { $0 as? BooksData }
        let oldIds = oldBooks.map(\.id)
        let newIds = newBooks.map(\.id)

        if oldIds == newIds { return }

        var currentBooks = oldBooks
        outlineView.beginUpdates()

        let newIdSet = Set(newIds)
        for (index, oldBook) in currentBooks.enumerated().reversed() where !newIdSet.contains(oldBook.id) {
            outlineView.removeItems(at: IndexSet(integer: index), inParent: nil, withAnimation: [.slideUp])
            currentBooks.remove(at: index)
        }

        firstCat.children = currentBooks

        for (newIndex, newBook) in newBooks.enumerated() {
            if let oldIndex = currentBooks.firstIndex(where: { $0.id == newBook.id }) {
                if oldIndex != newIndex {
                    outlineView.moveItem(at: oldIndex, inParent: nil, to: newIndex, inParent: nil)
                    let movedBook = currentBooks.remove(at: oldIndex)
                    currentBooks.insert(movedBook, at: newIndex)
                    firstCat.children = currentBooks
                }
            } else {
                currentBooks.insert(newBook, at: newIndex)
                firstCat.children = currentBooks
                outlineView.insertItems(at: IndexSet(integer: newIndex), inParent: nil, withAnimation: [.slideDown])
            }
        }
        outlineView.endUpdates()

        if viewModel.isFlatMode, let selectedBook = viewModel.selectedBookName {
            restoreFlatSelection(byBookName: selectedBook)
        }
    }

    private func handleBooksChanged(_ notification: Notification) {
        guard let payload = notification.object as? BooksChangedNotification else { return }
        for (categoryId, book) in payload.insertedBooks {
            if let category = findCategoryInDisplayed(categoryId) {
                viewModel.bookLookup[book.book] = (category, book)

                if viewModel.searchQuery.isEmpty {
                    outlineView.expandItem(category, expandChildren: true)
                    outlineView.reloadItem(category, reloadChildren: true)
                    let row = outlineView.row(forItem: book)
                    if row >= 0 {
                        outlineView.scrollRowToVisible(row)
                    }
                } else {
                    let currentQuery = viewModel.searchQuery
                    let base = viewModel.baseCategories.isEmpty ? viewModel.displayedCategories : viewModel.baseCategories
                    var filtered: [CategoryData] = []
                    _ = dataManager.filterContent(
                        with: currentQuery,
                        displayedCategories: &filtered,
                        baseCategories: base
                    )
                    viewModel.displayedCategories = filtered
                    outlineView.reloadData()
                }
            }
        }
        if !payload.updatedBookIds.isEmpty {
            reloadUpdatedBooks(payload.updatedBookIds)
        }
    }

    private func reloadUpdatedBooks(_ bookIds: Set<Int>) {
        for bookId in bookIds {
            guard let book = dataManager.booksById[bookId] else { continue }
            for (oldName, value) in viewModel.bookLookup where value.book.id == bookId {
                viewModel.bookLookup.removeValue(forKey: oldName)
                viewModel.bookLookup[book.book] = (value.category, book)
                break
            }
            outlineView.reloadItem(book, reloadChildren: false)
        }
    }

    private func reloadParentCategory(ofBookId bookId: Int) {
        if viewModel.showOnlyDownloaded {
            handleIntegratedBookUpdate(bookId)
            return
        }
        guard let parent = findParentCategory(ofBookId: bookId, in: viewModel.displayedCategories) else { return }

        if downloadView || viewModel.isDownloadModal {
            if let childIndex = parent.children.firstIndex(where: { ($0 as? BooksData)?.id == bookId }) {
                outlineView.beginUpdates()

                if parent.children.count == 1 {
                    parent.children.remove(at: childIndex)
                    viewModel.selectedBookIds.remove(bookId)
                    if let index = viewModel.displayedCategories.firstIndex(where: { $0 === parent }) {
                        viewModel.displayedCategories.remove(at: index)
                        outlineView.removeItems(at: IndexSet(integer: index), inParent: nil, withAnimation: [.slideUp])
                    }
                    viewModel.baseCategories = viewModel.displayedCategories
                } else {
                    parent.children.remove(at: childIndex)
                    outlineView.removeItems(at: IndexSet(integer: childIndex), inParent: parent, withAnimation: [.slideUp])
                }

                outlineView.endUpdates()
                outlineView.reloadItem(parent, reloadChildren: false)
            }
        } else {
            if let book = parent.children.first(where: { ($0 as? BooksData)?.id == bookId }) {
                outlineView.reloadItem(book, reloadChildren: false)
            }
        }
    }

    private func handleIntegratedBookUpdate(_ bookId: Int) {
        guard let book = dataManager.booksById[bookId] else {
            removeBookFromDisplayed(bookId: bookId)
            return
        }
        if BookArchiveIntegrator.shared.isBookIntegrated(book) {
            insertIntegratedBookIntoDisplayed(book)
        } else if viewModel.showOnlyDownloaded {
            removeBookFromDisplayed(bookId: bookId)
        }
    }

    private func removeBookFromDisplayed(bookId: Int) {
        func findAndRemove(in list: inout [CategoryData], parent: CategoryData?) -> Bool {
            var anyChanged = false
            for i in (0 ..< list.count).reversed() {
                let category = list[i]

                if let bookIndex = category.children.firstIndex(where: { ($0 as? BooksData)?.id == bookId }) {
                    outlineView.removeItems(at: IndexSet(integer: bookIndex), inParent: category, withAnimation: [.slideUp])
                    category.children.remove(at: bookIndex)
                    anyChanged = true
                }

                var subChanged = false
                for j in (0 ..< category.children.count).reversed() {
                    if let sub = category.children[j] as? CategoryData {
                        var subList = [sub]
                        if findAndRemove(in: &subList, parent: category) {
                            if subList.isEmpty {
                                outlineView.removeItems(at: IndexSet(integer: j), inParent: category, withAnimation: [.slideUp])
                                category.children.remove(at: j)
                            }
                            subChanged = true
                        }
                    }
                }

                if subChanged || anyChanged {
                    return true
                }
            }
            return false
        }

        var list = viewModel.displayedCategories
        if findAndRemove(in: &list, parent: nil) {
            var rootChanged = false
            for i in (0 ..< list.count).reversed() where list[i].children.isEmpty {
                outlineView.removeItems(at: IndexSet(integer: i), inParent: nil, withAnimation: [.slideUp])
                list.remove(at: i)
                rootChanged = true
            }

            if rootChanged {
                viewModel.displayedCategories = list
                viewModel.baseCategories = viewModel.displayedCategories
            } else {
                viewModel.baseCategories = list
            }
        }
    }

    private func findParentCategory(ofBookId bookId: Int, in categories: [CategoryData]) -> CategoryData? {
        for category in categories {
            for child in category.children {
                if let b = child as? BooksData, b.id == bookId { return category }
                if let sub = child as? CategoryData,
                   let found = findParentCategory(ofBookId: bookId, in: [sub]) { return found }
            }
        }
        return nil
    }

    private func findPathToBook(bookId: Int, in categories: [CategoryData]) -> [CategoryData]? {
        for category in categories {
            for child in category.children {
                if let b = child as? BooksData, b.id == bookId { return [category] }
                if let sub = child as? CategoryData,
                   let path = findPathToBook(bookId: bookId, in: [sub]) { return [category] + path }
            }
        }
        return nil
    }

    @discardableResult
    private func insertBook(
        _ book: BooksData,
        originalCategory: CategoryData,
        targetCategory: CategoryData
    ) -> Int? {
        if targetCategory.children.contains(where: { ($0 as? BooksData)?.id == book.id }) {
            return nil
        }
        let existingBooks = targetCategory.children.compactMap { $0 as? BooksData }
        let originalIndex = originalCategory.children.firstIndex { ($0 as? BooksData)?.id == book.id } ?? originalCategory.children.count
        var insertBookIndex = 0
        for existingBook in existingBooks {
            let existingIndex = originalCategory.children.firstIndex { ($0 as? BooksData)?.id == existingBook.id } ?? originalCategory.children.count
            if existingIndex > originalIndex { break }
            insertBookIndex += 1
        }
        let firstBookIndex = targetCategory.children.firstIndex { $0 is BooksData } ?? targetCategory.children.count
        targetCategory.children.insert(book, at: firstBookIndex + insertBookIndex)
        return firstBookIndex + insertBookIndex
    }

    @discardableResult
    private func insertCategory(_ category: CategoryData, into list: inout [CategoryData]) -> Int {
        let insertIndex = list.firstIndex { $0.order > category.order } ?? list.count
        list.insert(category, at: insertIndex)
        return insertIndex
    }

    @discardableResult
    private func insertCategory(_ category: CategoryData, into children: inout [Any]) -> Int {
        let firstBookIndex = children.firstIndex { $0 is BooksData } ?? children.count
        let categoryIndex = children.enumerated().first { _, element in
            guard let existing = element as? CategoryData else { return false }
            return existing.order > category.order
        }?.offset ?? firstBookIndex
        let insertIndex = min(categoryIndex, firstBookIndex)
        children.insert(category, at: insertIndex)
        return insertIndex
    }

    private func insertIntegratedBookIntoDisplayed(_ book: BooksData) {
        guard let path = findPathToBook(bookId: book.id, in: dataManager.allRootCategories),
              let originalLeaf = path.last else { return }

        var currentParent: CategoryData?
        for category in path {
            if let parent = currentParent {
                if let existing = parent.children.compactMap({ $0 as? CategoryData }).first(where: { $0.id == category.id }) {
                    currentParent = existing
                } else {
                    let clone = category.copy()
                    clone.children = []
                    let insertIndex = insertCategory(clone, into: &parent.children)
                    outlineView.insertItems(at: IndexSet(integer: insertIndex), inParent: parent, withAnimation: [.slideDown])
                    currentParent = clone
                }
            } else {
                if let existing = viewModel.displayedCategories.first(where: { $0.id == category.id }) {
                    currentParent = existing
                } else {
                    let clone = category.copy()
                    clone.children = []
                    var list = viewModel.displayedCategories
                    let insertIndex = insertCategory(clone, into: &list)
                    viewModel.displayedCategories = list
                    outlineView.insertItems(at: IndexSet(integer: insertIndex), inParent: nil, withAnimation: [.slideDown])
                    currentParent = clone
                }
            }
        }

        guard let leaf = currentParent else { return }

        let insertIndex = insertBook(book, originalCategory: originalLeaf, targetCategory: leaf)

        if let insertIndex {
            outlineView.insertItems(at: IndexSet(integer: insertIndex), inParent: leaf, withAnimation: [.slideDown])
        }

        if let bookName = viewModel.selectedBookName {
            restoreSelection(byBookName: bookName)
        }
    }

    func findCategoryInDisplayed(_ categoryId: Int) -> CategoryData? {
        func search(_ category: CategoryData) -> CategoryData? {
            if category.id == categoryId { return category }
            for child in category.children {
                if let sub = child as? CategoryData, let found = search(sub) { return found }
            }
            return nil
        }
        for root in viewModel.displayedCategories {
            if let found = search(root) { return found }
        }
        return nil
    }
}
