//
//  Reader+Observers.swift
//  Maktabah
//

import Foundation
import OSLog

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
        #endif

        addObserver(
            forName: .bookLifecycleDidChange,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.bookLifecycleEvent else { return }
            Task { @MainActor [weak self] in self?.handleBookLifecycleEvent(event) }
        }

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

    private func handleBookLifecycleEvent(_ event: BookLifecycleEvent) {
        switch event {
        case let .deleted(bookIds, _, removedFromCatalog):
            guard let book = currentBook, bookIds.contains(book.id) else { return }
            let isGone = removedFromCatalog.contains(book.id) || (AppConfig.isUsingBundleMode && !BookArchiveIntegrator.shared.isBookIntegrated(book))
            if isGone {
                #if os(macOS)
                cleanUpState()
                #else
                resetReaderForDeletedOrCleanedBook()
                #endif
            }

        case let .updated(bookIds, _, _), let .integrated(bookIds, _):
            guard let id = currentBook?.id, bookIds.contains(id),
                  let freshBook = LibraryDataManager.shared.booksById[id]
            else { return }
            reloadCurrentBookAfterUpdate(freshBook)

        case .libraryFolderChanged, .bundledDataCleaned:
            #if os(macOS)
            handleLibraryFolderChanged()
            #else
            resetReaderForDeletedOrCleanedBook()
            #endif

        case .idChanged:
            break
        }
    }

    private func reloadCurrentBookAfterUpdate(_ book: BooksData) {
        currentBook = book
        do {
            try bookConnection.connect(archive: book.archive, force: true)
        } catch {
            Logger.reader.error("Failed to reconnect after update: \(error.localizedDescription, privacy: .public)")
        }

        loadTOC(book: book)
        if currentContentId > 0, let content = bookConnection.getContent(bkid: "\(book.id)", contentId: currentContentId) {
            updateContentState(with: content)
        } else {
            loadFromHistory(for: book)
        }
    }

    #if os(iOS)
    private func resetReaderForDeletedOrCleanedBook() {
        currentBook = nil
        contentText = ""
        currentPage = nil
        currentPart = nil
        currentID = nil
        currentContentId = 0
        currentAnnotations = []
        bookConnectionMutex.withLock { $0 = .init() }
    }
    #endif
}
