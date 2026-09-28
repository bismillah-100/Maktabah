//
//  StringInterner.swift
//  Data SDI
//
//  Created by MacBook on 02/07/25.
//

import Foundation
import Synchronization

/// StringInterner untuk berbagi instance string yang sama.
/// Thread-safe, ringan, dan mendukung multi-thread access.
public final class StringInterner: Sendable {
    /// Pool untuk menyimpan string interned.
    private let pool: Mutex<[String: String]> = .init([:])

    /// Shared singleton instance.
    public static let shared: StringInterner = .init()

    /// Private init untuk mencegah instance di luar.
    private init() {}

    /// Mengintern string. Jika string sudah ada, kembalikan pointer yang sama.
    /// - Parameter value: String yang akan diintern.
    /// - Returns: String yang telah diintern.
    public func intern(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        return pool.withLock { dict in
            if let existing = dict[value] {
                return existing
            }
            dict[value] = value
            return value
        }
    }

    /// Total string unik yang diintern.
    /*
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return pool.count
    }

    /// Hapus semua string yang diintern (optional).
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        pool.removeAll()
    }
     */
}
