//
//  ResultsFolders.swift
//  Maktabah
//
//  Created by MacBook on 05/12/25.
//

import Foundation
import SQLite3

extension ResultsHandler {
    func insertFolder(name: String, parentNode: FolderNode? = nil) throws -> Int64? {
        guard let db else { return nil }
        let cId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)

        let parentId: Any = parentNode?.id ?? NSNull()
        let pCkId: Any = parentNode != nil ? ((try? findFolderCkId(id: parentNode!.id)) ?? NSNull()) : NSNull()
        let params: [Any] = [name, parentId, cId, now, pCkId]

        var rowId: Int64 = -1
        try transaction {
            try exec(insertFolderSQL, parameters: params)
            rowId = db.lastInsertRowId()
            try self.addPendingSync(ckRecordId: cId, operation: "upload")
        }

        if rowId != -1, let reloaded = try reloadSyncFolder(id: rowId) {
            CloudKitSyncManager.shared.uploadResultsData(folders: [reloaded], results: [], trackPending: false)
        }

        return rowId != -1 ? rowId : nil
    }

    func insertRootFolder(name: String) throws -> Int64? {
        try insertFolder(name: name, parentNode: nil)
    }

    func insertSubFolder(parentNode: FolderNode, name: String) throws -> Int64? {
        try insertFolder(name: name, parentNode: parentNode)
    }

    func fetchFolderTree() -> [FolderNode] {
        guard let db else { return [] }
        var nodes: [Int64: FolderNode] = [:]
        var roots: [FolderNode] = []

        let sql = "SELECT \(colId), \(colName), \(colParent), \(colLastModified), \(colParentCkRecordId) FROM \(foldersTable)"
        do {
            struct FolderTreeRow {
                let id: Int64
                let name: String
                let parent: Int64?
                let lastModified: Int64?
                let parentCkId: String?
            }

            let rows = try db.fetch(query: sql) { row -> FolderTreeRow in
                let fid = row.int64(at: 0)
                let fname = row.string(at: 1) ?? ""
                let fparent = !row.isNull(at: 2) ? row.int64(at: 2) : nil
                let flastMod = !row.isNull(at: 3) ? row.int64(at: 3) : nil
                let fparentCkId = row.string(at: 4)
                return FolderTreeRow(id: fid, name: fname, parent: fparent, lastModified: flastMod, parentCkId: fparentCkId)
            }

            for row in rows {
                let node = FolderNode(id: row.id, name: row.name, lastModified: row.lastModified)
                nodes[row.id] = node
            }

            for row in rows {
                if let parentId = row.parent, let parentNode = nodes[parentId] {
                    parentNode.children.append(nodes[row.id]!)
                } else if row.parentCkId == nil {
                    roots.append(nodes[row.id]!)
                }
            }
        } catch {
            print("Failed to fetch folder tree: \(error)")
        }

        return roots
    }

    func deleteFolder(_ folderId: Int64) {
        guard let db else { return }
        do {
            let allFolderIds = getAllDescendantIds(of: folderId)
            var ckIdsToDelete: [String] = []

            for fId in allFolderIds {
                if let ckId = try findFolderCkId(id: fId) {
                    ckIdsToDelete.append(ckId)
                }

                let findResSql = "SELECT \(colResCkRecordId) FROM \(resultsTable) WHERE \(colFolderId) = ?"
                let resCkIds = try db.fetch(query: findResSql, parameters: [fId]) { $0.string(at: 0) }
                ckIdsToDelete.append(contentsOf: resCkIds.compactMap { $0 })
            }

            try transaction {
                for id in allFolderIds {
                    try exec("DELETE FROM \(resultsTable) WHERE \(colFolderId) = ?;", parameters: [id])
                }
                for id in allFolderIds.reversed() {
                    try exec("DELETE FROM \(foldersTable) WHERE \(colId) = ?;", parameters: [id])
                }
                for id in ckIdsToDelete {
                    try self.addPendingSync(ckRecordId: id, operation: "delete")
                }
            }

            if !ckIdsToDelete.isEmpty {
                CloudKitSyncManager.shared.delete(ckRecordIds: ckIdsToDelete, target: .result, trackPending: false)
            }
        } catch {
            print("Delete transaction failed:", error)
        }
    }

    func updateParent(of id: Int64, to newParentId: Int64?) throws {
        let now = Int64(Date().timeIntervalSince1970)
        var reloaded: SyncFolder?

        try transaction {
            let pCkId = try newParentId.flatMap { try findFolderCkId(id: $0) }
            let updateSql = "UPDATE \(foldersTable) SET \(colParent) = ?, \(colLastModified) = ?, \(colParentCkRecordId) = ? WHERE \(colId) = ?;"
            let params: [Any] = [newParentId ?? NSNull(), now, pCkId ?? NSNull(), id]
            try exec(updateSql, parameters: params)

            if let fetched = try reloadSyncFolder(id: id) {
                reloaded = fetched
                if let ckId = fetched.ckRecordId {
                    try self.addPendingSync(ckRecordId: ckId, operation: "upload")
                }
            }
        }

        if let folderToUpload = reloaded {
            CloudKitSyncManager.shared.uploadResultsData(folders: [folderToUpload], results: [], trackPending: false)
        }
    }

    func updateFolderName(id folderId: Int64, newName: String) throws {
        let now = Int64(Date().timeIntervalSince1970)
        let sql = "UPDATE \(foldersTable) SET \(colName) = ?, \(colLastModified) = ? WHERE \(colId) = ?;"

        try transaction {
            let ckId = try findFolderCkId(id: folderId)
            try exec(sql, parameters: [newName, now, folderId])

            if let ckId {
                try self.addPendingSync(ckRecordId: ckId, operation: "upload")
            }
        }

        if let reloaded = try reloadSyncFolder(id: folderId) {
            CloudKitSyncManager.shared.uploadResultsData(folders: [reloaded], results: [], trackPending: false)
        }
    }

    func getAllDescendantIds(of folderId: Int64) -> [Int64] {
        guard let db else { return [folderId] }
        var ids: [Int64] = []
        _getAllDescendantIds(of: folderId, ids: &ids, db: db)
        return ids
    }

    private func _getAllDescendantIds(of folderId: Int64, ids: inout [Int64], db: SQLiteDatabase) {
        ids.append(folderId)
        let sql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colParent) = ?"
        do {
            let children = try db.fetch(query: sql, parameters: [folderId]) { $0.int64(at: 0) }
            for childId in children {
                _getAllDescendantIds(of: childId, ids: &ids, db: db)
            }
        } catch {
            print("Failed to get descendant IDs: \(error)")
        }
    }

    func fetchFolders(byCkRecordIds ckRecordIds: [String]) -> [SyncFolder] {
        var folders: [SyncFolder] = []
        for chunk in ckRecordIds.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            if let fetched = try? fetchSyncFolders(whereClause: "WHERE \(colCkRecordId) IN (\(placeholders))", parameters: chunk) {
                folders.append(contentsOf: fetched)
            }
        }
        return folders
    }

    func fetchAllSyncFolders() -> [SyncFolder] {
        do {
            return try fetchSyncFolders()
        } catch {
            print("Failed to fetch all sync folders: \(error)")
            return []
        }
    }
}
