//
//  SearchResultBuffer.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 27/09/26.
//

import Foundation

final class SearchResultBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SearchResultItem] = []
    private var flushTimer: Task<Void, Never>?
    private let batchSize: Int
    private let flushInterval: Duration
    private let onFlush: @Sendable ([SearchResultItem]) -> Void

    init(
        batchSize: Int = 50,
        flushInterval: Duration = .milliseconds(100),
        onFlush: @escaping @Sendable ([SearchResultItem]) -> Void
    ) {
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.onFlush = onFlush
    }

    deinit {
        lock.lock()
        flushTimer?.cancel()
        lock.unlock()
    }

    func append(_ item: SearchResultItem) {
        var toFlush: [SearchResultItem]?
        lock.lock()
        items.append(item)
        if items.count >= batchSize {
            flushTimer?.cancel()
            flushTimer = nil
            toFlush = items
            items.removeAll(keepingCapacity: true)
        } else if flushTimer == nil {
            flushTimer = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: flushInterval)
                flush()
            }
        }
        lock.unlock()

        if let toFlush, !toFlush.isEmpty {
            onFlush(toFlush)
        }
    }

    func flush() {
        var toFlush: [SearchResultItem]?
        lock.lock()
        flushTimer?.cancel()
        flushTimer = nil
        if !items.isEmpty {
            toFlush = items
            items.removeAll(keepingCapacity: true)
        }
        lock.unlock()

        if let toFlush, !toFlush.isEmpty {
            onFlush(toFlush)
        }
    }
}
