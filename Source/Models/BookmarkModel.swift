//
//  BookmarkModel.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

#if os(iOS)
@Observable
#endif
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
}

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

struct GroupedResult {
    let archive: Int
    let bkId: Int // tableName setelah dropFirst()
    var contentIds: [String] = []
}

enum BookmarkTreeChange {
    case fullReload
    case insertFolder(folder: FolderNode, parent: FolderNode?, index: Int)
    case removeFolder(folder: FolderNode, parent: FolderNode?, index: Int)
    case updateFolder(folder: FolderNode)
    case moveFolder(folder: FolderNode, oldParent: FolderNode?, oldIndex: Int, newParent: FolderNode?, newIndex: Int)
    
    case insertResult(result: ResultNode, parentId: Int64?, index: Int)
    case removeResult(result: ResultNode, parentId: Int64?, index: Int)
    case updateResult(result: ResultNode)
    case moveResult(result: ResultNode, oldParentId: Int64?, oldIndex: Int, newParentId: Int64?, newIndex: Int)
}
