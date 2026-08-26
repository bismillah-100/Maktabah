//
//  CloudKitUploadDebouncer.swift
//  Maktabah
//

import Foundation

final class CloudKitUploadDebouncer<Item> {
    private var buffer: [String: Item] = [:]
    private var debounceTask: DispatchWorkItem?
    private var pendingCompletions: [(Result<Void, Error>) -> Void] = []
    private let debounceInterval: TimeInterval
    private let queue: DispatchQueue

    init(queue: DispatchQueue, debounceInterval: TimeInterval = 2.0) {
        self.queue = queue
        self.debounceInterval = debounceInterval
    }

    func add(
        items: [(id: String, item: Item)],
        completion: ((Result<Void, Error>) -> Void)?,
        debounce: Bool,
        onFlush: @escaping ([Item], [(Result<Void, Error>) -> Void]) -> Void
    ) {
        for (id, item) in items {
            buffer[id] = item
        }
        if let completion {
            pendingCompletions.append(completion)
        }
        debounceTask?.cancel()

        if debounce {
            let workItem = DispatchWorkItem(flags: .barrier) { [weak self] in
                self?.flush(onFlush: onFlush)
            }
            debounceTask = workItem
            queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
        } else {
            flush(onFlush: onFlush)
        }
    }

    private func flush(onFlush: ([Item], [(Result<Void, Error>) -> Void]) -> Void) {
        let itemsToUpload = Array(buffer.values)
        buffer.removeAll()
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        onFlush(itemsToUpload, completions)
    }
}
