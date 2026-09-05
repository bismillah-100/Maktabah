//
//  LibraryUpdate.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 05/09/26.
//

import Foundation

enum LibraryUpdate {
    case reloadData
    case reloadItem(Any?, reloadChildren: Bool)
    case expandItem(Any?)
    case scrollRowToVisible(Any)
    case beginUpdates
    case endUpdates
    case removeItems(IndexSet, parent: Any?)
    case insertItems(IndexSet, parent: Any?)
    case moveItem(from: Int, to: Int, parent: Any?)
}
