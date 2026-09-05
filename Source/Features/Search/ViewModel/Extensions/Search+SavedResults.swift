//
//  Search+SavedResults.swift
//  Maktabah
//

import Foundation

extension SearchViewModel {
    // MARK: - Bookmarked Search Results

    /// Load saved results dari database, emit via `searchDidReceiveResult`.
    @discardableResult
    func loadSavedResults(
        _ savedResults: [SavedResultsItem],
        onProgress: (@MainActor (Double) -> Void)? = nil,
        onInsert: (@MainActor (Int, Int) -> Void)? = nil, // (prevCount, newCount)
        onFinish: (@MainActor () -> Void)? = nil
    ) -> Task<Void, Never> {
        clearResults()
        if let first = savedResults.first {
            query = first.query
            if let mode = SearchMode(rawValue: first.searchMode) {
                searchMode = mode
            }
            nearDistance = first.nearDistance
        }
        results = []
        totalTables = 0
        completedTables = 0
        completedRowsInTable = 0
        totalRowsInTable = 0

        let task = Task.detached { [weak self] in
            guard let self else { return }

            await onProgress?(Double(savedResults.count))

            let grouped = Dictionary(grouping: savedResults, by: \.archive)
            var buffer = ResultBuffer()

            for (archiveId, items) in grouped {
                guard searchWork?.isCancelled == false,
                      let arc = Int(archiveId)
                else { return }

                do {
                    try bkConn.connect(archive: arc)
                } catch {
                    continue
                }

                await processArchiveSavedItems(items: items, buffer: &buffer, onInsert: onInsert)
            }

            if !buffer.isEmpty {
                await flushBuffer(&buffer, onInsert: onInsert)
            }
            await onFinish?()
        }

        searchWork = task
        return task
    }

    func processArchiveSavedItems(
        items: [SavedResultsItem],
        buffer: inout ResultBuffer,
        onInsert: (@MainActor (Int, Int) -> Void)?
    ) async {
        for item in items {
            guard searchWork?.isCancelled == false else { return }

            while isPaused {
                guard searchWork?.isCancelled == false else { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            if let result = await processSavedItem(item) {
                buffer.add(result)
                if buffer.isFull {
                    await flushBuffer(&buffer, onInsert: onInsert)
                }
            }
        }
    }

    func processSavedItem(_ item: SavedResultsItem) async -> SearchResultItem? {
        guard let bookContent = bkConn.getContent(bkid: item.tableName, contentId: item.bookId)
        else { return nil }

        let bookId = Int(item.tableName.dropFirst()) ?? 0
        let book = ldm.booksById[bookId]
        let isMultilingual = book?.isMultiLanguage ?? false

        let normalized = bookContent.nash
            .convertToArabicDigits(isMultilingual: isMultilingual)
            .normalizeArabic()

        let mode = SearchMode(rawValue: item.searchMode) ?? .phrase

        let keywords = FtsQueryParser.extractKeywords(query: item.query, mode: mode)
            .map { $0.convertToArabicDigits(isMultilingual: isMultilingual) }

        let (_, attributed) = makeSnippetAndAttributedText(
            normalized: normalized,
            keywords: keywords,
            mode: mode,
            nearDistance: item.nearDistance
        )

        return SearchResultItem(
            archive: item.archive,
            tableName: item.tableName,
            bookId: item.bookId,
            bookTitle: item.bookTitle,
            page: bookContent.page,
            part: bookContent.part,
            attributedText: attributed
        )
    }

    func makeSnippetAndAttributedText(
        normalized: String,
        keywords: [String],
        mode: SearchMode,
        nearDistance: Int
    ) -> (String, NSAttributedString) {
        if mode == .near {
            let snippet = normalized.snippetNear(keywords: keywords, nearDistance: nearDistance, contextLength: 60)
            let attributed = snippet.highlightedAttributedText(keywords: keywords, nearDistance: nearDistance)
            return (snippet, attributed)
        } else {
            let snippet = normalized.snippetAround(keywords: keywords, contextLength: 60)
            let attributed = snippet.highlightedAttributedText(keywords: keywords)
            return (snippet, attributed)
        }
    }

    func flushBuffer(
        _ buffer: inout ResultBuffer,
        onInsert: (@MainActor (Int, Int) -> Void)?
    ) async {
        let items = buffer.flush()
        await MainActor.run { [weak self] in
            guard let self,
                  searchWork?.isCancelled == false
            else { return }
            let prev = results.count
            results.append(contentsOf: items)
            completedTables = prev + items.count
            onInsert?(prev, results.count)
        }
    }

    func commitBuffer(
        _ buffer: inout ResultBuffer,
        onItemAppended: @escaping (SearchResultItem, IndexSet) -> Void
    ) async {
        let items = buffer.flush()

        await MainActor.run { [weak self, items] in
            guard let self else { return }

            // Loop item satu per satu agar closure bisa dipanggil di setiap row
            for item in items {
                let currentIndex = results.count
                results.append(item)

                // Panggil closure bawaan
                onItemAppended(item, IndexSet(integer: currentIndex))
            }
        }
    }
}

// MARK: - Result Buffer Helper

struct ResultBuffer {
    private var items: [SearchResultItem] = []
    private let batchSize = 10

    var isEmpty: Bool {
        items.isEmpty
    }

    var isFull: Bool {
        items.count >= batchSize
    }

    mutating func add(_ item: SearchResultItem) {
        items.append(item)
    }

    mutating func flush() -> [SearchResultItem] {
        let flushed = items
        items.removeAll(keepingCapacity: true)
        return flushed
    }
}
