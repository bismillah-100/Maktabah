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
        searchText = ""
        targetAnnotation = nil
        fetchContentById(id)
    }

    func didSelectSearch(query: String, contentId: Int) {
        searchText = query
        searchMode = searchViewModel.searchMode
        nearDistance = searchViewModel.nearDistance
        fetchContentById(contentId)
    }

    func didSelectAnnotation(_ ann: Annotation) {
        targetAnnotation = ann
        fetchContentById(Int(ann.contentId))
    }
}
