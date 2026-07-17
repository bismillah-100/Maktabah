//
//  ZSTDContextWrapper.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 17/07/26.
//

import Foundation

final class ZSTDContextWrapper {
    let dctx: OpaquePointer
    init() { dctx = ZSTD_createDCtx()! }
    deinit { ZSTD_freeDCtx(dctx) }
}
