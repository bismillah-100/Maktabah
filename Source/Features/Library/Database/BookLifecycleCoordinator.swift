//
//  BookLifecycleCoordinator.swift
//  Maktabah
//

import Foundation

/// Coordinates final MainActor cache invalidation and typed/legacy notification emission
/// only after DB mutations, disk updates, and in-memory catalog updates have finished.
final class BookLifecycleCoordinator: Sendable {
    static let shared = BookLifecycleCoordinator()

    private init() {}

    func emit(
        _ event: BookLifecycleEvent,
        insertedBooks: [(categoryId: Int, book: BooksData)] = [],
        updatedBookIds: Set<Int> = [],
        postLegacyBooksChanged: Bool = true,
        postLegacyIntegratedIds: [Int] = []
    ) async {
        await MainActor.run {
            emitOnMainActor(
                event,
                insertedBooks: insertedBooks,
                updatedBookIds: updatedBookIds,
                postLegacyBooksChanged: postLegacyBooksChanged,
                postLegacyIntegratedIds: postLegacyIntegratedIds
            )
        }
    }

    func emitFromSyncContext(
        _ event: BookLifecycleEvent,
        insertedBooks: [(categoryId: Int, book: BooksData)] = [],
        updatedBookIds: Set<Int> = [],
        postLegacyBooksChanged: Bool = true,
        postLegacyIntegratedIds: [Int] = []
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                emitOnMainActor(
                    event,
                    insertedBooks: insertedBooks,
                    updatedBookIds: updatedBookIds,
                    postLegacyBooksChanged: postLegacyBooksChanged,
                    postLegacyIntegratedIds: postLegacyIntegratedIds
                )
            }
            return
        }

        let sendableInserted = insertedBooks
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.emitOnMainActor(
                    event,
                    insertedBooks: sendableInserted,
                    updatedBookIds: updatedBookIds,
                    postLegacyBooksChanged: postLegacyBooksChanged,
                    postLegacyIntegratedIds: postLegacyIntegratedIds
                )
            }
        }
    }

    @MainActor
    func emitOnMainActor(
        _ event: BookLifecycleEvent,
        insertedBooks: [(categoryId: Int, book: BooksData)] = [],
        updatedBookIds: Set<Int> = [],
        postLegacyBooksChanged: Bool = true,
        postLegacyIntegratedIds: [Int] = []
    ) {
        BookCacheCoordinator.shared.invalidateMainActorCaches(for: event)
        NotificationCenter.default.post(name: .bookLifecycleDidChange, object: event)

        switch event {
        case let .integrated(bookIds, _):
            let ids = postLegacyIntegratedIds.isEmpty ? Array(bookIds) : postLegacyIntegratedIds
            for id in ids {
                NotificationCenter.default.post(name: .bookIntegrated, object: id)
            }

        case let .updated(bookIds, _, _):
            let idsToReport = updatedBookIds.isEmpty ? bookIds : updatedBookIds
            if postLegacyBooksChanged, !insertedBooks.isEmpty || !idsToReport.isEmpty {
                NotificationCenter.default.postBooksChanged(
                    insertedBooks: insertedBooks,
                    updatedBookIds: idsToReport
                )
            }
            for id in postLegacyIntegratedIds {
                NotificationCenter.default.post(name: .bookIntegrated, object: id)
            }

        case let .deleted(bookIds, _, _):
            let ids = postLegacyIntegratedIds.isEmpty ? Array(bookIds) : postLegacyIntegratedIds
            for id in ids {
                NotificationCenter.default.post(name: .bookIntegrated, object: id)
            }

        case let .idChanged(oldId, newId, _, _):
            NotificationCenter.default.post(
                name: .bookIdMigrated,
                object: nil,
                userInfo: ["oldId": oldId, "newId": newId]
            )

        case .libraryFolderChanged:
            NotificationCenter.default.post(name: .libraryFolderChanged, object: nil)

        case .bundledDataCleaned:
            break
        }
    }
}
