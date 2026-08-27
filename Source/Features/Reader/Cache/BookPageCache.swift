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
    private let processedCache = NSCache<NSNumber, NSMutableDictionary>()
    private let lock = NSLock()

    private init() {
        cache.countLimit = 2000     // total item cache
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB memory (opsional)

        processedCache.countLimit = 2000
    }

    private func processedSubKey(
        contentId: Int,
        key: CleanedTextKey
    ) -> NSString {
        "\(contentId)_\(key.showHarakat)_\(key.isMultiLanguage)_\(key.isImported)" as NSString
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

    func getProcessed(bookId: Int, contentId: Int, key: CleanedTextKey) -> ProcessedArabicContent? {
        lock.lock()
        defer { lock.unlock() }

        let bookKey = bookId as NSNumber
        let pages = processedCache.object(forKey: bookKey)
        let subKey = processedSubKey(contentId: contentId, key: key)
        return pages?[subKey] as? ProcessedArabicContent
    }

    func setProcessed(bookId: Int, contentId: Int, key: CleanedTextKey, content: ProcessedArabicContent) {
        lock.lock()
        defer { lock.unlock() }

        let bookKey = bookId as NSNumber
        let pages = processedCache.object(forKey: bookKey) ?? NSMutableDictionary()
        let subKey = processedSubKey(contentId: contentId, key: key)

        pages[subKey] = content
        processedCache.setObject(pages, forKey: bookKey)
    }

    func remove(bookId: Int) {
        lock.lock()
        defer { lock.unlock() }

        // Langsung hapus satu buku beserta seluruh halamannya
        cache.removeObject(forKey: bookId as NSNumber)
        processedCache.removeObject(forKey: bookId as NSNumber)
        #if DEBUG
            print("Cache REMOVED all content for bookId: \(bookId)")
        #endif
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
        processedCache.removeAllObjects()
    }
}
