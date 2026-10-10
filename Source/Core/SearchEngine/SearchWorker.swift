//
//  SearchWorker.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//

import Foundation
import SQLite3

struct SearchControl: Sendable {
    let pauseController: PauseController
    let stopFlag: @Sendable () -> Bool
}

struct SearchCallbacks: Sendable {
    let onResult: @Sendable (String, SearchHit) -> Void
    let progress: @Sendable (Int) -> Void
    let onRowProgress: @Sendable (Int, Int) -> Void
}

struct SearchWorkerCallbacks: Sendable {
    let start: @Sendable (Int) -> Void
    let progress: @Sendable (Int) -> Void
    let onRowProgress: @Sendable (String, Int, Int) -> Void
    let onResult: @Sendable (String, SearchHit) -> Void
    let onTableComplete: @Sendable () -> Void
    let onComplete: @Sendable () -> Void
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

final class SearchWorker: @unchecked Sendable {
    let archiveId: String
    let tables: [String]
    let pool: SQLiteConnectionPool
    let batchSize: Int
    let queryLimit: String = "\nLIMIT 10000;"
    private var detectedSchemaCache: String?? = nil
    private let schemaLock = NSLock()

    init(archiveId: String, tables: [String], pool: SQLiteConnectionPool, batchSize: Int = 200) {
        self.archiveId = archiveId
        self.tables = tables
        self.pool = pool
        self.batchSize = batchSize
    }

    func interrupt() async {
        await pool.interruptAll()
    }

