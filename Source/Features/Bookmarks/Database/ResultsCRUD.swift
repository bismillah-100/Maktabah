//
//  ResultsCRUD.swift
//  Maktabah
//
//  Created by MacBook on 05/12/25.
//

import Foundation
import SQLite3

extension ResultsHandler {
    func insertResult(
        archive: Int,
        bkId: Int,
        contentId: String,
        options: ResultSaveOptions
    ) throws {
        guard let db else { return }
        let cId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)

        let fCkId = try options.folderId.flatMap { try findFolderCkId(id: $0) }
        let params: [Any] = [
            options.folderId ?? NSNull(),
            options.name,
            options.query,
            archive,
            bkId,
            contentId,
            cId,
            now,
            fCkId ?? NSNull(),
            options.searchMode,
            options.nearDistance,
        ]

        var rowId: Int64 = -1
        try transaction {
            try exec(insertResultSQL, parameters: params)
            rowId = db.lastInsertRowId()
            try self.addPendingSync(ckRecordId: cId, operation: "upload")
        }

        if rowId != -1, let reloaded = try reloadSyncResult(id: rowId) {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: [reloaded], trackPending: false)
        }
    }

    func insertResults(
        _ groupedResults: [String: GroupedResult],
        options: ResultSaveOptions
    ) throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let fCkId = try options.folderId.flatMap { try findFolderCkId(id: $0) }
        var reloadedResults: [SyncResult] = []

        try db.transaction {
            for (_, group) in groupedResults {
                if let reloaded = try insertSingleGroupedResult(group: group, options: options, now: now, fCkId: fCkId, db: db) {
                    reloadedResults.append(reloaded)
                }
            }
        }

        if !reloadedResults.isEmpty {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: reloadedResults, trackPending: false)
        }
    }

    private func insertSingleGroupedResult(
        group: GroupedResult,
        options: ResultSaveOptions,
        now: Int64,
        fCkId: String?,
        db: SQLiteDatabase
    ) throws -> SyncResult? {
        let cId = UUID().uuidString
        let commaSeparatedContentIds = group.contentIds.joined(separator: ",")

        let params: [Any] = [
            options.folderId ?? NSNull(),
            options.name,
            options.query,
            group.archive,
            group.bkId,
            commaSeparatedContentIds,
            cId,
            now,
            fCkId ?? NSNull(),
            options.searchMode,
            options.nearDistance,
        ]

        try exec(insertResultSQL, parameters: params)
        let rowId = db.lastInsertRowId()
        try addPendingSync(ckRecordId: cId, operation: "upload")

        return rowId != -1 ? try reloadSyncResult(id: rowId) : nil
    }

    private struct SavedResultsGroup {
        let id: Int64
        let parentId: Int64?
        let lastModified: Int64?
        var items: [SavedResultsItem]
    }

    private struct RawResultRow {
        let id: Int64
        let parentId: Int64?
        let name: String
        let query: String
        let archive: Int
        let bkId: Int
        let contentId: String
        let lastModified: Int64?
        let searchMode: Int
        let nearDistance: Int
    }

    func fetchResults(forFolder folderId: Int64?) -> [ResultNode] {
        guard let db else { return [] }

        let (sql, params) = buildFetchResultsQuery(forFolder: folderId)
        var groupedResults: [String: SavedResultsGroup] = [:]

        do {
            let results = try fetchRawResultRows(db: db, sql: sql, params: params)
            groupedResults = groupRawResultRows(results)
        } catch {
            print("Failed to fetch results: \(error)")
        }

        return buildResultNodes(from: groupedResults)
    }

    private func buildFetchResultsQuery(forFolder folderId: Int64?) -> (sql: String, params: [Any]) {
        let cols = "\(colId), \(colFolderId), \(colName), \(colQuery), \(colArchive), \(colBkId), \(colContentId), \(colResCkRecordId), \(colResLastModified), \(colSearchMode), \(colNearDistance)"
        if let fid = folderId {
            return ("SELECT \(cols) FROM \(resultsTable) WHERE \(colFolderId) = ?", [fid])
        } else {
            return ("SELECT \(cols) FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colFolderCkRecordId) IS NULL", [])
        }
    }

    private func fetchRawResultRows(db: SQLiteDatabase, sql: String, params: [Any]) throws -> [RawResultRow] {
        try db.fetch(query: sql, parameters: params) { row -> RawResultRow in
            RawResultRow(
                id: row.int64(at: 0),
                parentId: !row.isNull(at: 1) ? row.int64(at: 1) : nil,
                name: row.string(at: 2) ?? "",
                query: row.string(at: 3) ?? "",
                archive: row.int(at: 4),
                bkId: row.int(at: 5),
                contentId: row.string(at: 6) ?? "",
                lastModified: !row.isNull(at: 8) ? row.int64(at: 8) : nil,
                searchMode: row.int(at: 9),
                nearDistance: row.int(at: 10)
            )
        }
    }

    private func groupRawResultRows(_ results: [RawResultRow]) -> [String: SavedResultsGroup] {
        var groupedResults: [String: SavedResultsGroup] = [:]
        for res in results {
            let contentsId = res.contentId.components(separatedBy: ",")
            for cid in contentsId {
                guard let idInt = Int(cid) else { continue }
                let book = LibraryDataManager.shared.getBook([res.bkId]).first

                let item = SavedResultsItem(
                    archive: String(res.archive),
                    tableName: String(res.bkId),
                    query: res.query,
                    bookId: idInt,
                    bookTitle: book?.book ?? "",
                    searchMode: res.searchMode,
                    nearDistance: res.nearDistance
                )

                if groupedResults[res.name] == nil {
                    groupedResults[res.name] = SavedResultsGroup(id: res.id, parentId: res.parentId, lastModified: res.lastModified, items: [])
                }
                groupedResults[res.name]?.items.append(item)
            }
        }
        return groupedResults
    }

    private func buildResultNodes(from groupedResults: [String: SavedResultsGroup]) -> [ResultNode] {
        groupedResults.map {
            let mode = $0.value.items.first?.searchMode ?? 0
            let distance = $0.value.items.first?.nearDistance ?? 10
            return ResultNode(
                id: $0.value.id,
                parentId: $0.value.parentId,
                name: $0.key,
                lastModified: $0.value.lastModified,
                searchMode: mode,
                nearDistance: distance,
                items: $0.value.items
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func deleteResult(_ folderId: Int64?, name: String) {
        guard let db else { return }
        var ckIds: [String] = []
        let sql: String
        var params: [Any] = []

        if let fid = folderId {
            sql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?"
            params = [fid, name]
        } else {
            sql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?"
            params = [name]
        }

        do {
            ckIds = try db.fetch(query: sql, parameters: params, mapping: { $0.string(at: 0) ?? "" })

            if let fid = folderId {
                try exec("DELETE FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?;", parameters: [fid, name])
            } else {
                try exec("DELETE FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?;", parameters: [name])
            }
            for id in ckIds {
                try addPendingSync(ckRecordId: id, operation: "delete")
            }

            if !ckIds.isEmpty {
                CloudKitSyncManager.shared.delete(ckRecordIds: ckIds, target: .result, trackPending: false)
            }
        } catch {
            print(error.localizedDescription)
        }
    }

    func updateResultParent(newParentId: Int64?, oldParent: Int64?, name: String) throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let fCkId = try newParentId.flatMap { try findFolderCkId(id: $0) }

        let updateSql: String
        var params: [Any] = [newParentId ?? NSNull(), now, fCkId ?? NSNull()]

        if let old = oldParent {
            updateSql = "UPDATE \(resultsTable) SET \(colFolderId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ? WHERE \(colFolderId) = ? AND \(colName) = ?;"
            params.append(contentsOf: [old, name])
        } else {
            updateSql = "UPDATE \(resultsTable) SET \(colFolderId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ? WHERE \(colFolderId) IS NULL AND \(colName) = ?;"
            params.append(name)
        }

        var ckIds: [String] = []
        try transaction {
            let findCkIdSql: String
            let findCkIdParams: [Any]
            if let old = oldParent {
                findCkIdSql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?"
                findCkIdParams = [old, name]
            } else {
                findCkIdSql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?"
                findCkIdParams = [name]
            }
            ckIds = try db.fetch(query: findCkIdSql, parameters: findCkIdParams) { $0.string(at: 0) }.compactMap { $0 }

            try exec(updateSql, parameters: params)
            for ckId in ckIds {
                try self.addPendingSync(ckRecordId: ckId, operation: "upload")
            }
        }

        let whereClause = newParentId != nil ? "WHERE \(colFolderId) = ? AND \(colName) = ?" : "WHERE \(colFolderId) IS NULL AND \(colName) = ?"
        let reloadParams: [Any] = newParentId != nil ? [newParentId!, name] : [name]
        let updated = try fetchSyncResults(whereClause: whereClause, parameters: reloadParams)

        if !updated.isEmpty {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: updated, trackPending: false)
        }
    }

    func updateResultQueryName(folderId: Int64?, oldName: String, newName: String) throws {
        guard let db else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let sql: String
        var params: [Any] = []

        if let fid = folderId {
            sql = "UPDATE \(resultsTable) SET \(colName) = ?, \(colResLastModified) = ? WHERE \(colFolderId) = ? AND \(colName) = ?;"
            params = [newName, now, fid, oldName]
        } else {
            sql = "UPDATE \(resultsTable) SET \(colName) = ?, \(colResLastModified) = ? WHERE \(colFolderId) IS NULL AND \(colName) = ?;"
            params = [newName, now, oldName]
        }

        var ckIds: [String] = []
        try transaction {
            let findCkIdSql: String
            let findCkIdParams: [Any]
            if let fid = folderId {
                findCkIdSql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ?"
                findCkIdParams = [fid, oldName]
            } else {
                findCkIdSql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) IS NULL AND \(colName) = ?"
                findCkIdParams = [oldName]
            }
            ckIds = try db.fetch(query: findCkIdSql, parameters: findCkIdParams) { $0.string(at: 0) }.compactMap { $0 }

            try exec(sql, parameters: params)

            for ckId in ckIds {
                try self.addPendingSync(ckRecordId: ckId, operation: "upload")
            }
        }

        let whereClause = folderId != nil ? "WHERE \(colFolderId) = ? AND \(colName) = ?" : "WHERE \(colFolderId) IS NULL AND \(colName) = ?"
        let reloadParams: [Any] = folderId != nil ? [folderId!, newName] : [newName]
        let updatedResults = try fetchSyncResults(whereClause: whereClause, parameters: reloadParams)

        if !updatedResults.isEmpty {
            CloudKitSyncManager.shared.uploadResultsData(folders: [], results: updatedResults, trackPending: false)
        }
    }

    func updateResultsFolder(oldFolderId: Int64, newFolderId: Int64) {
        let now = Int64(Date().timeIntervalSince1970)

        do {
            var updatedResults: [SyncResult] = []
            try transaction {
                let fCkId = try findFolderCkId(id: newFolderId)
                let updateSql = "UPDATE \(resultsTable) SET \(colFolderId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ? WHERE \(colFolderId) = ?;"
                let params: [Any] = [newFolderId, now, fCkId ?? NSNull(), oldFolderId]
                try exec(updateSql, parameters: params)

                updatedResults = try fetchSyncResults(whereClause: "WHERE \(colFolderId) = ?", parameters: [newFolderId])

                for res in updatedResults {
                    if let ckId = res.ckRecordId {
                        try self.addPendingSync(ckRecordId: ckId, operation: "upload")
                    }
                }
            }

            if !updatedResults.isEmpty {
                CloudKitSyncManager.shared.uploadResultsData(folders: [], results: updatedResults, trackPending: false)
            }
        } catch {
            print("Failed to update results folder: \(error)")
        }
    }

    func migrateBookId(from oldId: Int, to newId: Int) throws -> [SyncResult] {
        let now = Int64(Date().timeIntervalSince1970)
        let sql = "UPDATE \(resultsTable) SET \(colBkId) = ?, \(colResLastModified) = ? WHERE \(colBkId) = ?"

        var updatedResults: [SyncResult] = []
        try transaction {
            try exec(sql, parameters: [newId, now, oldId])
            updatedResults = try fetchSyncResults(whereClause: "WHERE \(colBkId) = ?", parameters: [newId])

            for res in updatedResults {
                if let ckId = res.ckRecordId {
                    try addPendingSync(ckRecordId: ckId, operation: "upload")
                }
            }
        }
        return updatedResults
    }

    func fetchResults(byCkRecordIds ckRecordIds: [String]) -> [SyncResult] {
        var results: [SyncResult] = []
        for chunk in ckRecordIds.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            if let fetched = try? fetchSyncResults(whereClause: "WHERE \(colResCkRecordId) IN (\(placeholders))", parameters: chunk) {
                results.append(contentsOf: fetched)
            }
        }
        return results
    }

    func fetchAllSyncResults() -> [SyncResult] {
        do {
            return try fetchSyncResults()
        } catch {
            print("Failed to fetch all sync results: \(error)")
            return []
        }
    }
}
