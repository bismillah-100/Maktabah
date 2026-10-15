//
//  ByteCountFormat.swift
//  Maktabah
//
//  Created by Ays on 15/10/26.
//

import Foundation

extension BinaryInteger {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
