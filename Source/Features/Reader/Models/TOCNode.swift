//
//  TOCNode.swift
//  Maktabah
//

import Foundation

final class TOCNode: Identifiable, @unchecked Sendable {
    let bab: String
    let level: Int
    let sub: Int
    let id: Int
    var children: [TOCNode] = []

    var endID: Int = .max

    init(from toc: TOC) {
        bab = toc.bab.convertToArabicDigits()
        level = toc.level
        sub = toc.sub
        id = toc.id
    }
}
