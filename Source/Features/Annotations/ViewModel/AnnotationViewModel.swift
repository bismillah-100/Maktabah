//
//  AnnotationViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 19/06/26.
//

import Combine
import Foundation
import OSLog
import SwiftUI

enum AnnotationSearchScope: Int, CaseIterable, Identifiable {
    case all = 0
    case book = 1
    case context = 2
    case note = 3
    case tag = 4

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .all: String(localized: .Annotation.searchScopeAll)
        case .book: String(localized: .Annotation.searchScopeBook)
        case .context: String(localized: .Annotation.searchScopeContext)
        case .note: String(localized: .Annotation.searchScopeNote)
        case .tag: String(localized: .Annotation.searchScopeTag)
        }
    }
}

struct SwiftUIAnnotationNode: Identifiable {
    let id: String
    let title: String
    let kind: AnnotationNodeKind
    let annotation: Annotation?
    let bookTitle: String?
    var children: [SwiftUIAnnotationNode]?

    init(
        id: String,
        title: String,
        kind: AnnotationNodeKind,
        annotation: Annotation?,
        bookTitle: String? = nil,
        children: [SwiftUIAnnotationNode]? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.annotation = annotation
        self.bookTitle = bookTitle
        self.children = children
    }

    static func id(from node: AnnotationNode) -> String {
        if node.kind == .annotation, let ann = node.annotation, let annId = ann.id {
            return "ann-\(annId)"
        }
        return "group-\(node.kind)-\(node.title)"
    }

    /// Convert the core AppKit/Foundation AnnotationNode to SwiftUI identifiable node
    init(from node: AnnotationNode, parentId: String? = nil) {
        let baseId = SwiftUIAnnotationNode.id(from: node)
        id = (parentId != nil && node.kind == .annotation) ? "\(parentId!)-\(baseId)" : baseId
        title = node.title
        kind = node.kind
        annotation = node.annotation
        bookTitle = node.bookTitle
        let currentId = id
        children = node.children.isEmpty ? nil : node.children.map { SwiftUIAnnotationNode(from: $0, parentId: currentId) }
    }
}

@Observable
class AnnotationViewModel: ViewModelBase {
    var state: ViewModelState = .loading

    /// Cache untuk pencarian dan filter buku
    private var cachedFilteredNodes: [AnnotationNode]?

    /// Core AppKit/Foundation tree (Computed property)
    var filteredNodes: [AnnotationNode] {
        if let cached = cachedFilteredNodes {
            return cached
        }
        return AnnotationTreeBuilder.shared.currentRootNode()?.children ?? []
    }

    /// SwiftUI tree
    var swiftUINodes: [SwiftUIAnnotationNode] {
        filteredNodes.map { SwiftUIAnnotationNode(from: $0) }
    }

