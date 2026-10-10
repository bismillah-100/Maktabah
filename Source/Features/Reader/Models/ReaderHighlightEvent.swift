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
    
    init(
        query: String,
        contentId: Int? = nil,
        mode: SearchMode? = nil,
        nearDistance: Int = 10,
        id: UUID = UUID()
    ) {
        self.id = id
        self.query = query
        self.contentId = contentId
        self.mode = mode
        self.nearDistance = nearDistance
    }
}
