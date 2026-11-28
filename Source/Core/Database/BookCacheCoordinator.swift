//
//  BookCacheCoordinator.swift
//  Maktabah
//

import Foundation

/// Centralized coordinator for closing archive connections and invalidating runtime caches.
final class BookCacheCoordinator: Sendable {
    static let shared = BookCacheCoordinator()

    private init() {}

    func closeArchiveConnections(archiveIds: Set<Int>) {
        for archiveId in archiveIds where archiveId >= 0 {
            LibraryDataManager.shared.closeArchiveConnection(archiveId: archiveId)
        }
    }

    func closeAllArchiveConnections() {
        LibraryDataManager.shared.closeAllArchiveConnections()
    }

    func invalidateBookRuntimeCaches(bookId: Int) {
        BookPageCache.shared.remove(bookId: bookId)
        BookConnection.invalidateTOC(for: bookId)
        BookConnection.totalPartsCache.removeObject(forKey: NSString(string: String(bookId)))
        DatabaseManager.shared.invalidateShortCache(bookId: bookId)
        BookDownloadManager.shared.removeCachedBook(bookId: bookId)
    }

    func invalidateSynchronously(for event: BookLifecycleEvent) {
        switch event {
        case let .integrated(bookIds, archiveIds):
            for archiveId in archiveIds {
                DatabaseManager.shared.invalidateArchiveCache(archiveId: archiveId)
            }
            for bookId in bookIds {
                invalidateBookRuntimeCaches(bookId: bookId)
                for archiveId in archiveIds {
                    IntegrationCache.shared.markIntegrated(bookId: bookId, archiveId: archiveId)
                }
            }

        case let .updated(bookIds, oldArchiveIds, newArchiveIds):
            for archiveId in oldArchiveIds.union(newArchiveIds) {
                DatabaseManager.shared.invalidateArchiveCache(archiveId: archiveId)
            }
            for bookId in bookIds {
                invalidateBookRuntimeCaches(bookId: bookId)
                for oldArchiveId in oldArchiveIds where !newArchiveIds.contains(oldArchiveId) {
                    IntegrationCache.shared.unmarkIntegrated(bookId: bookId, archiveId: oldArchiveId)
                }
                for newArchiveId in newArchiveIds {
                    IntegrationCache.shared.markIntegrated(bookId: bookId, archiveId: newArchiveId)
                }
            }

        case let .deleted(bookIds, archiveIds, _):
            for archiveId in archiveIds {
                DatabaseManager.shared.invalidateArchiveCache(archiveId: archiveId)
            }
            for bookId in bookIds {
                invalidateBookRuntimeCaches(bookId: bookId)
                for archiveId in archiveIds {
                    IntegrationCache.shared.unmarkIntegrated(bookId: bookId, archiveId: archiveId)
                }
            }

        case let .idChanged(oldId, newId, oldArchiveId, newArchiveId):
            for archiveId in Set([oldArchiveId, newArchiveId].compactMap(\.self)) {
                DatabaseManager.shared.invalidateArchiveCache(archiveId: archiveId)
            }
            invalidateBookRuntimeCaches(bookId: oldId)
            invalidateBookRuntimeCaches(bookId: newId)
            if let oldArchiveId {
                IntegrationCache.shared.unmarkIntegrated(bookId: oldId, archiveId: oldArchiveId)
            }
            if let newArchiveId {
                IntegrationCache.shared.markIntegrated(bookId: newId, archiveId: newArchiveId)
            }

        case .libraryFolderChanged, .bundledDataCleaned:
            BookPageCache.shared.removeAll()
            BookConnection.invalidateAllCaches()
            DatabaseManager.shared.invalidateAllRuntimeCaches()
            IntegrationCache.shared.resetInMemoryCache()
        }
    }

    @MainActor
    func invalidateMainActorCaches(for _: BookLifecycleEvent) {
        SearchHitResolver.shared.clearCache()
    }
}
