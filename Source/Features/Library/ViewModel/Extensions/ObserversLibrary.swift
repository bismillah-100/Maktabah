//
//  ObserversLibrary.swift
//  Maktabah
//

import Foundation

extension LibraryViewModel {
    // MARK: - Observers

    func setupObservers() {
        setupDebouncedStreams()
        observeBookIntegrated()
        observeBooksChanged()
        enableBookIdMigrationObserver()
        observeLibraryFolderChanged()
    }

    private func setupDebouncedStreams() {
        refreshSubject
            .debounce(for: .seconds(0.3), scheduler: RunLoop.current)
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    rootCategories = Array(dataManager.allRootCategories)
                    if viewMode == .author {
                        _authorHierarchy = dataManager.buildAuthorHierarchy()
                        _hasBuiltAuthorHierarchy = true
                    }
                    applyFilter(filterMode)
                }
            }
            .store(in: &cancellables)
    }

    private func observeBookIntegrated() {
        addObserver(forName: .bookIntegrated, object: nil, queue: .current) { [weak self] _ in
            Task { @MainActor [weak self] in
                #if os(iOS)
                self?.refreshSubject.send(())
                #endif
            }
        }
    }

    private func observeBooksChanged() {
        addObserver(forName: .booksChanged, object: nil, queue: .current) { [weak self] notification in
            Task { @MainActor [weak self] in
                #if os(iOS)
                self?.refreshSubject.send(())
                #endif
                self?.checkBookUpdatesPeriodically(force: true)
            }
        }
    }

    private func observeLibraryFolderChanged() {
        addObserver(forName: .libraryFolderChanged, object: nil, queue: .current) { [weak self] _ in
            guard let self, reloadTask == nil else { return }
            reloadTask?.cancel()
            reloadTask = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                await refreshLibrary()
                reloadTask = nil
            }
        }
    }
}
