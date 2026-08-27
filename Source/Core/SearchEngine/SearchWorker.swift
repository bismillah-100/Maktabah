//
//  SearchWorker.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//

import Foundation
import SQLite3

struct SearchControl {
    let pauseController: PauseController
    let stopFlag: @Sendable () -> Bool
}

struct SearchCallbacks {
    let onResult: (String, BookContent) -> Void
    let progress: (Int) -> Void
    let onRowProgress: (Int, Int) -> Void
}

struct SearchWorkerCallbacks {
    let start: (Int) -> Void
    let progress: (Int) -> Void
    let onRowProgress: (String, Int, Int) -> Void
    let onResult: (String, BookContent) -> Void
    let onTableComplete: () -> Void
    let onComplete: () -> Void
}

private struct ChunkParallelPlan {
    let matchedIDs: [Int]
    let totalCount: Int
    let connectionCount: Int
    let chunkSize: Int
}

private struct ChunkResultContext {
    let tableName: String
    let totalCount: Int
}

class SearchWorker {
    let archiveId: String
    let tables: [String]
    let pool: SQLiteConnectionPool
    let batchSize: Int

    init(archiveId: String, tables: [String], pool: SQLiteConnectionPool, batchSize: Int = 200) {
        self.archiveId = archiveId
        self.tables = tables
        self.pool = pool
        self.batchSize = batchSize
    }

    func search(
        ftsQuery: String,
        allowedTables: Set<String>?,
        callbacks: SearchWorkerCallbacks,
        control: SearchControl
    ) async {
        let tablesToProcess = allowedTables != nil
            ? tables.filter { (allowedTables?.contains($0) ?? false) }
            : tables

        callbacks.start(tablesToProcess.count)

        for tableName in tablesToProcess {
            if control.stopFlag() {
                return
            }

            await control.pauseController.waitIfPaused()

            if control.stopFlag() {
                return
            }

            let tableCallbacks = SearchCallbacks(
                onResult: callbacks.onResult,
                progress: callbacks.progress,
                onRowProgress: { current, total in
                    callbacks.onRowProgress(tableName, current, total)
                }
            )

            _ = await searchTableParallel(
                tableName: tableName,
                ftsQuery: ftsQuery,
                callbacks: tableCallbacks,
                control: control
            )

            if control.stopFlag() {
                return
            }

            callbacks.onTableComplete()
        }

        callbacks.onComplete()
    }

    private func fetchMatchedIDs(tableName: String, ftsQuery: String) async -> [Int] {
        do {
            return try await pool.read(at: 0) { conn in
                let idSQL = """
                    SELECT rowid
                    FROM \(tableName)_fts
                    WHERE nass_clean MATCH ?
                """
                return try conn.queryInts(sql: idSQL, params: [.text(ftsQuery)])
            }
        } catch {
            return []
        }
    }

    private func searchTableParallel(
        tableName: String,
        ftsQuery: String,
        callbacks: SearchCallbacks,
        control: SearchControl
    ) async -> Int {
        let matchedIDs = await fetchMatchedIDs(tableName: tableName, ftsQuery: ftsQuery)
        let totalCount = matchedIDs.count
        guard totalCount > 0 else { return 0 }

        await MainActor.run {
            callbacks.onRowProgress(0, totalCount)
        }

        if control.stopFlag() {
            return 0
        }

        return await executeParallelChunks(
            tableName: tableName,
            matchedIDs: matchedIDs,
            totalCount: totalCount,
            callbacks: callbacks,
            control: control
        )
    }

    private func executeParallelChunks(
        tableName: String,
        matchedIDs: [Int],
        totalCount: Int,
        callbacks: SearchCallbacks,
        control: SearchControl
    ) async -> Int {
        let connectionCount = pool.connectionCount
        let chunkSize = (totalCount + connectionCount - 1) / connectionCount
        let plan = ChunkParallelPlan(
            matchedIDs: matchedIDs,
            totalCount: totalCount,
            connectionCount: connectionCount,
            chunkSize: chunkSize
        )

        return await withTaskGroup(of: (Int, [BookContent]).self) { group -> Int in
            spawnChunkWorkerTasks(
                group: &group,
                tableName: tableName,
                plan: plan,
                control: control
            )

            let context = ChunkResultContext(
                tableName: tableName,
                totalCount: totalCount
            )

            let totalResults = await processWorkerChunkResults(
                group: &group,
                context: context,
                callbacks: callbacks,
                control: control
            )

            await MainActor.run {
                callbacks.onRowProgress(totalCount, totalCount)
            }

            return totalResults
        }
    }

    private func spawnChunkWorkerTasks(
        group: inout TaskGroup<(Int, [BookContent])>,
        tableName: String,
        plan: ChunkParallelPlan,
        control: SearchControl
    ) {
        for workerIndex in 0 ..< plan.connectionCount {
            if control.stopFlag() {
                break
            }

            let startIndex = workerIndex * plan.chunkSize
            if startIndex >= plan.totalCount { continue }
            let endIndex = min(startIndex + plan.chunkSize, plan.totalCount)
            let chunkIDs = Array(plan.matchedIDs[startIndex ..< endIndex])

            group.addTask { [weak self] in
                guard let self else { return (workerIndex, []) }

                let results = await searchChunkByIDs(
                    tableName: tableName,
                    ids: chunkIDs,
                    connectionIndex: workerIndex,
                    control: control
                )

                return (workerIndex, results)
            }
        }
    }

    private func processWorkerChunkResults(
        group: inout TaskGroup<(Int, [BookContent])>,
        context: ChunkResultContext,
        callbacks: SearchCallbacks,
        control: SearchControl
    ) async -> Int {
        var totalResults = 0
        var processedRows = 0

        for await (_, results) in group {
            if control.stopFlag() {
                group.cancelAll()
                break
            }

            for (idx, content) in results.enumerated() {
                if idx % 10 == 0 {
                    await control.pauseController.waitIfPaused()

                    if control.stopFlag() {
                        group.cancelAll()
                        return totalResults
                    }
                }

                callbacks.onResult(context.tableName, content)

                totalResults += 1
                processedRows += 1

                if processedRows % 10 == 0 {
                    callbacks.onRowProgress(processedRows, context.totalCount)
                }
                callbacks.progress(totalResults)
            }
        }
        return totalResults
    }

    private func searchChunkByIDs(
        tableName: String,
        ids: [Int],
        connectionIndex: Int,
        control: SearchControl
    ) async -> [BookContent] {
        var results: [BookContent] = []
        var currentIndex = 0

        while currentIndex < ids.count {
            await control.pauseController.waitIfPaused()

            if control.stopFlag() || Task.isCancelled {
                return results
            }

            let batchEnd = min(currentIndex + batchSize, ids.count)
            let batchIDs = ids[currentIndex ..< batchEnd]
            currentIndex = batchEnd

            let placeholders = String(repeating: "?,", count: batchIDs.count).dropLast()
            let sql = """
                SELECT nass, page, id, part
                FROM \(tableName)
                WHERE id IN (\(placeholders))
            """

            let params = batchIDs.map { SQLValue.int($0) }

            let fetchedContents: [BookContent]
            do {
                fetchedContents = try await pool.read(at: connectionIndex) { conn in
                    try conn.queryContents(sql: sql, params: params)
                }
            } catch {
                return results
            }

            if control.stopFlag() || Task.isCancelled {
                return results
            }

            if fetchedContents.isEmpty { continue }

            for (idx, content) in fetchedContents.enumerated() {
                if idx % 10 == 0, control.stopFlag() || Task.isCancelled {
                    return results
                }
                results.append(content)
            }
        }

        return results
    }
}
