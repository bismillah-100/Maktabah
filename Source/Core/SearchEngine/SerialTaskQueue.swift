//
//  SerialTaskQueue.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 01/07/26.
//

import Foundation
import Synchronization

final class SerialTaskQueue: Sendable {
    private let tailState = Mutex<Task<Void, Never>?>(nil)

    @discardableResult
    func enqueue(operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        tailState.withLock { tail in
            let previous = tail

            let newTask = Task {
                await withTaskCancellationHandler {
                    _ = await previous?.value
                    guard !Task.isCancelled else { return }
                    await operation()
                } onCancel: {
                    previous?.cancel()
                }
            }

            tail = newTask
            return newTask
        }
    }

    func cancelAll() {
        tailState.withLock { tail in
            tail?.cancel()
            tail = nil
        }
    }
}
