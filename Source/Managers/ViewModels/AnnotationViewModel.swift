//
//  AnnotationViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 19/06/26.
//

import Combine
import Foundation
import SwiftUI

enum AnnotationSearchScope: Int, Sendable, CaseIterable, Identifiable {
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
        case .all: "All".localized
        case .book: "Book".localized
        case .context: "Context".localized
        case .note: "Note".localized
        case .tag: "Tag".localized
        }
    }
}

struct SwiftUIAnnotationNode: Identifiable {
    let id: String
    let title: String
    let kind: AnnotationNodeKind
    let annotation: Annotation?
    var children: [SwiftUIAnnotationNode]?

    init(
        id: String,
        title: String,
        kind: AnnotationNodeKind,
        annotation: Annotation?,
        children: [SwiftUIAnnotationNode]? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.annotation = annotation
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
        let currentId = id
        children = node.children.isEmpty ? nil : node.children.map { SwiftUIAnnotationNode(from: $0, parentId: currentId) }
    }
}

@MainActor
#if os(iOS)
@Observable
#endif
class AnnotationViewModel: ViewModelBase, @unchecked Sendable {
    var state: ViewModelState = .loading

    /// Cache untuk pencarian dan filter buku
    private var cachedFilteredNodes: [AnnotationNode]?

    /// Core AppKit/Foundation tree (Computed property)
    var filteredNodes: [AnnotationNode] {
        if let cached = cachedFilteredNodes {
            return cached
        }
        return AnnotationManager.shared.rootNode?.children ?? []
    }

    /// SwiftUI tree
    var swiftUINodes: [SwiftUIAnnotationNode] {
        filteredNodes.map { SwiftUIAnnotationNode(from: $0) }
    }

