//
//  OpenBookOptions.swift
//  Maktabah
//
//  Created by Ays on 10/10/26.
//

import Foundation

struct OpenBookOptions {
    var contentId: Int?
    var searchEvent: ReaderHighlightEvent?
    var annotationEvent: ReaderAnnotationEvent?
    var recordHistory: Bool = true

    init(
        contentId: Int? = nil,
        searchEvent: ReaderHighlightEvent? = nil,
        annotationEvent: ReaderAnnotationEvent? = nil,
        recordHistory: Bool = true
    ) {
        self.contentId = contentId
        self.searchEvent = searchEvent
        self.annotationEvent = annotationEvent
        self.recordHistory = recordHistory
    }
}
