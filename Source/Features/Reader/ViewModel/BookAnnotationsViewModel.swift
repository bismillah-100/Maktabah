//
//  BookAnnotationsViewModel.swift
//  Maktabah
//
//  Created by Antigravity on 19/10/26.
//

import Combine
import Foundation
import Observation

@Observable @MainActor
final class BookAnnotationsViewModel {
    var bookId: Int?
    var bookAnnotations: [Annotation] = []
    var searchText: String = ""
    var scrollPositionId: Int64?
    private(set) var hasLoaded: Bool = false

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    var filteredAnnotations: [Annotation] {
        if searchText.isEmpty {
            return bookAnnotations
        } else {
            let query = searchText.normalizeArabic(false)
            return bookAnnotations.filter { ann in
                ann.context.normalizeArabic(false).localizedStandardContains(query) ||
                    (ann.note?.normalizeArabic(false).localizedStandardContains(query) == true)
            }
        }
    }

    init(bookId: Int? = nil) {
        self.bookId = bookId
        setupObserver()
    }

    private func setupObserver() {
        AnnotationStore.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let id = bookId else { return }
                loadBookAnnotations(bookId: id)
            }
            .store(in: &cancellables)
    }

    func loadBookAnnotations(bookId: Int) {
        self.bookId = bookId
        if let bookNode = AnnotationTreeBuilder.shared.currentRootNode()?.children.first(
            where: {
                $0.kind == .book
                    && $0.children.first?.annotation?.bkId == bookId
            }
        ) {
            bookAnnotations = bookNode.children.compactMap(\.annotation)
        } else {
            bookAnnotations = AnnotationStore.shared.loadAnnotations(bkId: bookId)
        }
        hasLoaded = true
    }

    func updateAnnotation(_ updated: Annotation) throws {
        try AnnotationStore.shared.updateAnnotation(updated)
    }

    func deleteAnnotation(_ annotation: Annotation) throws {
        guard let id = annotation.id else { return }
        try AnnotationStore.shared.deleteAnnotation(id: id)
    }
}
