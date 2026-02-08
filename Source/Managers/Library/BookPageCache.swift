//
//  BookPageCache.swift
//  maktab
//
//  Created by MacBook on 11/12/25.
//

import Foundation

final class BookPageCache {
    static let shared = BookPageCache()

    // Key: bookId (NSNumber) -> Value: Map of pages (NSMutableDictionary)
    private let cache = NSCache<NSNumber, NSMutableDictionary>()
    private let lock = NSLock()

    private init() {
        cache.countLimit = 2000     // total item cache
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB memory (opsional)
    }

    func get(bookId: Int, contentId: Int) -> BookContent? {
        lock.lock()
        defer { lock.unlock() }

        let bookKey = bookId as NSNumber
        let pages = cache.object(forKey: bookKey)
        #if DEBUG
            print("Cache HIT: \(bookKey), \(String(describing: pages))")
        #endif
        return pages?[contentId as NSNumber] as? BookContent
    }

    func set(bookId: Int, content: BookContent) {
        lock.lock()
        defer { lock.unlock() }

        let bookKey = bookId as NSNumber
        let pages = cache.object(forKey: bookKey) ?? NSMutableDictionary()

        pages[content.id as NSNumber] = content
        cache.setObject(pages, forKey: bookKey)
    }

    func remove(bookId: Int) {
        lock.lock()
        defer { lock.unlock() }

        // Langsung hapus satu buku beserta seluruh halamannya
        cache.removeObject(forKey: bookId as NSNumber)
        #if DEBUG
            print("Cache REMOVED all content for bookId: \(bookId)")
        #endif
    }

    // Optional: helper to remove or clear cache safely
    /*
    func remove(bookId: Int, contentId: Int) {
        let k = key(bookId: bookId, contentId: contentId)
        lock.lock()
        defer { lock.unlock() }
        cache.removeObject(forKey: k)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
    }
     */
}
