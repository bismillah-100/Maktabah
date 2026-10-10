//
//  SearchResultBuffer.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 27/09/26.
//

import Foundation
import Synchronization

final class SearchResultBuffer: Sendable {
    private struct BufferState: Sendable {
        var items: [SearchResultItem] = []
        var flushTimer: Task<Void, Never>?
        var lastFlushTime: ContinuousClock.Instant = .now
    }

    private let state = Mutex(BufferState())
    private let batchSize: Int
    private let flushInterval: Duration
    private let minFlushInterval: Duration
    private let onFlush: @Sendable ([SearchResultItem]) -> Void

    init(
        batchSize: Int = 50,
        flushInterval: Duration = .milliseconds(100),
        minFlushInterval: Duration = .milliseconds(25),
        onFlush: @escaping @Sendable ([SearchResultItem]) -> Void
    ) {
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.minFlushInterval = minFlushInterval
        self.onFlush = onFlush
    }

    deinit {
        state.withLock { $0.flushTimer?.cancel() }
    }

    func append(_ item: SearchResultItem) {
        var toFlush: [SearchResultItem]?
        let now = ContinuousClock.now

        state.withLock { s in
            s.items.append(item)
            let elapsed = now - s.lastFlushTime

            if s.items.count >= batchSize && elapsed >= minFlushInterval {
                s.flushTimer?.cancel()
                s.flushTimer = nil
                s.lastFlushTime = now
                toFlush = s.items
                s.items.removeAll(keepingCapacity: true)
            } else if s.flushTimer == nil {
                let delay = elapsed < minFlushInterval ? (minFlushInterval - elapsed) : flushInterval
                s.flushTimer = Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(for: delay)
                    flush()
                }
            }
        }

        if let toFlush, !toFlush.isEmpty {
            onFlush(toFlush)
        }
    }

    func flush() {
        var toFlush: [SearchResultItem]?
        let now = ContinuousClock.now

        state.withLock { s in
            s.flushTimer?.cancel()
            s.flushTimer = nil
            if !s.items.isEmpty {
                s.lastFlushTime = now
                toFlush = s.items
                s.items.removeAll(keepingCapacity: true)
            }
        }

        if let toFlush, !toFlush.isEmpty {
            onFlush(toFlush)
        }
    }
}