    func search(
        ftsQuery: String,
        allowedTables: Set<String>?,
        callbacks: SearchWorkerCallbacks,
        control: SearchControl
    ) async {
        if let schema = await checkUnifiedFtsSchema() {
            await searchUnifiedArchive(
                schema: schema,
                ftsQuery: ftsQuery,
                allowedTables: allowedTables,
                callbacks: callbacks,
                control: control
            )
            return
        }

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

    private func checkUnifiedFtsSchema() async -> String? {
        do {
            return try await pool.read(at: 0) { conn in
                let checkCountSql = { (schemaName: String) in
                    """
                    SELECT count(*) FROM \(schemaName).sqlite_master 
                    WHERE type='table' AND name IN ('archive_fts', 'archive_index');
                    """
                }

                let checkFtsDb = checkCountSql("fts_db")
                if let rows = try? conn.queryInts(sql: checkFtsDb, params: []), !rows.isEmpty {
                    return "fts_db"
                }
                let checkMain = checkCountSql("main")
                if let rows = try? conn.queryInts(sql: checkMain, params: []), !rows.isEmpty {
                    return "main"
                }
                return nil
            }
        } catch {
            return nil
        }
    }

    private func searchUnifiedArchive(
        schema: String,
        ftsQuery: String,
        allowedTables: Set<String>?,
        callbacks: SearchWorkerCallbacks,
        control: SearchControl
    ) async {
        if control.stopFlag() { return }

        if let allowed = allowedTables, Set(tables).intersection(allowed).isEmpty {
            callbacks.onTableComplete()
            callbacks.onComplete()
            return
        }

        callbacks.start(1)

        let localTables = allowedTables.map { Set(tables).intersection($0) }
        let bookIds: [Int] = (localTables ?? []).compactMap { tbl in
            tbl.hasPrefix("b") ? Int(tbl.dropFirst()) : Int(tbl)
        }

        let (sql, params) = buildUnifiedQuery(schema: schema, ftsQuery: ftsQuery, bookIds: bookIds)

        let hits: [SearchHit]
        do {
            hits = try await pool.read(at: 0) { conn in
                try conn.queryUnifiedHits(archive: self.archiveId, sql: sql, params: params)
            }
        } catch {
            callbacks.onTableComplete()
            callbacks.onComplete()
            return
        }

        await dispatchUnifiedHits(hits: hits, callbacks: callbacks, control: control)
        callbacks.onTableComplete()
        callbacks.onComplete()
    }

    private func baseSearchSQL(schema: String, withRowIdBounds: Bool = false) -> String {
        """
        SELECT i.book_id, i.page, i.id, i.part
        FROM \(schema).archive_fts f
        JOIN \(schema).archive_index i ON f.rowid = i.rowid
        WHERE f.archive_fts MATCH ?\(withRowIdBounds ? "\n  AND f.rowid BETWEEN ? AND ?" : "")
        """
    }

    private func buildUnifiedQuery(
        schema: String,
        ftsQuery: String,
        bookIds: [Int]
    ) -> (sql: String, params: [SQLValue]) {
        if bookIds.count == 1, let targetBookId = bookIds.first {
            return buildSingleBookQuery(schema: schema, ftsQuery: ftsQuery, bookId: targetBookId)
        }
        if (2 ... 5).contains(bookIds.count) {
            return buildUnionBookQuery(schema: schema, ftsQuery: ftsQuery, bookIds: bookIds)
        }
        return buildBroadBookQuery(schema: schema, ftsQuery: ftsQuery, bookIds: bookIds)
    }

    private func buildSingleBookQuery(
        schema: String,
        ftsQuery: String,
        bookId: Int
    ) -> (sql: String, params: [SQLValue]) {
        let (minRowId, maxRowId) = rowIdBounds(from: bookId)
        let sql = baseSearchSQL(schema: schema, withRowIdBounds: true) + queryLimit
        let params: [SQLValue] = [
            .text(ftsQuery),
            .int(minRowId),
            .int(maxRowId)
        ]
        return (sql, params)
    }

    private func buildUnionBookQuery(
        schema: String,
        ftsQuery: String,
        bookIds: [Int]
    ) -> (sql: String, params: [SQLValue]) {
        let singleQuery = baseSearchSQL(schema: schema, withRowIdBounds: true)
        let sql = Array(repeating: singleQuery, count: bookIds.count)
            .joined(separator: "\nUNION ALL\n") + queryLimit

        var params: [SQLValue] = []
        for bId in bookIds {
            let (minRowId, maxRowId) = rowIdBounds(from: bId)
            params.append(contentsOf: [
                .text(ftsQuery),
                .int(minRowId),
                .int(maxRowId)
            ])
        }
        return (sql, params)
    }

    private func buildBroadBookQuery(
        schema: String,
        ftsQuery: String,
        bookIds: [Int]
    ) -> (sql: String, params: [SQLValue]) {
        var sql = baseSearchSQL(schema: schema)
        var params: [SQLValue] = [.text(ftsQuery)]

        if !bookIds.isEmpty {
            if let minBook = bookIds.min(), let maxBook = bookIds.max(), (maxBook - minBook) < 350 {
                let (minRowId, maxRowId) = rowIdBounds(from: minBook, to: maxBook)
                sql += "\n  AND f.rowid BETWEEN ? AND ?"
                params.append(contentsOf: [.int(minRowId), .int(maxRowId)])
            }

            let placeholders = String(repeating: "?,", count: bookIds.count).dropLast()
            sql += "\n  AND i.book_id IN (\(placeholders))"
            params.append(contentsOf: bookIds.map { .int($0) })
        }

        sql += queryLimit
        return (sql, params)
    }

    private func dispatchUnifiedHits(
        hits: [SearchHit],
        callbacks: SearchWorkerCallbacks,
        control: SearchControl
    ) async {
        let total = hits.count
        callbacks.onRowProgress("archive_\(archiveId)", 0, total)

        for (idx, hit) in hits.enumerated() {
            if idx % 10 == 0 {
                await control.pauseController.waitIfPaused()
                if control.stopFlag() { return }
                callbacks.onRowProgress(hit.tableName, idx + 1, total)
            }

            callbacks.onResult(hit.tableName, hit)
            callbacks.progress(idx + 1)
        }

        callbacks.onRowProgress("archive_\(archiveId)", total, total)
    }

    private func fetchMatchedIDs(tableName: String, ftsQuery: String) async -> [Int] {
        do {
            return try await pool.read(at: 0) { conn in
                let idSQL = """
                    SELECT rowid
                    FROM \(tableName)_fts
                    WHERE nass_clean MATCH ?
                    LIMIT 1000;
                """
                return try conn.queryInts(sql: idSQL, params: [.text(ftsQuery)])
            }
        } catch {
            return []
        }
    }

    private func rowIdBounds(from minBookId: Int, to maxBookId: Int? = nil) -> (min: Int, max: Int) {
        let endBookId = maxBookId ?? minBookId
        let minRow = Int64(minBookId) << 32
        let maxRow = (Int64(endBookId) << 32) | 0xFFFF_FFFF
        return (Int(minRow), Int(maxRow))
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
        let connectionCount = await pool.connectionCount
        let chunkSize = (totalCount + connectionCount - 1) / connectionCount
        let plan = ChunkParallelPlan(
            matchedIDs: matchedIDs,
            totalCount: totalCount,
            connectionCount: connectionCount,
            chunkSize: chunkSize
        )

        return await withTaskGroup(of: (Int, [SearchHit]).self) { group -> Int in
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
        group: inout TaskGroup<(Int, [SearchHit])>,
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
        group: inout TaskGroup<(Int, [SearchHit])>,
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

            for (idx, hit) in results.enumerated() {
                if idx % 10 == 0 {
                    await control.pauseController.waitIfPaused()

                    if control.stopFlag() {
                        group.cancelAll()
                        return totalResults
                    }
                }

                callbacks.onResult(context.tableName, hit)

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
    ) async -> [SearchHit] {
        var results: [SearchHit] = []
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
                SELECT page, id, part
                FROM \(tableName)
                WHERE id IN (\(placeholders))
            """

            let params = batchIDs.map { SQLValue.int($0) }

            let fetchedHits: [SearchHit]
            do {
                fetchedHits = try await pool.read(at: connectionIndex) { conn in
                    try conn.querySearchHits(archive: self.archiveId, tableName: tableName, sql: sql, params: params)
                }
            } catch {
                return results
            }

            if control.stopFlag() || Task.isCancelled {
                return results
            }

            if fetchedHits.isEmpty { continue }

            for (idx, hit) in fetchedHits.enumerated() {
                if idx % 10 == 0, control.stopFlag() || Task.isCancelled {
                    return results
                }
                results.append(hit)
            }
        }

        return results
    }
}
