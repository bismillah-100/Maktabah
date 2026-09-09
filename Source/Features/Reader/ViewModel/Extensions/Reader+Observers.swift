//
//  Reader+Observers.swift
//  Maktabah
//

import Foundation

extension ReaderViewModel {
    // MARK: - Notification Observers

    func setupNotificationObservers() {
        #if os(macOS)
        addObserver(
            forName: .libraryFolderChanged,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleLibraryFolderChanged() }
        }
        addObserver(
            forName: .bookIntegrated,
            object: nil, queue: .main
        ) { [weak self] notification in
            let bookId = notification.object as? Int
            Task { @MainActor [weak self] in self?.handleBookIntegrated(bookId: bookId) }
        }

        #endif

        enableBookIdMigrationObserver()

        #if os(iOS)
        annotationCancellable = annotationStore.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.loadAnnotations()
                }
            }
        #endif
    }
}
