//
//  BookPageCache.swift
//  maktab
//
//  Created by MacBook on 11/12/25.
//

import Foundation

final class CachedBookContent: NSObject {
    let content: BookContent
    init(_ content: BookContent) {
        self.content = content
    }
}

final class BookPageCache {
    static let shared = BookPageCache()

    // Key: "bookId-contentId"
    private let cache = NSCache<NSString, CachedBookContent>()
    private let lock = NSLock()

    init() {
        cache.countLimit = 2000     // total item cache
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB memory (opsional)
    }

    private func key(bookId: Int, contentId: Int) -> NSString {
        return "\(bookId)-\(contentId)" as NSString
    }

    func get(bookId: Int, contentId: Int) -> BookContent? {
        let k = key(bookId: bookId, contentId: contentId)
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache.object(forKey: k) {
            print("Cache HIT: \(k)")
            return cached.content
        } else {
            print("Cache MISS: \(k)")
            return nil
        }
    }

    func set(bookId: Int, content: BookContent) {
        let k = key(bookId: bookId, contentId: content.id)
        lock.lock()
        defer { lock.unlock() }

        print("Cache SET: \(k)")
        cache.setObject(CachedBookContent(content), forKey: k)
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
