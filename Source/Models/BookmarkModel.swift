//
//  BookmarkModel.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

import Foundation

class FolderNode {
    let id: Int64
    var name: String
    var children: [FolderNode] = []

    init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

class ResultNode {
    var id: Int64
    var parentId: Int64?
    var name: String
    let items: [SavedResultsItem]

    init(id: Int64, parentId: Int64?, name: String, items: [SavedResultsItem]) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.items = items
    }
}

struct GroupedResult {
    let archive: Int
    let bkId: Int // tableName setelah dropFirst()
    var contentIds: [String] = []
}
