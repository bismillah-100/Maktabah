//
//  ResultsCloudKit.swift
//  Maktabah
//
//  Created by MacBook on 05/12/25.
//

import Foundation
import OSLog
import SQLite3

extension ResultsHandler {
    func backfillResultsCloudKitFieldsIfNeeded(uploadIfNeeded: Bool = true) throws {
        guard db != nil else { return }
        let now = Int64(Date().timeIntervalSince1970)

        let foldersToUpload = try backfillFoldersCloudKitFields(now: now)
        let resultsToUpload = try backfillResultsCloudKitFields(now: now)

        if uploadIfNeeded, !foldersToUpload.isEmpty || !resultsToUpload.isEmpty {
            DispatchQueue.global(qos: .background).async {
                CloudKitSyncManager.shared.uploadResultsData(folders: foldersToUpload, results: resultsToUpload, trackPending: true)
            }
        }
    }

    private func backfillFoldersCloudKitFields(now: Int64) throws -> [SyncFolder] {
        guard let db else { return [] }
        var foldersToUpload: [SyncFolder] = []

        try transaction {
            let sql = "SELECT \(allFoldersColumns) FROM \(foldersTable) WHERE \(colCkRecordId) IS NULL ORDER BY \(colParent) ASC"

            struct BackfillFolderRow {
                let id: Int64
                let name: String
                let parent: Int64?
            }

            let folders = try db.fetch(query: sql) { row -> BackfillFolderRow in
                BackfillFolderRow(
                    id: row.int64(at: 0),
                    name: row.string(at: 1) ?? "",
                    parent: !row.isNull(at: 2) ? row.int64(at: 2) : nil
                )
            }

            for folder in folders {
                let fId = folder.id
                let parentIdentifier: String = if let pid = folder.parent {
                    (try? findFolderCkId(id: pid)) ?? "orphan_\(pid)"
                } else {
                    "root"
                }

                let cId = UUID().uuidString
                let parentCkRecordIdValue: Any = parentIdentifier == "root" ? NSNull() : parentIdentifier

                try exec("UPDATE \(foldersTable) SET \(colCkRecordId) = ?, \(colLastModified) = ?, \(colParentCkRecordId) = ? WHERE \(colId) = ?;", parameters: [cId, now, parentCkRecordIdValue, fId])
                try self.addPendingSync(ckRecordId: cId, operation: "upload")

                if let reloaded = try reloadSyncFolder(id: fId) {
                    foldersToUpload.append(reloaded)
                }
            }
        }
        return foldersToUpload
    }

    private func backfillResultsCloudKitFields(now: Int64) throws -> [SyncResult] {
        guard let db else { return [] }
        var resultsToUpload: [SyncResult] = []

        try transaction {
            let sql = "SELECT \(allResultsColumns) FROM \(resultsTable) WHERE \(colResCkRecordId) IS NULL"

            struct BackfillResultRow {
                let id: Int64
                let folderId: Int64?
                let name: String
                let bkId: Int
                let archive: Int
            }

            let results = try db.fetch(query: sql) { row -> BackfillResultRow in
                BackfillResultRow(
                    id: row.int64(at: 0),
                    folderId: !row.isNull(at: 1) ? row.int64(at: 1) : nil,
                    name: row.string(at: 2) ?? "",
                    bkId: row.int(at: 5),
                    archive: row.int(at: 4)
                )
            }

            for res in results {
                let rId = res.id
                let folderIdentifier: String = if let fid = res.folderId {
                    (try? findFolderCkId(id: fid)) ?? "orphan_\(fid)"
                } else {
                    "root"
                }

                let cId = UUID().uuidString
                let folderCkIdValue: Any = folderIdentifier == "root" ? NSNull() : folderIdentifier

                try exec("UPDATE \(resultsTable) SET \(colResCkRecordId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ? WHERE \(colId) = ?;", parameters: [cId, now, folderCkIdValue, rId])
                try self.addPendingSync(ckRecordId: cId, operation: "upload")

                if let reloaded = try reloadSyncResult(id: rId) {
                    resultsToUpload.append(reloaded)
                }
            }
        }
        return resultsToUpload
    }

