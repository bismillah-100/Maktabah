//
//  SingleFlight.swift
//  Maktabah
//

import Foundation

actor SingleFlight<Key: Hashable, Value> {
    private var runningTasks: [Key: Task<Value, Error>] = [:]

    func run(
        key: Key,
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        if let existingTask = runningTasks[key] {
            return try await existingTask.value
        }

        let task = Task {
            try await operation()
        }
        runningTasks[key] = task

        do {
            let result = try await task.value
            runningTasks.removeValue(forKey: key)
            return result
        } catch {
            runningTasks.removeValue(forKey: key)
            throw error
        }
    }

    func cancelAll() {
        for (_, task) in runningTasks {
            task.cancel()
        }
        runningTasks.removeAll()
    }
}