    private var searchTask: Task<Void, Never>?
    var searchText: String = "" {
        didSet {
            guard oldValue != searchText else { return }
            searchTask?.cancel()
            searchTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                self?.applyFilter()
            }
        }
    }

    var searchScope: AnnotationSearchScope = .all {
        didSet {
            guard oldValue != searchScope else { return }
            if !searchText.isEmpty {
                applyFilter()
            }
        }
    }

    var groupingMode: AnnotationGroupingMode = UserDefaults.standard.selectedAnnGroupingMode {
        didSet {
            guard oldValue != groupingMode else { return }
            state = .loading
            UserDefaults.standard.selectedAnnGroupingMode = groupingMode
            AnnotationTreeBuilder.shared.updateGroupingMode(groupingMode)
        }
    }

    var sortField: AnnotationSortField = UserDefaults.standard.selectedAnnSortField {
        didSet {
            guard oldValue != sortField else { return }
            state = .loading
            UserDefaults.standard.selectedAnnSortField = sortField
            AnnotationTreeBuilder.shared.updateSorting(field: sortField, isAscending: sortAscending)
        }
    }

    var sortAscending: Bool = UserDefaults.standard.selectedAnnAscending {
        didSet {
            guard oldValue != sortAscending else { return }
            state = .loading
            UserDefaults.standard.selectedAnnAscending = sortAscending
            AnnotationTreeBuilder.shared.updateSorting(field: sortField, isAscending: sortAscending)
        }
    }

    // MARK: - Tag Filtering

    var selectedTags: Set<String> = [] {
        didSet {
            guard oldValue != selectedTags else { return }
            applyFilter()
        }
    }

    var tagFilterMode: TagFilterMode = .or {
        didSet {
            guard oldValue != tagFilterMode else { return }
            if !selectedTags.isEmpty {
                applyFilter()
            }
        }
    }

    /// All unique tag names from annotation store
    var allTags: [String] {
        AnnotationStore.shared.allTagNames()
    }

    /// Tags that are relevant based on current filter mode and selections.
    /// In AND mode with active selections, only tags that co-occur in the matching annotations are returned.
    var availableTags: [String] {
        availableTags(for: selectedTags)
    }

    func availableTags(for tags: Set<String>) -> [String] {
        guard let root = AnnotationTreeBuilder.shared.currentRootNode() else {
            return allTags
        }
        return AnnotationTreeFilter.availableTags(
            for: tags,
            in: root.children,
            allTags: allTags,
            mode: tagFilterMode
        )
    }

    var onTagsChanged: (@MainActor ([String]) -> Void)?

    // MARK: - Update Callbacks

    /// Controller implements these to apply changes
    var onIncrementalUpdate: (@MainActor (AnnotationTreeDiff) -> Void)? {
        didSet {
            flushBufferedDiffs()
        }
    }

    var onTreeUpdate: (@MainActor ([AnnotationNode], AnnotationGroupingMode) -> Void)?

    private var bufferedDiffs: [AnnotationTreeDiff] = []
    private var diffObserverTask: Task<Void, Never>?

    deinit {
        MainActor.assumeIsolated {
            diffObserverTask?.cancel()
            diffObserverTask = nil
        }
    }

    override init() {
        super.init()

        diffObserverTask = Task { @MainActor [weak self] in
            for await diff in AnnotationTreeBuilder.shared.diffPublisher.values {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                handleTreeDiff(diff)
            }
        }

        if AnnotationTreeBuilder.shared.currentRootNode() != nil {
            reloadFromTree()
            state = .loaded
        }
    }

    private func handleTreeDiff(_ diff: AnnotationTreeDiff?) {
        guard let diff else {
            reloadFromTree()
            onTreeUpdate?(filteredNodes, groupingMode)
            state = .loaded
            return
        }

        onTagsChanged?(availableTags)

        if !searchText.isEmpty || !selectedTags.isEmpty {
            applyFilter()
            return
        }

        // Check if annotation belongs to a missing book
        if UserDefaults.standard.hideMissingBookAnnotations {
            let targetAnn = diff.annotation ?? diff.annotationId.flatMap { AnnotationStore.shared.loadAnnotationById($0) }
            if let bkId = targetAnn?.bkId, LibraryDataManager.shared.getBook([bkId]).isEmpty {
                return
            }
        }

        if let callback = onIncrementalUpdate {
            callback(diff)
        } else {
            bufferedDiffs.append(diff)
        }
    }

    private func flushBufferedDiffs() {
        guard let callback = onIncrementalUpdate else { return }
        for diff in bufferedDiffs {
            callback(diff)
        }
        bufferedDiffs.removeAll()
    }

    func loadAnnotations() async {
        AnnotationTreeBuilder.shared.updateGroupingMode(groupingMode)
        AnnotationTreeBuilder.shared.updateSorting(field: sortField, isAscending: sortAscending)
        reloadFromTree()
    }

    func applyFilter() {
        reloadFromTree()
        onTreeUpdate?(filteredNodes, groupingMode)
    }

    func renameTag(from oldName: String, to newName: String) throws {
        try AnnotationStore.shared.renameTag(from: oldName, to: newName)
        if let match = selectedTags.first(where: { $0.caseInsensitiveCompare(oldName) == .orderedSame }) {
            var updated = selectedTags
            updated.remove(match)
            updated.insert(newName)
            selectedTags = updated
        }
    }

    func deleteTag(named tagName: String) throws {
        try AnnotationStore.shared.deleteTag(named: tagName)
        if let match = selectedTags.first(where: { $0.caseInsensitiveCompare(tagName) == .orderedSame }) {
            selectedTags.remove(match)
        }
    }

    private func reloadFromTree() {
        guard let coreNodes = AnnotationTreeBuilder.shared.currentRootNode()?.children else { return }

        let currentAllTags = Set(allTags)
        let validSelected = selectedTags.filter { currentAllTags.contains($0) }
        if validSelected != selectedTags {
            selectedTags = validSelected
            return
        }

        let isFiltered = !selectedTags.isEmpty || !searchText.isEmpty
        if isFiltered {
            cachedFilteredNodes = AnnotationTreeFilter.filter(
                nodes: coreNodes,
                selectedTags: selectedTags,
                tagFilterMode: tagFilterMode,
                searchText: searchText,
                searchScope: searchScope
            )
        } else {
            cachedFilteredNodes = nil
        }

        let currentTags = availableTags
        onTagsChanged?(currentTags)
    }

    func deleteAnnotation(id: Int64) {
        do {
            try AnnotationStore.shared.deleteAnnotation(id: id)
        } catch {
            Logger.annotations.error("Failed to delete annotation: \(error.localizedDescription, privacy: .public)")
        }
    }

    func toggleTagSelection(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func toggleTagFilterMode() {
        tagFilterMode = tagFilterMode == .or ? .and : .or
    }
}

extension UserDefaults {
    @objc dynamic var hideMissingBookAnnotations: Bool {
        get { bool(forKey: "hideMissingBookAnnotations") }
        set { set(newValue, forKey: "hideMissingBookAnnotations") }
    }
}