    @discardableResult
    func applyCloudKitFolderChanges(foldersToSave: [SyncFolder], recordIdsToDelete: [String]) -> Bool {
        guard let db else { return false }
        var hasChanges = false

        do {
            try transaction {
                let deletedCount = try processFolderDeletions(recordIdsToDelete: recordIdsToDelete, db: db)
                if deletedCount > 0 {
                    hasChanges = true
                }
                let sortedFolders = sortFoldersTopologically(folders: foldersToSave)
                var (folderCkIdToLocalId, folderCkIdToExisting) = try prefetchFolderSyncContext(foldersToSave: foldersToSave, db: db)

                for folder in sortedFolders {
                    if try processSingleFolderSave(folder, db: db, folderCkIdToLocalId: &folderCkIdToLocalId, folderCkIdToExisting: folderCkIdToExisting) {
                        hasChanges = true
                    }
                }
            }

            if resolveOrphanFolders() {
                hasChanges = true
            }

            if hasChanges {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .savedResultsTreeDidUpdate, object: nil)
                }
            }
        } catch {
            Logger.sync.error("ResultsHandler: Failed to apply folder changes: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return true
    }

    private func prefetchFolderSyncContext(
        foldersToSave: [SyncFolder],
        db: SQLiteDatabase
    ) throws -> (folderCkIdToLocalId: [String: Int64], folderCkIdToExisting: [String: ExistingFolderInfo]) {
        let allParentCkIds = Array(Set(foldersToSave.compactMap(\.parentCkRecordId)))
        let folderCkIdToLocalId = try fetchFolderLocalIdMap(for: allParentCkIds, db: db)

        let allFolderCkIds = Array(Set(foldersToSave.compactMap(\.ckRecordId)))
        var folderCkIdToExisting: [String: ExistingFolderInfo] = [:]
        for chunk in allFolderCkIds.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let sql = "SELECT \(colCkRecordId), \(colId), \(colName), \(colLastModified), \(colParent) FROM \(foldersTable) WHERE \(colCkRecordId) IN (\(placeholders))"
            let rows = try db.fetch(query: sql, parameters: chunk, mapping: { row -> (String, ExistingFolderInfo) in
                let ckId = row.string(at: 0) ?? ""
                let info = ExistingFolderInfo(
                    id: row.int64(at: 1),
                    name: row.string(at: 2) ?? "",
                    lastModified: row.int64(at: 3),
                    parentId: !row.isNull(at: 4) ? row.int64(at: 4) : nil
                )
                return (ckId, info)
            })
            for (ckId, info) in rows {
                folderCkIdToExisting[ckId] = info
            }
        }

        return (folderCkIdToLocalId, folderCkIdToExisting)
    }

    @discardableResult
    private func processFolderDeletions(recordIdsToDelete: [String], db: SQLiteDatabase) throws -> Int {
        guard !recordIdsToDelete.isEmpty else { return 0 }
        var allLocalIdsToDelete = Set<Int64>()

        for chunk in recordIdsToDelete.chunked(into: 999) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let findSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colCkRecordId) IN (\(placeholders))"

            let localIds = try db.fetch(query: findSql, parameters: chunk, mapping: { $0.int64(at: 0) })

            for localId in localIds {
                let descendantIds = getAllDescendantIds(of: localId)
                allLocalIdsToDelete.formUnion(descendantIds)
            }
        }

        guard !allLocalIdsToDelete.isEmpty else { return 0 }

        let uniqueLocalIds = Array(allLocalIdsToDelete)
        for chunk in uniqueLocalIds.chunked(into: 999) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            try exec("DELETE FROM \(resultsTable) WHERE \(colFolderId) IN (\(placeholders));", parameters: chunk)
            try exec("DELETE FROM \(foldersTable) WHERE \(colId) IN (\(placeholders));", parameters: chunk)
        }
        return uniqueLocalIds.count
    }

    private func sortFoldersTopologically(folders: [SyncFolder]) -> [SyncFolder] {
        var sortedFolders: [SyncFolder] = []
        var pendingFolders = folders
        var progress = true

        while !pendingFolders.isEmpty, progress {
            progress = false
            let pendingIds = Set(pendingFolders.compactMap(\.ckRecordId))
            pendingFolders = pendingFolders.filter { f in
                let parentInPending = f.parentCkRecordId.map { pendingIds.contains($0) } ?? false
                if !parentInPending {
                    sortedFolders.append(f)
                    progress = true
                    return false
                }
                return true
            }
        }
        sortedFolders.append(contentsOf: pendingFolders)
        return sortedFolders
    }

    private func processSingleFolderSave(
        _ folder: SyncFolder,
        db: SQLiteDatabase,
        folderCkIdToLocalId: inout [String: Int64],
        folderCkIdToExisting: [String: ExistingFolderInfo]
    ) throws -> Bool {
        guard let ckId = folder.ckRecordId else { return false }

        var pLocalId: Int64?
        if let pCK = folder.parentCkRecordId {
            pLocalId = folderCkIdToLocalId[pCK]
        }

        if let existing = folderCkIdToExisting[ckId] {
            return try updateExistingFolder(folder, db: db, existing: existing, pLocalId: pLocalId)
        } else {
            return try insertOrResolveConflictFolder(folder, db: db, ckId: ckId, pLocalId: pLocalId, folderCkIdToLocalId: &folderCkIdToLocalId)
        }
    }

    private func updateExistingFolder(
        _ folder: SyncFolder,
        db: SQLiteDatabase,
        existing: ExistingFolderInfo,
        pLocalId: Int64?
    ) throws -> Bool {
        let remoteLastMod = folder.lastModified ?? 0
        guard remoteLastMod >= existing.lastModified else { return false }

        let isOrphan = folder.parentCkRecordId != nil && pLocalId == nil
        let newParentForDb = isOrphan ? existing.parentId : pLocalId

        var didDeleteConflict = false
        if !isOrphan || newParentForDb != nil {
            let conflictSql: String
            let conflictParams: [Any]
            if let pid = newParentForDb {
                conflictSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colParent) = ? AND \(colName) = ? AND \(colId) != ? LIMIT 1"
                conflictParams = [pid, folder.name, existing.id]
            } else {
                conflictSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colParent) IS NULL AND \(colName) = ? AND \(colId) != ? LIMIT 1"
                conflictParams = [folder.name, existing.id]
            }
            if let conflictId = try db.fetch(query: conflictSql, parameters: conflictParams, mapping: { $0.int64(at: 0) }).first {
                try exec("DELETE FROM \(resultsTable) WHERE \(colFolderId) = ?;", parameters: [conflictId])
                try exec("DELETE FROM \(foldersTable) WHERE \(colId) = ?;", parameters: [conflictId])
                didDeleteConflict = true
            }
        }

        if !didDeleteConflict,
           remoteLastMod == existing.lastModified,
           newParentForDb == existing.parentId,
           folder.name == existing.name
        {
            return false
        }

        let upSql = """
        UPDATE \(foldersTable) SET 
        \(colName) = ?, \(colParent) = ?, \(colLastModified) = ?, \(colParentCkRecordId) = ?
        WHERE \(colId) = ?;
        """
        let params: [Any] = [
            folder.name, newParentForDb ?? NSNull(), folder.lastModified ?? 0,
            folder.parentCkRecordId ?? NSNull(), existing.id,
        ]
        try db.execute(query: upSql, parameters: params)
        return true
    }

    private func findConflictingFolder(
        _ folder: SyncFolder,
        db: SQLiteDatabase,
        pLocalId: Int64?
    ) throws -> (id: Int64, lastModified: Int64)? {
        let isOrphan = folder.parentCkRecordId != nil && pLocalId == nil
        guard !isOrphan else { return nil }

        let condition = pLocalId != nil ? "\(colParent) = ?" : "\(colParent) IS NULL"
        let conflictSql = "SELECT \(colId), \(colLastModified) FROM \(foldersTable) WHERE \(condition) AND \(colName) = ? LIMIT 1"
        let conflictParams: [Any] = pLocalId != nil ? [pLocalId!, folder.name] : [folder.name]

        return try db.fetch(
            query: conflictSql,
            parameters: conflictParams,
            mapping: { ($0.int64(at: 0), $0.int64(at: 1)) }
        ).first
    }

    private func insertOrResolveConflictFolder(
        _ folder: SyncFolder,
        db: SQLiteDatabase,
        ckId: String,
        pLocalId: Int64?,
        folderCkIdToLocalId: inout [String: Int64]
    ) throws -> Bool {
        let conflict = try findConflictingFolder(folder, db: db, pLocalId: pLocalId)

        if let (conflictLocalId, conflictLastMod) = conflict {
            let remoteLastMod = folder.lastModified ?? 0

            if remoteLastMod >= conflictLastMod {
                let upSql = """
                UPDATE \(foldersTable) SET 
                \(colName) = ?, \(colParent) = ?, \(colCkRecordId) = ?, \(colLastModified) = ?, \(colParentCkRecordId) = ?
                WHERE \(colId) = ?;
                """
                let params: [Any] = [
                    folder.name, pLocalId ?? NSNull(), ckId, folder.lastModified ?? 0,
                    folder.parentCkRecordId ?? NSNull(), conflictLocalId,
                ]
                try db.execute(query: upSql, parameters: params)
            } else {
                let upCkIdSql = "UPDATE \(foldersTable) SET \(colCkRecordId) = ? WHERE \(colId) = ?"
                try db.execute(query: upCkIdSql, parameters: [ckId, conflictLocalId])
            }

            folderCkIdToLocalId[ckId] = conflictLocalId
            return remoteLastMod >= conflictLastMod
        } else {
            let params: [Any] = [
                folder.name, pLocalId ?? NSNull(), ckId, folder.lastModified ?? 0,
                folder.parentCkRecordId ?? NSNull(),
            ]
            try db.execute(query: insertFolderSQL, parameters: params)
            folderCkIdToLocalId[ckId] = db.lastInsertRowId()
            return true
        }
    }

    @discardableResult
    func applyCloudKitResultChanges(resultsToSave: [SyncResult], recordIdsToDelete: [String]) -> Bool {
        guard let db else { return false }
        var hasChanges = false

        do {
            try transaction {
                let deletedCount = try processResultDeletions(recordIdsToDelete: recordIdsToDelete, db: db)
                if deletedCount > 0 {
                    hasChanges = true
                }

                let syncContext = try prefetchResultsSyncContext(resultsToSave: resultsToSave, db: db)
                let folderCkIdToLocalId = syncContext.folderMap
                let resCkIdToExisting = syncContext.resMap
                var conflictMap = syncContext.conflictMap

                for res in resultsToSave {
                    guard let ckId = res.ckRecordId else { continue }
                    let fLocalId = res.folderCkRecordId.flatMap { folderCkIdToLocalId[$0] }

                    if let existing = resCkIdToExisting[ckId] {
                        if try saveUpdatedSyncResult(res, db: db, existing: existing, fLocalId: fLocalId, conflictMap: &conflictMap) {
                            hasChanges = true
                        }
                    } else {
                        if try insertOrResolveConflictResult(res, db: db, ckId: ckId, fLocalId: fLocalId, conflictMap: &conflictMap) {
                            hasChanges = true
                        }
                    }
                }
            }

            if resolveOrphanResults() {
                hasChanges = true
            }

            if hasChanges {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .savedResultsTreeDidUpdate, object: nil)
                }
            }
        } catch {
            Logger.sync.error("ResultsHandler: Failed to apply result changes: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return true
    }

    @discardableResult
    private func processResultDeletions(recordIdsToDelete: [String], db: SQLiteDatabase) throws -> Int {
        guard !recordIdsToDelete.isEmpty else { return 0 }
        var deletedCount = 0

        for chunk in recordIdsToDelete.chunked(into: 999) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let findSql = "SELECT \(colId) FROM \(resultsTable) WHERE \(colResCkRecordId) IN (\(placeholders))"
            let matchingIds = try db.fetch(query: findSql, parameters: chunk, mapping: { $0.int64(at: 0) })
            if !matchingIds.isEmpty {
                let idPlaceholders = String(repeating: "?,", count: matchingIds.count).dropLast()
                try exec("DELETE FROM \(resultsTable) WHERE \(colId) IN (\(idPlaceholders));", parameters: matchingIds)
                deletedCount += matchingIds.count
            }
        }
        return deletedCount
    }

    private func prefetchResultsSyncContext(
        resultsToSave: [SyncResult],
        db: SQLiteDatabase
    ) throws -> ResultsSyncContext {
        let folderMap = try prefetchResultsFolderMap(resultsToSave: resultsToSave, db: db)
        let resMap = try prefetchExistingResultsMap(resultsToSave: resultsToSave, db: db)
        let conflictMap = try prefetchConflictResultsMap(resultsToSave: resultsToSave, db: db)

        return ResultsSyncContext(folderMap: folderMap, resMap: resMap, conflictMap: conflictMap)
    }

    private func prefetchResultsFolderMap(resultsToSave: [SyncResult], db: SQLiteDatabase) throws -> [String: Int64] {
        let allFolderCkIds = Array(Set(resultsToSave.compactMap(\.folderCkRecordId)))
        return try fetchFolderLocalIdMap(for: allFolderCkIds, db: db)
    }

    private func fetchFolderLocalIdMap(for ckIds: [String], db: SQLiteDatabase) throws -> [String: Int64] {
        var folderCkIdToLocalId: [String: Int64] = [:]
        for chunk in ckIds.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let sql = "SELECT \(colCkRecordId), \(colId) FROM \(foldersTable) WHERE \(colCkRecordId) IN (\(placeholders))"
            let rows = try db.fetch(query: sql, parameters: chunk, mapping: { ($0.string(at: 0) ?? "", $0.int64(at: 1)) })
            for (ckId, localId) in rows {
                folderCkIdToLocalId[ckId] = localId
            }
        }
        return folderCkIdToLocalId
    }

    private func prefetchExistingResultsMap(resultsToSave: [SyncResult], db: SQLiteDatabase) throws -> [String: ExistingResultInfo] {
        let allResCkIds = Array(Set(resultsToSave.compactMap(\.ckRecordId)))
        var resCkIdToExisting: [String: ExistingResultInfo] = [:]
        for chunk in allResCkIds.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let sql = "SELECT \(colResCkRecordId), \(colId), \(colName), \(colResLastModified), \(colFolderId) FROM \(resultsTable) WHERE \(colResCkRecordId) IN (\(placeholders))"
            let rows = try db.fetch(query: sql, parameters: chunk, mapping: { row -> (String, ExistingResultInfo) in
                let ckId = row.string(at: 0) ?? ""
                let info = ExistingResultInfo(
                    id: row.int64(at: 1),
                    name: row.string(at: 2) ?? "",
                    lastModified: row.int64(at: 3),
                    folderId: !row.isNull(at: 4) ? row.int64(at: 4) : nil
                )
                return (ckId, info)
            })
            for (ckId, info) in rows {
                resCkIdToExisting[ckId] = info
            }
        }
        return resCkIdToExisting
    }

    private func prefetchConflictResultsMap(resultsToSave: [SyncResult], db: SQLiteDatabase) throws -> [String: (Int64, Int64)] {
        var conflictMap: [String: (Int64, Int64)] = [:]
        let allBkIds = Array(Set(resultsToSave.compactMap(\.bkId)))
        for chunk in allBkIds.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            let conflictSql = "SELECT \(colId), \(colResLastModified), \(colFolderId), \(colName), \(colBkId) FROM \(resultsTable) WHERE \(colBkId) IN (\(placeholders))"
            let rows = try db.fetch(query: conflictSql, parameters: chunk, mapping: { row -> ConflictResultRow in
                ConflictResultRow(
                    id: row.int64(at: 0),
                    lastModified: row.int64(at: 1),
                    folderId: !row.isNull(at: 2) ? row.int64(at: 2) : nil,
                    name: row.string(at: 3) ?? "",
                    bkId: row.int(at: 4)
                )
            })
            for row in rows {
                let fIdStr = row.folderId != nil ? "\(row.folderId!)" : "NULL"
                let key = "\(fIdStr)_\(row.name)_\(row.bkId)"
                conflictMap[key] = (row.id, row.lastModified)
            }
        }
        return conflictMap
    }

    private func saveUpdatedSyncResult(
        _ res: SyncResult,
        db: SQLiteDatabase,
        existing: ExistingResultInfo,
        fLocalId: Int64?,
        conflictMap: inout [String: (Int64, Int64)]
    ) throws -> Bool {
        let remoteLastMod = res.lastModified ?? 0
        guard remoteLastMod >= existing.lastModified else { return false }

        let isOrphan = res.folderCkRecordId != nil && fLocalId == nil
        let newFolderForDb = isOrphan ? existing.folderId : fLocalId

        let fIdStr = newFolderForDb != nil ? "\(newFolderForDb!)" : "NULL"
        let key = "\(fIdStr)_\(res.name)_\(res.bkId)"

        var didDeleteConflict = false
        if !isOrphan || newFolderForDb != nil,
           let conflict = conflictMap[key], conflict.0 != existing.id
        {
            try exec("DELETE FROM \(resultsTable) WHERE \(colId) = ?;", parameters: [conflict.0])
            conflictMap.removeValue(forKey: key)
            didDeleteConflict = true
        }

        if !didDeleteConflict,
           remoteLastMod == existing.lastModified,
           newFolderForDb == existing.folderId,
           res.name == existing.name
        {
            return false
        }

        let upSql = """
        UPDATE \(resultsTable) SET 
        \(colFolderId) = ?, \(colName) = ?, \(colQuery) = ?, \(colArchive) = ?,
        \(colBkId) = ?, \(colContentId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ?, \(colSearchMode) = ?, \(colNearDistance) = ?
        WHERE \(colId) = ?;
        """
        let params: [Any] = [
            newFolderForDb ?? NSNull(), res.name, res.query, res.archive,
            res.bkId, res.contentId, res.lastModified ?? 0, res.folderCkRecordId ?? NSNull(),
            res.searchMode, res.nearDistance, existing.id,
        ]
        try db.execute(query: upSql, parameters: params)
        conflictMap[key] = (existing.id, res.lastModified ?? 0)
        return true
    }

    private func insertOrResolveConflictResult(
        _ res: SyncResult,
        db: SQLiteDatabase,
        ckId: String,
        fLocalId: Int64?,
        conflictMap: inout [String: (Int64, Int64)]
    ) throws -> Bool {
        let isOrphan = res.folderCkRecordId != nil && fLocalId == nil
        let fIdStr = fLocalId != nil ? "\(fLocalId!)" : "NULL"
        let key = "\(fIdStr)_\(res.name)_\(res.bkId)"
        let conflict = !isOrphan ? conflictMap[key] : nil

        if let conflict {
            let changed = try updateConflictResult(res, db: db, ckId: ckId, fLocalId: fLocalId, conflict: conflict)
            if (res.lastModified ?? 0) >= conflict.1 {
                conflictMap[key] = (conflict.0, res.lastModified ?? 0)
            }
            return changed
        } else {
            let params: [Any] = [
                fLocalId ?? NSNull(), res.name, res.query, res.archive,
                res.bkId, res.contentId, ckId, res.lastModified ?? 0,
                res.folderCkRecordId ?? NSNull(), res.searchMode, res.nearDistance,
            ]
            try db.execute(query: insertResultSQL, parameters: params)
            conflictMap[key] = (db.lastInsertRowId(), res.lastModified ?? 0)
            return true
        }
    }

    private func updateConflictResult(
        _ res: SyncResult,
        db: SQLiteDatabase,
        ckId: String,
        fLocalId: Int64?,
        conflict: (Int64, Int64)
    ) throws -> Bool {
        let remoteLastMod = res.lastModified ?? 0
        if remoteLastMod >= conflict.1 {
            let upSql = """
            UPDATE \(resultsTable) SET 
            \(colFolderId) = ?, \(colName) = ?, \(colQuery) = ?, \(colArchive) = ?,
            \(colBkId) = ?, \(colContentId) = ?, \(colResCkRecordId) = ?, \(colResLastModified) = ?, \(colFolderCkRecordId) = ?, \(colSearchMode) = ?, \(colNearDistance) = ?
            WHERE \(colId) = ?;
            """
            let params: [Any] = [
                fLocalId ?? NSNull(), res.name, res.query, res.archive,
                res.bkId, res.contentId, ckId, res.lastModified ?? 0, res.folderCkRecordId ?? NSNull(),
                res.searchMode, res.nearDistance, conflict.0,
            ]
            try db.execute(query: upSql, parameters: params)
            return true
        } else {
            let upCkIdSql = "UPDATE \(resultsTable) SET \(colResCkRecordId) = ? WHERE \(colId) = ?"
            try db.execute(query: upCkIdSql, parameters: [ckId, conflict.0])
            return false
        }
    }
}
