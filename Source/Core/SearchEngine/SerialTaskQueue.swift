//
//  SerialTaskQueue.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 01/07/26.
//

import Foundation

class SerialTaskQueue {
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()

    func enqueue(operation: @escaping @Sendable () async -> Void) {
        let op = AsyncBlockOperation(operation: operation)
        queue.addOperation(op)
    }

    func cancelAll() {
        queue.cancelAllOperations()
    }
}

private class AsyncBlockOperation: Operation, @unchecked Sendable {
    private let operationClosure: @Sendable () async -> Void
    private var task: Task<Void, Never>?
    private let lock = NSLock()

    init(operation: @escaping @Sendable () async -> Void) {
        self.operationClosure = operation
        super.init()
    }

    private var _executing = false
    private var _finished = false

    override var isExecuting: Bool {
        get { lock.withLock { _executing } }
        set { setKVO(\._executing, to: newValue, key: "isExecuting") }
    }

    override var isFinished: Bool {
        get { lock.withLock { _finished } }
        set { setKVO(\._finished, to: newValue, key: "isFinished") }
    }

    private func setKVO(_ keyPath: ReferenceWritableKeyPath<AsyncBlockOperation, Bool>, to value: Bool, key: String) {
        willChangeValue(forKey: key)
        lock.withLock { self[keyPath: keyPath] = value }
        didChangeValue(forKey: key)
    }

    override var isAsynchronous: Bool { true }

    override func start() {
        guard !isCancelled else {
            isFinished = true
            return
        }
        isExecuting = true
        task = Task {
            await operationClosure()
            isExecuting = false
            isFinished = true
        }
    }

    override func cancel() {
        super.cancel()
        task?.cancel()
    }
}
