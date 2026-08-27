//
//  GroupedResult.swift
//  Maktabah
//

import Foundation

struct GroupedResult {
    let archive: Int
    let bkId: Int // tableName setelah dropFirst()
    var contentIds: [String] = []
}
