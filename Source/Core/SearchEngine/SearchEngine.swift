//
//  SearchEngine.swift
//  maktab
//
//  Modified: Parallel search within table using 4 connections
//

import Foundation
import OSLog
import SQLite3
import Synchronization

struct SearchQueryOptions: Sendable {
    var query: String = ""
    var keywords: [String] = []
    var allowedTables: Set<String>? = nil
    var mode: SearchMode
    var nearDistance: Int = 10
}

struct SearchEngineCallbacks: Sendable {
    var onInitialize: @Sendable (Int) -> Void
    var onTableComplete: @Sendable (String, Int) -> Void
    var onRowProgress: @Sendable (String, String, Int, Int) -> Void
    var onResult: @Sendable (String, String, SearchHit) -> Void
    var onComplete: @Sendable () -> Void
}

actor SearchEngine {
    private(set) var workers: [SearchWorker] = []
    private let pauseController = PauseController()
    private var searchTask: Task<Void, Never>?
    private var isStopped = false

    init() {}

    func registerDB(archiveId: String, tables: [String], connections: [DBConnectionType], batchSize: Int = 200) {
        let pool = SQLiteConnectionPool(conns: connections)
        let worker = SearchWorker(archiveId: archiveId, tables: tables, pool: pool, batchSize: batchSize)
        workers.append(worker)
    }

    func startSearch(
        options: SearchQueryOptions,
        callbacks: SearchEngineCallbacks
    ) async {
        searchTask?.cancel()
        searchTask = nil
        isStopped = false

        let currentWorkers = workers
        for worker in currentWorkers {
            await worker.interrupt()
        }

        // Kirim total workers ke UI
        await MainActor.run {
            callbacks.onInitialize(currentWorkers.count)
        }

        let inputQuery = options.query.isEmpty ? options.keywords.joined(separator: " ") : options.query
        let ftsQuery = FtsQueryParser.buildFtsQuery(query: inputQuery, mode: options.mode, nearDistance: options.nearDistance)

        if ftsQuery.isEmpty {
            Task { @MainActor in callbacks.onComplete() }
            return
        }

        searchTask = Task.detached(priority: .userInitiated) { [ftsQuery, currentWorkers, pauseController] in
            for worker in currentWorkers {
                if Task.isCancelled { break }
                let counter = SafeCounter()

                let workerCallbacks = SearchWorkerCallbacks(
                    start: { _ in },
                    progress: { _ in },
                    onRowProgress: { tableName, current, total in
                        callbacks.onRowProgress(worker.archiveId, tableName, current, total)
                    },
                    onResult: { tableName, hit in
                        callbacks.onResult(tableName, worker.archiveId, hit)
                    },
                    onTableComplete: {
                        let currentCount = counter.increment()
                        callbacks.onTableComplete(worker.archiveId, currentCount)
                    },
                    onComplete: {}
                )

                let control = SearchControl(
                    pauseController: pauseController,
                    stopFlag: { Task.isCancelled }
                )

                await worker.search(
                    ftsQuery: ftsQuery,
                    allowedTables: options.allowedTables,
                    callbacks: workerCallbacks,
                    control: control
                )
            }
            await MainActor.run { callbacks.onComplete() }
        }
    }

    func checkAndResumeIfNeeded() async -> Bool {
        let isPaused = await currentlyPaused()

        if isPaused {
            Logger.search.debug("Pencarian saat ini dijeda. Melanjutkan (Resuming)...")
            await resume()
            return true
        } else {
            Logger.search.debug("Pencarian saat ini tidak dijeda. Memerlukan Start Baru.")
            return false
        }
    }

    func pause() async {
        await pauseController.pause()
    }

    func resume() async {
        await pauseController.resume()
    }

    func stop() async {
        isStopped = true
        await pauseController.stopAndResumeAll()
        searchTask?.cancel()
        searchTask = nil
        for worker in workers {
            await worker.interrupt()
        }
        cleanup()
    }

    func isRunning() async -> Bool {
        let isPaused = await currentlyPaused()
        return !isPaused && searchTask != nil
    }

    func currentlyPaused() async -> Bool {
        await pauseController.currentlyPaused()
    }

    func cleanup() {
        workers.removeAll()
    }
}

