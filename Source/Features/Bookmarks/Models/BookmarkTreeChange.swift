//
//  BookmarkTreeChange.swift
//  Maktabah
//

import Foundation

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
