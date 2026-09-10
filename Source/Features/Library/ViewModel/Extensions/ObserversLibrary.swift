//
//  ObserversLibrary.swift
//  Maktabah
//

import Foundation
import Synchronization

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
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { [weak self] in
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
        #if os(iOS)
        addObserver(forName: .bookIntegrated, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                self?.updateDisplayedCategories()
            }
        }
        #endif
    }

    private func observeBooksChanged() {
        addObserver(forName: .booksChanged, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { [weak self] in
                #if os(iOS)
                self?.updateDisplayedCategories()
                #endif
                self?.checkBookUpdatesPeriodically(force: true)
            }
        }
    }

    private func observeLibraryFolderChanged() {
        addObserver(forName: .libraryFolderChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                selectedBookName = nil
            }
            reloadTask.withLock { currentTask in
                if currentTask == nil {
                    currentTask = Task { [weak self] in
                        guard let self, !Task.isCancelled else { return }
                        await refreshLibrary()
                        reloadTask.withLock { $0 = nil }
                    }
                }
            }
        }
    }
}
