//
//  SavedResultsItem.swift
//  Maktabah
//

import Foundation

struct SavedResultsItem {
    let archive: String
    let tableName: String
    let query: String
    let bookId: Int
    let bookTitle: String
    var searchMode: Int = 0
    var nearDistance: Int = 10
}
