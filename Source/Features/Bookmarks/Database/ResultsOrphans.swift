//
//  ResultsOrphans.swift
//  Maktabah
//
//  Created by MacBook on 05/12/25.
//

import Foundation
import OSLog

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
            Logger.bookmarks.error("ResultsHandler: Failed to resolve orphan folders: \(error.localizedDescription, privacy: .public)")
        }
    }

    func resolveOrphanResults() {
        do {
            try transaction {
                let updateSql = """
                UPDATE OR IGNORE \(resultsTable)
                SET \(colFolderId) = (SELECT \(colId) FROM \(foldersTable) WHERE \(colCkRecordId) = \(resultsTable).\(colFolderCkRecordId))
                WHERE \(colFolderCkRecordId) IS NOT NULL
                  AND EXISTS (
                      SELECT 1 FROM \(foldersTable) f
                      WHERE f.\(colCkRecordId) = \(resultsTable).\(colFolderCkRecordId)
                      AND COALESCE(\(resultsTable).\(colFolderId), -1) != COALESCE(f.\(colId), -1)
                  );
                """
                try exec(updateSql)

                let deleteSql = """
                DELETE FROM \(resultsTable)
                WHERE \(colFolderCkRecordId) IS NOT NULL
                  AND EXISTS (
                      SELECT 1 FROM \(foldersTable) f
                      WHERE f.\(colCkRecordId) = \(resultsTable).\(colFolderCkRecordId)
                      AND COALESCE(\(resultsTable).\(colFolderId), -1) != COALESCE(f.\(colId), -1)
                  );
                """
                try exec(deleteSql)
            }
        } catch {
            Logger.bookmarks.error("ResultsHandler: Failed to resolve orphan results: \(error.localizedDescription, privacy: .public)")
        }
    }
}
