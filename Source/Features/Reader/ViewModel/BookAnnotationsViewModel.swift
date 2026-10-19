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
    var filteredAnnotations: [Annotation] = []
    var scrollPositionId: Int64?
    private(set) var hasLoaded: Bool = false

    private var searchDebounceTask: Task<Void, Never>?

    var searchText: String = "" {
        didSet {
            guard oldValue != searchText else { return }
            searchDebounceTask?.cancel()
            if searchText.isEmpty {
                filteredAnnotations = bookAnnotations
            } else {
                searchDebounceTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled else { return }
                    self?.filterAnnotations(with: self?.searchText ?? "")
                }
            }
        }
    }

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    init(bookId: Int? = nil) {
        self.bookId = bookId
        setupObserver()
    }

    private func setupObserver() {
        AnnotationStore.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let id = bookId else { return }
                Task {
                    await self.loadBookAnnotations(bookId: id)
                }
            }
            .store(in: &cancellables)
    }

    func loadBookAnnotations(bookId: Int) async {
        self.bookId = bookId
        let anns: [Annotation] = await Task.detached(priority: .userInitiated) {
            if let bookNode = AnnotationTreeBuilder.shared.currentRootNode()?.children.first(where: {
                $0.kind == .book && $0.children.first?.annotation?.bkId == bookId
            }) {
                return bookNode.children.compactMap(\.annotation)
            } else {
                return AnnotationStore.shared.loadAnnotations(bkId: bookId)
            }
        }.value

        self.bookAnnotations = anns
        self.filterAnnotations(with: self.searchText)
        self.hasLoaded = true
    }

    private func filterAnnotations(with query: String) {
        guard !query.isEmpty else {
            filteredAnnotations = bookAnnotations
            return
        }
        let normalizedQuery = query.normalizeArabic(false)
        filteredAnnotations = bookAnnotations.filter { ann in
            ann.context.normalizeArabic(false).localizedStandardContains(normalizedQuery) ||
                (ann.note?.normalizeArabic(false).localizedStandardContains(normalizedQuery) == true)
        }
    }
}
