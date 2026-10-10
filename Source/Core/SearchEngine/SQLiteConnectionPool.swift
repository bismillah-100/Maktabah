//
//  SQLiteConnectionPool.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//


import Foundation
import SQLite3

actor SQLiteConnectionPool {
    private var connections: [DBConnectionType]

    init(conns: [DBConnectionType]) {
        connections = conns
    }

    var connectionCount: Int {
        connections.count
    }

    /// Ambil koneksi berdasarkan index
    func getConnection(at index: Int) -> DBConnectionType? {
        guard !connections.isEmpty else { return nil }
        return connections[abs(index) % connections.count]
    }

    /// Interrupt all connections in pool
    func interruptAll() {
        for conn in connections {
            conn.interrupt()
        }
    }

    /// Menjalankan read-operation pada koneksi tertentu
    func read<T: Sendable>(at index: Int, _ body: @escaping @Sendable (DBConnectionType) throws -> T) async throws -> T {
        guard let conn = getConnection(at: index) else {
            throw NSError(
                domain: "SQLiteConnectionPool",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No database connections available in pool"]
            )
        }
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { try body(conn) }.value
        } onCancel: {
            conn.interrupt()
        }
    }
}
