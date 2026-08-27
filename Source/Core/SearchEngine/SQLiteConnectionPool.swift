//
//  SQLiteConnectionPool.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//


import Foundation
import SQLite3

class SQLiteConnectionPool {
    private var connections: [DBConnectionType]

    init(conns: [DBConnectionType]) {
        connections = conns
    }

    var connectionCount: Int {
        connections.count
    }

    /// Ambil koneksi berdasarkan index
    func getConnection(at index: Int) -> DBConnectionType {
        connections[index % connections.count]
    }

    /// Menjalankan read-operation pada koneksi tertentu
    func read<T>(at index: Int, _ body: @escaping (DBConnectionType) throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            let conn = self.getConnection(at: index)
            return try body(conn)
        }.value
    }
}
