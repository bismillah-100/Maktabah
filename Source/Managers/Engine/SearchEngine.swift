//
//  SearchEngine.swift
//  maktab
//
//  Modified: Parallel search within table using 4 connections
//

import Foundation
import SQLite3

struct SearchQueryOptions {
    var query: String = ""
    var keywords: [String] = []
    var allowedTables: Set<String>? = nil
    var mode: SearchMode
    var nearDistance: Int = 10
}

struct SearchEngineCallbacks {
    var onInitialize: (Int) -> Void
    var onTableComplete: (String, Int) -> Void
    var onRowProgress: (String, String, Int, Int) -> Void
    var onResult: (String, String, BookContent) -> Void
    var onComplete: () -> Void
}

final class SearchEngine {
    private(set) var workers: [SearchWorker] = []
    private let pauseController = PauseController()
    private var searchTask: Task<Void, Never>?
    private var isStopped = false
    private let stopLock = NSLock()
    private let workersLock = NSLock()

    init() {}

    func registerDB(archiveId: String, tables: [String], connections: [DBConnectionType], batchSize: Int = 200) {
        let pool = SQLiteConnectionPool(conns: connections)
        let worker = SearchWorker(archiveId: archiveId, tables: tables, pool: pool, batchSize: batchSize)
        workersLock.lock()
        workers.append(worker)
        workersLock.unlock()
    }

    func startSearch(
        options: SearchQueryOptions,
        callbacks: SearchEngineCallbacks
    ) {
        searchTask?.cancel()
        searchTask = nil
        isStopped = false

        workersLock.lock()
        let currentWorkers = workers
        workersLock.unlock()

        // Kirim total workers ke UI
        Task { @MainActor in
            callbacks.onInitialize(currentWorkers.count)
        }

        let inputQuery = options.query.isEmpty ? options.keywords.joined(separator: " ") : options.query
        let ftsQuery = FtsQueryParser.buildFtsQuery(query: inputQuery, mode: options.mode, nearDistance: options.nearDistance)

        if ftsQuery.isEmpty {
            Task { @MainActor in callbacks.onComplete() }
            return
        }

        searchTask = Task.detached(priority: .userInitiated) { [weak self, ftsQuery, currentWorkers] in
            guard let self else { return }
            for worker in currentWorkers {
                if isStopped { break }

                var completedTables = 0

                let workerCallbacks = SearchWorkerCallbacks(
                    start: { _ in },
                    progress: { _ in },
                    onRowProgress: { tableName, current, total in
                        callbacks.onRowProgress(worker.archiveId, tableName, current, total)
                    },
                    onResult: { tableName, content in
                        callbacks.onResult(tableName, worker.archiveId, content)
                    },
                    onTableComplete: {
                        completedTables += 1
                        callbacks.onTableComplete(worker.archiveId, completedTables)
                    },
                    onComplete: {}
                )

                let control = SearchControl(
                    pauseController: pauseController,
                    stopFlag: { [weak self] in
                        return self?.isStopped ?? false
                    }
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

    func checkAndResumeIfNeeded(completion: @escaping (Bool) -> Void) {
        Task {
            let isPaused = await currentlyPaused()

            if isPaused {
                print("Pencarian saat ini dijeda. Melanjutkan (Resuming)...")
                self.resume()
                // Kasus Resume: Kita sudah melanjutkan yang lama. Jangan panggil startSearch.
                completion(true) // <-- Mengembalikan TRUE
            } else {
                print("Pencarian saat ini tidak dijeda. Memerlukan Start Baru.")
                // Kasus Start Baru: Tidak ada yang dijeda, jadi kita perlu mulai baru.
                completion(false) // <-- Mengembalikan FALSE
            }
        }
    }

    func pause() {
        Task {
            await pauseController.pause()
        }
    }

    func resume() {
        Task {
            await pauseController.resume()
        }
    }

    func stop() {
        stopLock.lock()
        isStopped = true
        stopLock.unlock()
        Task {
            await pauseController.stopAndResumeAll()
        }
        searchTask?.cancel()
        searchTask = nil
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
        workersLock.lock()
        workers.removeAll()
        workersLock.unlock()
    }
}

