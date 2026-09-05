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
        Task { @MainActor [weak self] in
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
                self?.notifySearchReload()
            }
        }
    }

    func observeLibraryFolderChanged() {
        addObserver(forName: .libraryFolderChanged, object: nil, queue: .current) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                stopSearch()
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
