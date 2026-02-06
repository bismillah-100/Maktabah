//
//  StringInterner.swift
//  Data SDI
//
//  Created by MacBook on 02/07/25.
//

import Foundation

/// StringInterner untuk berbagi instance string yang sama.
/// Thread-safe, ringan, dan mendukung multi-thread access.
public final class StringInterner {
    /// Pool untuk menyimpan string interned.
    private var pool: [String: String] = [:]

    /// Lock agar thread-safe.
    private let lock: NSLock = .init()

    /// Shared singleton instance.
    public static let shared: StringInterner = .init()

    /// Private init untuk mencegah instance di luar.
    private init() {}

    /// Mengintern string. Jika string sudah ada, kembalikan pointer yang sama.
    /// - Parameter value: String yang akan diintern.
    /// - Returns: String yang telah diintern.
    public func intern(_ value: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = pool[value] {
            return existing
        } else {
            pool[value] = value
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
