//
//  ReaderHighlightEvent.swift
//  Maktabah
//
//  Created by Ays on 10/10/26.
//

import Foundation

struct ReaderHighlightEvent: Equatable {
    let id: UUID
    let query: String
    let contentId: Int?
    let mode: SearchMode?
    let nearDistance: Int
    let isTOC: Bool
    
    init(
        query: String,
        contentId: Int? = nil,
        mode: SearchMode? = nil,
        nearDistance: Int = 10,
        isTOC: Bool = false,
        id: UUID = UUID()
    ) {
        self.id = id
        self.query = query
        self.contentId = contentId
        self.mode = mode
        self.nearDistance = nearDistance
        self.isTOC = isTOC
    }
}