    var searchText: String = "" {
        didSet {
            if oldValue != searchText {
                searchSubject.send(searchText)
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

    private let searchSubject = PassthroughSubject<String, Never>()

    var groupingMode: AnnotationGroupingMode = UserDefaults.standard.selectedAnnGroupingMode {
        didSet {
            guard oldValue != groupingMode else { return }
            state = .loading
            UserDefaults.standard.selectedAnnGroupingMode = groupingMode
            AnnotationManager.shared.updateGroupingMode(groupingMode)
        }
    }

    var sortField: AnnotationSortField = UserDefaults.standard.selectedAnnSortField {
        didSet {
            guard oldValue != sortField else { return }
            state = .loading
            UserDefaults.standard.selectedAnnSortField = sortField
            AnnotationManager.shared.updateSorting(field: sortField, isAscending: sortAscending)
        }
    }

    var sortAscending: Bool = UserDefaults.standard.selectedAnnAscending {
        didSet {
            guard oldValue != sortAscending else { return }
            state = .loading
            UserDefaults.standard.selectedAnnAscending = sortAscending
            AnnotationManager.shared.updateSorting(field: sortField, isAscending: sortAscending)
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

    /// All unique tag names from annotation manager
    var allTags: [String] {
        AnnotationManager.shared.allTagNames()
    }

    /// Tags that are relevant based on current filter mode and selections.
    /// In AND mode with active selections, only tags that co-occur in the matching annotations are returned.
    var availableTags: [String] {
        availableTags(for: selectedTags)
    }

    func availableTags(for tags: Set<String>) -> [String] {
        guard tagFilterMode == .and, !tags.isEmpty,
              let root = AnnotationManager.shared.rootNode
        else {
            return allTags
        }

        var coOccurringTags = Set(tags)
        let matchingNodes = filterNodesByTags(root.children, tags: tags)
        gatherTags(from: matchingNodes, into: &coOccurringTags)
        return coOccurringTags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var onTagsChanged: (([String]) -> Void)?

    // MARK: - Update Callbacks

    /// Controller implements these to apply changes
    var onIncrementalUpdate: ((AnnotationChangeType, [AnyHashable: Any]) -> Void)? {
        didSet {
            flushBufferedNotifications()
        }
    }

    var onTreeUpdate: (([AnnotationNode], AnnotationGroupingMode) -> Void)?

    private var bufferedNotifications: [(
        changeType: AnnotationChangeType,
        userInfo: [AnyHashable: Any]
    )] = []

    override init() {
        super.init()
        Task { @MainActor in
            searchSubject
                .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    self?.applyFilter()
                }
                .store(in: &cancellables)
        }

        addObserver(
            forName: .annotationTreeDidUpdate,
            object: nil,
            queue: .current
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                reloadFromManager()
                onTreeUpdate?(filteredNodes, groupingMode)
                state = .loaded
            }
        }

        addObserver(
            forName: .annotationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAnnotationChange(notification)
            }
        }
    }

    private func handleAnnotationChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawType = userInfo[AnnotationNotificationKeys.changeType] as? String,
              let changeType = AnnotationChangeType(rawValue: rawType)
        else { return }

        onTagsChanged?(availableTags)

        if !searchText.isEmpty || !selectedTags.isEmpty {
            applyFilter()
            return
        }

        // Cek apakah anotasi yang diupdate merujuk ke buku yang tidak ada
        // Jika tidak ada, cukup abaikan agar UI tetap sesuai filter.
        if UserDefaults.standard.hideMissingBookAnnotations,
           let annotationId = userInfo[AnnotationNotificationKeys.annotationId] as? Int64,
           let annotation = AnnotationManager.shared.loadAnnotationById(annotationId),
           LibraryDataManager.shared.getBook([annotation.bkId]).isEmpty
        {
            return
        }

        if let callback = onIncrementalUpdate {
            callback(changeType, userInfo)
        } else {
            bufferedNotifications.append((changeType, userInfo))
        }
    }

    private func flushBufferedNotifications() {
        guard let callback = onIncrementalUpdate else { return }
        for (changeType, userInfo) in bufferedNotifications {
            callback(changeType, userInfo)
        }
        bufferedNotifications.removeAll()
    }

    func loadAnnotations() async {
        Task.detached { [weak self] in
            guard let self else { return }
            await AnnotationManager.shared.updateGroupingMode(groupingMode)
            await AnnotationManager.shared.updateSorting(field: sortField, isAscending: sortAscending)
            await reloadFromManager()
        }
    }

    func applyFilter() {
        reloadFromManager()
        onTreeUpdate?(filteredNodes, groupingMode)
    }

    func renameTag(from oldName: String, to newName: String) throws {
        try AnnotationManager.shared.renameTag(from: oldName, to: newName)
        if let match = selectedTags.first(where: { $0.caseInsensitiveCompare(oldName) == .orderedSame }) {
            var updated = selectedTags
            updated.remove(match)
            updated.insert(newName)
            selectedTags = updated
        }
    }

    func deleteTag(named tagName: String) throws {
        try AnnotationManager.shared.deleteTag(named: tagName)
        if let match = selectedTags.first(where: { $0.caseInsensitiveCompare(tagName) == .orderedSame }) {
            selectedTags.remove(match)
        }
    }

    private func reloadFromManager() {
        guard let coreNodes = AnnotationManager.shared.rootNode?.children else { return }

        let currentAllTags = Set(allTags)
        let validSelected = selectedTags.filter { currentAllTags.contains($0) }
        if validSelected != selectedTags {
            selectedTags = validSelected
            return
        }

        var isFiltered = false
        var nodes = coreNodes

        if !selectedTags.isEmpty {
            nodes = filterNodesByTags(nodes)
            isFiltered = true
        }

        if !searchText.isEmpty {
            nodes = filterNodes(nodes, with: searchText)
            isFiltered = true
        }

        if isFiltered {
            cachedFilteredNodes = nodes
        } else {
            cachedFilteredNodes = nil
        }

        let currentTags = availableTags
        onTagsChanged?(currentTags)
    }

    private func filterOutMissingBooks(from nodes: [AnnotationNode]) -> [AnnotationNode] {
        var uniqueBkIds: Set<Int> = []
        gatherBkIds(from: nodes, into: &uniqueBkIds)
        let existingBkIds = uniqueBkIds.filter { !LibraryDataManager.shared.getBook([$0]).isEmpty }
        return applyBookFilter(from: nodes, existingBkIds: existingBkIds)
    }

    private func gatherBkIds(from nodes: [AnnotationNode], into set: inout Set<Int>) {
        for node in nodes {
            if node.kind == .annotation, let ann = node.annotation {
                set.insert(ann.bkId)
            } else {
                gatherBkIds(from: node.children, into: &set)
            }
        }
    }

    private func applyBookFilter(from nodes: [AnnotationNode], existingBkIds: Set<Int>) -> [AnnotationNode] {
        var result: [AnnotationNode] = []
        for node in nodes {
            if node.kind == .annotation, let ann = node.annotation {
                if existingBkIds.contains(ann.bkId) {
                    result.append(node)
                }
            } else {
                let filteredChildren = applyBookFilter(from: node.children, existingBkIds: existingBkIds)
                if !filteredChildren.isEmpty {
                    let copy = AnnotationNode(title: node.title, kind: node.kind, annotation: nil)
                    copy.children = filteredChildren
                    result.append(copy)
                }
            }
        }
        return result
    }

    private func filterNodesByTags(_ nodes: [AnnotationNode], tags: Set<String>? = nil) -> [AnnotationNode] {
        let activeTags = tags ?? selectedTags
        guard !activeTags.isEmpty else { return nodes }
        var result: [AnnotationNode] = []
        for node in nodes {
            if node.kind == .annotation, let ann = node.annotation {
                let annTags = Set(ann.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                let matches = tagFilterMode == .and
                    ? activeTags.allSatisfy { annTags.contains($0) }
                    : !activeTags.isDisjoint(with: annTags)
                if matches { result.append(node) }
            } else {
                let filteredChildren = filterNodesByTags(node.children, tags: tags)
                if !filteredChildren.isEmpty {
                    let copy = AnnotationNode(title: node.title, kind: node.kind, annotation: nil)
                    copy.children = filteredChildren
                    result.append(copy)
                }
            }
        }
        return result
    }

    private func filterNodes(_ nodes: [AnnotationNode], with query: String) -> [AnnotationNode] {
        var result: [AnnotationNode] = []
        let query = query.normalizeArabic(false)

        for node in nodes {
            var matchingChildren: [AnnotationNode] = []
            if !node.children.isEmpty {
                matchingChildren = filterNodes(node.children, with: query)
            }

            let matchesSelf: Bool = {
                if searchScope == .all || searchScope == .book {
                    if node.title.normalizeArabic(false).localizedStandardContains(query) { return true }
                }

                if let ann = node.annotation {
                    if searchScope == .all || searchScope == .context {
                        if ann.context.normalizeArabic(false).localizedStandardContains(query) { return true }
                    }
                    if searchScope == .all || searchScope == .note {
                        if let note = ann.note, note.normalizeArabic(false).localizedStandardContains(query) { return true }
                    }
                    if searchScope == .all || searchScope == .tag {
                        if ann.tags.contains(where: { $0.normalizeArabic(false).localizedStandardContains(query) }) { return true }
                    }
                }
                return false
            }()

            if matchesSelf {
                let copy = AnnotationNode(title: node.title, kind: node.kind, annotation: node.annotation)
                copy.children = node.children
                result.append(copy)
            } else if !matchingChildren.isEmpty {
                let copy = AnnotationNode(title: node.title, kind: node.kind, annotation: node.annotation)
                copy.children = matchingChildren
                result.append(copy)
            }
        }
        return result
    }

    func deleteAnnotation(id: Int64) {
        do {
            try AnnotationManager.shared.deleteAnnotation(id: id)
        } catch {
            print("Failed to delete annotation: \(error.localizedDescription)")
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

    private func gatherTags(from nodes: [AnnotationNode], into set: inout Set<String>) {
        for node in nodes {
            if let ann = node.annotation {
                for tag in ann.tags {
                    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { set.insert(trimmed) }
                }
            }
            if !node.children.isEmpty {
                gatherTags(from: node.children, into: &set)
            }
        }
    }
}

extension UserDefaults {
    @objc dynamic var hideMissingBookAnnotations: Bool {
        bool(forKey: "hideMissingBookAnnotations")
    }
}
