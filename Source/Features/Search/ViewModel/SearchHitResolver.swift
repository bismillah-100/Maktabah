//
//  SearchHitResolver.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 27/09/26.
//

import Foundation

@MainActor
final class SearchHitResolver {
    static let shared = SearchHitResolver()

    private let cache = NSCache<NSString, NSAttributedString>()

    private init() {
        cache.countLimit = 1000
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    func cachedSnippet(for item: SearchResultItem) -> NSAttributedString? {
        cache.object(forKey: item.id as NSString)
    }

    func resolveSnippet(
        for item: SearchResultItem,
        keywords: [String],
        mode: SearchMode,
        nearDistance: Int,
    ) async -> NSAttributedString? {
        let key = item.id as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let payload = await Task.detached(priority: .userInitiated, operation: { () -> (snippet: String, keywords: [String])? in
            guard let content = await LibraryDataManager.shared.fetchSingleContent(
                archive: item.archive,
                table: item.tableName,
                rowId: item.bookId
            ) else {
                return nil
            }

            let bookId = Int(item.tableName.dropFirst()) ?? 0
            let book = LibraryDataManager.shared.getBook([bookId]).first
            let isMultilingual = book?.isMultiLanguage ?? false
            let isImported = book?.isImported ?? false

            let cleaned = content.nash.cleaningLineBreaks()
            let stripped = isImported ? cleaned.stripSpanTags() : cleaned
            let normalized = stripped.convertToArabicDigits(isMultilingual: isMultilingual)
            let keywordsConverted = keywords.map { $0.convertToArabicDigits(isMultilingual: isMultilingual) }

            let snippet: String
            if mode == .near {
                snippet = normalized
                    .normalizeArabic()
                    .snippetNear(keywords: keywordsConverted, nearDistance: nearDistance, contextLength: 60)
            } else {
                snippet = normalized
                    .normalizeArabic()
                    .snippetAround(keywords: keywordsConverted, contextLength: 60)
            }

            return (snippet, keywordsConverted)
        }).value else {
            return nil
        }

        let attributed: NSAttributedString
        if mode == .near {
            attributed = payload.snippet.highlightedAttributedText(keywords: payload.keywords, nearDistance: nearDistance)
        } else {
            attributed = payload.snippet.highlightedAttributedText(keywords: payload.keywords)
        }

        cache.setObject(attributed, forKey: key)
        return attributed
    }
}
