//
//  CloudKitUploadDebouncer.swift
//  Maktabah
//

import Foundation

/// Actor-isolated debouncer to manage upload batching, buffer state, and pending callbacks.
actor CloudKitUploadDebouncer<Item: Sendable> {
    private var buffer: [String: Item] = [:]
    private var debounceTask: Task<Void, Never>?
    private var pendingCompletions: [@Sendable (Result<Void, Error>) -> Void] = []
    private let debounceInterval: Duration

    init(debounceInterval: Duration = .seconds(2)) {
        self.debounceInterval = debounceInterval
    }

    /// Buffers items and executes flush when the debounce delay expires, or immediately if debounce is false.
    func add(
        items: [(id: String, item: Item)],
        completion: (@Sendable (Result<Void, Error>) -> Void)?,
        debounce: Bool,
        onFlush: @Sendable @escaping ([Item], [@Sendable (Result<Void, Error>) -> Void]) -> Void
    ) {
        for (id, item) in items {
            buffer[id] = item
        }
        if let completion {
            pendingCompletions.append(completion)
        }

        debounceTask?.cancel()

        if debounce {
            let delay = debounceInterval
            debounceTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.flush(onFlush: onFlush)
            }
        } else {
            flush(onFlush: onFlush)
        }
    }

    /// Drains current buffer and forwards items along with accumulated completions to the caller.
    private func flush(
        onFlush: @Sendable ([Item], [@Sendable (Result<Void, Error>) -> Void]) -> Void
    ) {
        let itemsToUpload = Array(buffer.values)
        buffer.removeAll()
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        onFlush(itemsToUpload, completions)
    }
}
