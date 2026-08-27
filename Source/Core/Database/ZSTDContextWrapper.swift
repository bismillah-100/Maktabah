//
//  ZSTDContextWrapper.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 17/07/26.
//

import Foundation

final class ZSTDContextWrapper: @unchecked Sendable {
    let dctx: OpaquePointer
    init?() {
        guard let ctx = ZSTD_createDCtx() else { return nil }
        dctx = ctx
    }

    deinit { ZSTD_freeDCtx(dctx) }
}

final class ZSTDContextPool: @unchecked Sendable {
    static let shared = ZSTDContextPool()
    private var pool: [ZSTDContextWrapper] = []
    private let lock = NSLock()

    func get() -> ZSTDContextWrapper? {
        lock.lock()
        defer { lock.unlock() }
        if !pool.isEmpty {
            return pool.removeLast()
        }
        return ZSTDContextWrapper()
    }

    func release(_ wrapper: ZSTDContextWrapper) {
        lock.lock()
        defer { lock.unlock() }
        pool.append(wrapper)
    }
}
