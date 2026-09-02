//
//  FolderNode.swift
//  Maktabah
//

import Foundation
import Observation

@Observable
class FolderNode: Identifiable, Hashable {
    let id: Int64
    var name: String
    var lastModified: Int64?
    var children: [FolderNode] = []

    init(id: Int64, name: String, lastModified: Int64? = nil) {
        self.id = id
        self.name = name
        self.lastModified = lastModified
    }

    static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var allDescendantIds: [Int64] {
        var ids: [Int64] = []
        collectDescendantIds(into: &ids)
        return ids
    }

    private func collectDescendantIds(into ids: inout [Int64]) {
        ids.append(id)
        for child in children {
            child.collectDescendantIds(into: &ids)
        }
    }
}
