//
//  SyncPendingStore.swift
//  Maktabah
//

import Foundation

struct SyncPendingStore {
    static let tableName = "sync_pending"

    static let createTableSQL = """
    CREATE TABLE IF NOT EXISTS sync_pending (
        ck_record_id TEXT PRIMARY KEY,
        operation TEXT NOT NULL CHECK(operation IN ('upload', 'delete')),
        queued_at INTEGER NOT NULL
    );
    """

    static let createIndexSQL = "CREATE INDEX IF NOT EXISTS idx_sync_pending_op_queued ON sync_pending (operation, queued_at);"

    private let db: SQLiteDatabase

    init(database: SQLiteDatabase) {
        db = database
    }

    func createTable() throws {
        try db.execute(query: Self.createTableSQL)
        try db.execute(query: Self.createIndexSQL)
    }

    func addPendingSync(ckRecordId: String, operation: String) throws {
        if operation == "upload" {
            let count = try db.fetch(
                query: "SELECT COUNT(*) FROM sync_pending WHERE ck_record_id = ? AND operation = 'delete';",
                parameters: [ckRecordId]
            ) { $0.int64(at: 0) }.first ?? 0
            if count > 0 { return } // Delete wins
        } else if operation == "delete" {
            try db.execute(
                query: "DELETE FROM sync_pending WHERE ck_record_id = ? AND operation = 'upload';",
                parameters: [ckRecordId]
            )
        }
        let now = Int64(Date().timeIntervalSince1970)
        try db.execute(
            query: "INSERT OR REPLACE INTO sync_pending (ck_record_id, operation, queued_at) VALUES (?, ?, ?);",
            parameters: [ckRecordId, operation, now]
        )
    }

    func removePendingSync(ckRecordIds: [String]) {
        guard !ckRecordIds.isEmpty else { return }
        for chunk in ckRecordIds.chunked(into: 500) {
            let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
            try? db.execute(
                query: "DELETE FROM sync_pending WHERE ck_record_id IN (\(placeholders));",
                parameters: chunk
            )
        }
    }

    func fetchPendingSync(operation: String) -> [String] {
        (try? db.fetch(
            query: "SELECT ck_record_id FROM sync_pending WHERE operation = ? ORDER BY queued_at ASC;",
            parameters: [operation]
        ) { $0.string(at: 0) ?? "" }) ?? []
    }
}

protocol SyncPendingManaging: AnyObject {
    var syncPendingStore: SyncPendingStore? { get }
}

extension SyncPendingManaging {
    func addPendingSync(ckRecordId: String, operation: String) throws {
        try syncPendingStore?.addPendingSync(ckRecordId: ckRecordId, operation: operation)
    }

    func removePendingSync(ckRecordIds: [String]) {
        syncPendingStore?.removePendingSync(ckRecordIds: ckRecordIds)
    }

    func fetchPendingSync(operation: String) -> [String] {
        syncPendingStore?.fetchPendingSync(operation: operation) ?? []
    }
}
