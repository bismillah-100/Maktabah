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
    }

    private let state = Mutex(BufferState())
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
        state.withLock { $0.flushTimer?.cancel() }
    }

    func append(_ item: SearchResultItem) {
        var toFlush: [SearchResultItem]?
        state.withLock { s in
            s.items.append(item)
            if s.items.count >= batchSize {
                s.flushTimer?.cancel()
                s.flushTimer = nil
                toFlush = s.items
                s.items.removeAll(keepingCapacity: true)
            } else if s.flushTimer == nil {
                s.flushTimer = Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(for: flushInterval)
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
        state.withLock { s in
            s.flushTimer?.cancel()
            s.flushTimer = nil
            if !s.items.isEmpty {
                toFlush = s.items
                s.items.removeAll(keepingCapacity: true)
            }
        }

        if let toFlush, !toFlush.isEmpty {
            onFlush(toFlush)
        }
    }
}
