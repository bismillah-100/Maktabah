//
//  Search+Observers.swift
//  Maktabah
//

import Foundation

extension SearchViewModel {
    // MARK: - Observers

    func setupObservers() {
        #if os(iOS)
        setupDebouncedFilters()
        #endif
        observeBooksReloadNotifications()
        enableBookIdMigrationObserver()
        observeLibraryFolderChanged()
    }

    func notifySearchReload() {
        Task { [weak self] in
            #if os(macOS)
            self?.searchNeedsReload.send(())
            #else
            self?.refreshSubject.send(())
            #endif
        }
    }

    func observeBooksReloadNotifications() {
        for name in [Notification.Name.bookIntegrated, .booksChanged] {
            addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.notifySearchReload()
                }
            }
        }

        addObserver(forName: .bookLifecycleDidChange, object: nil, queue: .main) { [weak self] notification in
            guard let event = notification.bookLifecycleEvent else { return }
            MainActor.assumeIsolated { [weak self] in
                self?.handleBookLifecycleEvent(event)
            }
        }
    }

    private func handleBookLifecycleEvent(_ event: BookLifecycleEvent) {
        switch event {
        case let .deleted(bookIds, _, removedFromCatalog):
            let goneTables = Set(bookIds.compactMap { id -> String? in
                if removedFromCatalog.contains(id) {
                    return BookTableName.prefixedTableName(from: String(id))
                }
                if let book = ldm.booksById[id], !AppConfig.isUsingBundleMode || BookArchiveIntegrator.shared.isBookIntegrated(book) {
                    return nil
                }
                return BookTableName.prefixedTableName(from: String(id))
            })
            if !goneTables.isEmpty {
                results.removeAll { goneTables.contains($0.tableName) }
                let goneIds = Set(goneTables.compactMap(BookTableName.bookId(from:)))
                selectedBookIds.subtract(goneIds)
            }
            SearchHitResolver.shared.clearCache()
            #if os(iOS)
            updateDisplayedCategories()
            #endif
            notifySearchReload()

        case .updated, .integrated:
            SearchHitResolver.shared.clearCache()
            #if os(iOS)
            updateDisplayedCategories()
            #endif
            notifySearchReload()

        case .bundledDataCleaned:
            resetForWorkspaceOrDataReset()

        case .idChanged, .libraryFolderChanged:
            break
        }
    }

    private func resetForWorkspaceOrDataReset() {
        stopSearch()
        results.removeAll()
        selectedBookIds.removeAll()
        query = ""
        targetBookId = ""
        SearchHitResolver.shared.clearCache()
        #if os(iOS)
        updateDisplayedCategories()
        #endif
        notifySearchReload()
    }

    func observeLibraryFolderChanged() {
        addObserver(forName: .libraryFolderChanged, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                stopSearch()
                results.removeAll()
                selectedBookIds.removeAll()
                query = ""
                targetBookId = ""
                SearchHitResolver.shared.clearCache()
                state = .loading
                ldm.resetState()
                await ldm.reloadAllData()
                await ldm.buildArchive()
                #if os(iOS)
                updateDisplayedCategories()
                #endif
                state = .loaded
            }
        }
    }
}
