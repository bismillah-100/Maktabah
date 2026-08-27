//
//  ResultNode.swift
//  Maktabah
//

import Foundation
#if canImport(Observation)
import Observation
#endif

#if os(iOS)
@Observable
#endif
class ResultNode: Identifiable, Hashable {
    var id: Int64
    var parentId: Int64?
    var name: String
    var lastModified: Int64?
    var searchMode: Int
    var nearDistance: Int
    let items: [SavedResultsItem]

    init(
        id: Int64,
        parentId: Int64?,
        name: String,
        lastModified: Int64? = nil,
        searchMode: Int = 0,
        nearDistance: Int = 10,
        items: [SavedResultsItem]
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.lastModified = lastModified
        self.searchMode = searchMode
        self.nearDistance = nearDistance
        self.items = items
    }

    static func == (lhs: ResultNode, rhs: ResultNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
