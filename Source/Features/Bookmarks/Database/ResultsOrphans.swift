//
//  ResultsOrphans.swift
//  Maktabah
//
//  Created by MacBook on 05/12/25.
//

import Foundation

extension ResultsHandler {
    func resolveOrphanFolders() {
        guard let db else { return }
        do {
            try transaction {
                let sql = """
                SELECT f1.\(colId), f1.\(colName), f1.\(colParentCkRecordId), f2.\(colId) as expected_parent
                FROM \(foldersTable) f1
                LEFT JOIN \(foldersTable) f2 ON f1.\(colParentCkRecordId) = f2.\(colCkRecordId)
                WHERE f1.\(colParentCkRecordId) IS NOT NULL 
                AND COALESCE(f1.\(colParent), -1) != COALESCE(f2.\(colId), -1)
                """

                struct OrphanFolderRow {
                    let id: Int64
                    let name: String
                    let expectedParent: Int64?
                }

                let orphans = try db.fetch(query: sql) { row -> OrphanFolderRow in
                    OrphanFolderRow(
                        id: row.int64(at: 0),
                        name: row.string(at: 1) ?? "",
                        expectedParent: !row.isNull(at: 3) ? row.int64(at: 3) : nil
                    )
                }

                for orphan in orphans {
                    guard let newParentId = orphan.expectedParent else { continue }

                    let conflictSql = "SELECT \(colId) FROM \(foldersTable) WHERE \(colParent) = ? AND \(colName) = ? AND \(colId) != ? LIMIT 1"
                    if let conflictId = try db.fetch(query: conflictSql, parameters: [newParentId, orphan.name, orphan.id], mapping: { $0.int64(at: 0) }).first {
                        try exec("UPDATE \(resultsTable) SET \(colFolderId) = ? WHERE \(colFolderId) = ?;", parameters: [conflictId, orphan.id])
                        try exec("UPDATE \(foldersTable) SET \(colParent) = ? WHERE \(colParent) = ?;", parameters: [conflictId, orphan.id])
                        try exec("DELETE FROM \(foldersTable) WHERE \(colId) = ?;", parameters: [orphan.id])
                    } else {
                        try exec("UPDATE \(foldersTable) SET \(colParent) = ? WHERE \(colId) = ?;", parameters: [newParentId, orphan.id])
                    }
                }
            }
        } catch {
            print("ResultsHandler: Failed to resolve orphan folders - \(error)")
        }
    }

    func resolveOrphanResults() {
        guard let db else { return }
        do {
            try transaction {
                let sql = """
                SELECT r.\(colId), r.\(colName), r.\(colBkId), f.\(colId) as expected_folder
                FROM \(resultsTable) r
                LEFT JOIN \(foldersTable) f ON r.\(colFolderCkRecordId) = f.\(colCkRecordId)
                WHERE r.\(colFolderCkRecordId) IS NOT NULL
                AND COALESCE(r.\(colFolderId), -1) != COALESCE(f.\(colId), -1)
                """

                struct OrphanResultRow {
                    let id: Int64
                    let name: String
                    let bkId: Int
                    let expectedFolder: Int64?
                }

                let orphans = try db.fetch(query: sql) { row -> OrphanResultRow in
                    OrphanResultRow(
                        id: row.int64(at: 0),
                        name: row.string(at: 1) ?? "",
                        bkId: row.int(at: 2),
                        expectedFolder: !row.isNull(at: 3) ? row.int64(at: 3) : nil
                    )
                }

                for orphan in orphans {
                    guard let newFolderId = orphan.expectedFolder else { continue }

                    let conflictSql = "SELECT \(colId) FROM \(resultsTable) WHERE \(colFolderId) = ? AND \(colName) = ? AND \(colBkId) = ? AND \(colId) != ? LIMIT 1"
                    if let _ = try db.fetch(query: conflictSql, parameters: [newFolderId, orphan.name, orphan.bkId, orphan.id], mapping: { $0.int64(at: 0) }).first {
                        try exec("DELETE FROM \(resultsTable) WHERE \(colId) = ?;", parameters: [orphan.id])
                    } else {
                        try exec("UPDATE \(resultsTable) SET \(colFolderId) = ? WHERE \(colId) = ?;", parameters: [newFolderId, orphan.id])
                    }
                }
            }
        } catch {
            print("ResultsHandler: Failed to resolve orphan results - \(error)")
        }
    }
}
