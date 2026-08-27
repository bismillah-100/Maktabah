//
//  BookContent.swift
//  Maktabah
//

import Foundation

class BookContent {
    let id: Int
    let nash: String
    let page: Int
    let part: Int

    var surah: Int?
    var aya: Int?

    init(id: Int, nash: String, page: Int = 1, part: Int = 1) {
        self.id = id
        self.nash = nash
        self.page = page
        self.part = part
    }
}
