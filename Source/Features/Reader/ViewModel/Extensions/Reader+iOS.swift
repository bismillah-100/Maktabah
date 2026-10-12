//
//  Reader+iOS.swift
//  Maktabah
//

import Foundation

extension ReaderViewModel {
    func saveCurrentState() {
        if let scroll = fetchScrollPosition?() {
            readerState.scrollPosition = scroll
        }
        if let range = fetchSelectedRange?() {
            readerState.selectedRange = range
        }
    }

    func didSelectTOCNode(id: Int) {
        searchEvent = nil
        annotationEvent = nil
        fetchContentById(id)
    }

    func didSelectSearch(query: String, contentId: Int) {
        searchEvent = ReaderHighlightEvent(
            query: query,
            contentId: contentId,
            mode: searchViewModel.searchMode,
            nearDistance: searchViewModel.nearDistance
        )
        annotationEvent = nil
        fetchContentById(contentId)
    }

    func didSelectAnnotation(_ ann: Annotation) {
        annotationEvent = ReaderAnnotationEvent(annotation: ann)
        searchEvent = nil
        fetchContentById(Int(ann.contentId))
    }
}
