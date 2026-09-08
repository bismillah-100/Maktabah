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
            object: nil, queue: .current
        ) { [weak self] _ in
            Task { @MainActor in self?.handleLibraryFolderChanged() }
        }
        addObserver(
            forName: .bookIntegrated,
            object: nil, queue: .current
        ) { [weak self] notification in
            Task { @MainActor in self?.handleBookIntegrated(notification) }
        }

        #endif

        enableBookIdMigrationObserver()

        #if os(iOS)
        annotationCancellable = annotationStore.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadAnnotations()
            }
        #endif
    }
}
