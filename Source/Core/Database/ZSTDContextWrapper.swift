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

