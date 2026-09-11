//
//  AnnotationTreeBuilder.swift
//  Maktabah
//

import Combine
import Foundation

final class AnnotationTreeBuilder: @unchecked Sendable {
    static let shared = AnnotationTreeBuilder()

    // MARK: - Publishers

    let diffPublisher = PassthroughSubject<AnnotationTreeDiff?, Never>()

    // MARK: - State & Queues

    private let treeQueue = DispatchQueue(label: "com.maktab.annotationTreeBuilder.queue", qos: .userInitiated)
    private var rootNode: AnnotationNode?

    private var groupingMode: AnnotationGroupingMode = UserDefaults.standard.selectedAnnGroupingMode
    private var sortOption: AnnotationSortOption = .init(
        field: UserDefaults.standard.selectedAnnSortField,
        isAscending: UserDefaults.standard.selectedAnnAscending
    )

    private var cancellables = Set<AnyCancellable>()
    private var hideMissingObservation: NSKeyValueObservation?

    private init() {
        AnnotationStore.shared.events
            .sink { [weak self] event in
                self?.handle(event: event)
            }
            .store(in: &cancellables)

        hideMissingObservation = UserDefaults.standard.observe(\.hideMissingBookAnnotations, options: [.new]) { [weak self] _, _ in
            self?.buildAnnotationTree()
        }

        buildAnnotationTree()
    }

    deinit {
        hideMissingObservation?.invalidate()
    }

    // MARK: - Public API

    func currentRootNode() -> AnnotationNode? {
        treeQueue.sync { rootNode }
    }

    func buildAnnotationTree() {
        treeQueue.async { [weak self] in
            guard let self else { return }
            rebuildTree()
            diffPublisher.send(nil)
        }
    }

    func updateGroupingMode(_ mode: AnnotationGroupingMode) {
        treeQueue.async { [weak self] in
            guard let self else { return }
            guard groupingMode != mode || rootNode == nil else { return }
            groupingMode = mode
            rebuildTree()
            diffPublisher.send(nil)
        }
    }

    func updateSorting(field: AnnotationSortField, isAscending: Bool) {
        treeQueue.async { [weak self] in
            guard let self else { return }
            let newOption = AnnotationSortOption(field: field, isAscending: isAscending)
            guard sortOption != newOption || rootNode == nil else { return }
            sortOption = newOption
            if let root = rootNode {
                sortNodeChildren(root)
            } else {
                rebuildTree()
            }
            diffPublisher.send(nil)
        }
    }

    // MARK: - Event Handling

    private func handle(event: AnnotationEvent) {
        treeQueue.async { [weak self] in
            guard let self else { return }
            switch event {
            case let .added(annotation):
                handleAdd(annotation)
            case let .updated(annotation):
                handleUpdate(annotation)
            case let .deleted(id, annotation):
                handleDelete(id: id, annotation: annotation)
            case let .batchUpdated(annotations):
                handleBatchUpdate(annotations)
            case .treeInvalidated:
                rebuildTree()
                diffPublisher.send(nil)
            }
        }
    }

    // MARK: - Mutations

    private func handleAdd(_ annotation: Annotation) {
        guard let root = rootNode else {
            rebuildTree()
            diffPublisher.send(nil)
            return
        }

        if UserDefaults.standard.hideMissingBookAnnotations,
           LibraryDataManager.shared.getBook([annotation.bkId]).isEmpty
        {
            return
        }

        guard let annotationId = annotation.id else { return }

        switch groupingMode {
        case .book:
            let bookNode = findOrCreateBookNode(for: annotation.bkId, in: root)
            let annotationNode = AnnotationNode(
                title: displayTitle(for: annotation),
                kind: .annotation,
                annotation: annotation
            )

            let index = bookNode.children.insertionIndex(for: annotationNode, using: compareNodes)
            bookNode.children.insert(annotationNode, at: index)

            var oldParentIdx: Int?
            var newParentIdx: Int?

            if sortOption.field == .createdAt {
                if let oldIndex = root.children.firstIndex(where: { $0 === bookNode }) {
                    oldParentIdx = oldIndex
                    root.children.remove(at: oldIndex)
                }
                let newIndex = root.children.insertionIndex(for: bookNode, using: compareNodes)
                root.children.insert(bookNode, at: newIndex)
                newParentIdx = newIndex
            }

            let diff = AnnotationTreeDiff(
                changeType: .added,
                annotation: annotation,
                annotationId: annotationId,
                oldParentIndex: oldParentIdx,
                newParentIndex: newParentIdx
            )
            diffPublisher.send(diff)
        case .tag:
            let tagDiff = addAnnotationToTagTree(annotation, root: root)
            let diff = AnnotationTreeDiff(
                changeType: .added,
                annotation: annotation,
                annotationId: annotationId,
                tagDiff: tagDiff
            )
            diffPublisher.send(diff)
        case .timeline:
            let tagDiff = addAnnotationToTimelineTree(annotation, root: root)
            let diff = AnnotationTreeDiff(
                changeType: .added,
                annotation: annotation,
                annotationId: annotationId,
                tagDiff: tagDiff
            )
            diffPublisher.send(diff)
        }
    }

    private func handleUpdate(_ annotation: Annotation) {
        guard let root = rootNode, let annotationId = annotation.id else {
            rebuildTree()
            diffPublisher.send(nil)
            return
        }

        if UserDefaults.standard.hideMissingBookAnnotations,
           LibraryDataManager.shared.getBook([annotation.bkId]).isEmpty
        {
            return
        }

        switch groupingMode {
        case .book, .timeline:
            guard let node = findAnnotationNode(by: annotationId) else {
                handleAdd(annotation)
                return
            }

            node.update(with: annotation)
            let diff = AnnotationTreeDiff(
                changeType: .updated,
                annotation: annotation,
                annotationId: annotationId
            )
            diffPublisher.send(diff)
        case .tag:
            let tagDiff = updateAnnotationInTagTree(annotation, root: root)
            let diff = AnnotationTreeDiff(
                changeType: .updated,
                annotation: annotation,
                annotationId: annotationId,
                tagDiff: tagDiff
            )
            diffPublisher.send(diff)
        }
    }

    private func handleDelete(id: Int64, annotation: Annotation?) {
        guard let root = rootNode else {
            rebuildTree()
            diffPublisher.send(nil)
            return
        }

        if UserDefaults.standard.hideMissingBookAnnotations,
           let bkId = annotation?.bkId,
           LibraryDataManager.shared.getBook([bkId]).isEmpty
        {
            return
        }

        switch groupingMode {
        case .book:
            let diff = deleteAnnotationFromBookTree(id: id, annotation: annotation, root: root)
            diffPublisher.send(diff)
        case .tag, .timeline:
            let tagDiff = removeAnnotationFromTagTree(id: id, root: root)
            let diff = AnnotationTreeDiff(
                changeType: .deleted,
                annotation: annotation,
                annotationId: id,
                tagDiff: tagDiff
            )
            diffPublisher.send(diff)
        }
    }

    private func deleteAnnotationFromBookTree(id: Int64, annotation: Annotation?, root: AnnotationNode) -> AnnotationTreeDiff {
        for bookNode in root.children {
            guard let index = bookNode.children.firstIndex(where: { $0.annotation?.id == id }) else { continue }
            bookNode.children.remove(at: index)

            var oldParentIdx: Int?
            var newParentIdx: Int?

            if bookNode.children.isEmpty {
                if let bookIndex = root.children.firstIndex(where: { $0 === bookNode }) {
                    root.children.remove(at: bookIndex)
                }
            } else if sortOption.field == .createdAt {
                if let oldIdx = root.children.firstIndex(where: { $0 === bookNode }) {
                    oldParentIdx = oldIdx
                    root.children.remove(at: oldIdx)
                }
                let newIdx = root.children.insertionIndex(for: bookNode, using: compareNodes)
                root.children.insert(bookNode, at: newIdx)
                newParentIdx = newIdx
            }

            return AnnotationTreeDiff(
                changeType: .deleted,
                annotation: annotation,
                annotationId: id,
                oldParentIndex: oldParentIdx,
                newParentIndex: newParentIdx
            )
        }

        return AnnotationTreeDiff(
            changeType: .deleted,
            annotation: annotation,
            annotationId: id
        )
    }

    private func handleBatchUpdate(_ annotations: [Annotation]) {
        guard let root = rootNode else {
            rebuildTree()
            diffPublisher.send(nil)
            return
        }

        var effectiveAnnotations = annotations
        if UserDefaults.standard.hideMissingBookAnnotations {
            let existingBkIds = Set(effectiveAnnotations.map(\.bkId).filter { !LibraryDataManager.shared.getBook([$0]).isEmpty })
            effectiveAnnotations = effectiveAnnotations.filter { existingBkIds.contains($0.bkId) }
        }
        guard !effectiveAnnotations.isEmpty else { return }

        switch groupingMode {
        case .book, .timeline:
            for annotation in effectiveAnnotations {
                guard let id = annotation.id, let node = findAnnotationNode(by: id) else { continue }
                node.update(with: annotation)
            }
            let repId: Int64? = effectiveAnnotations.count == 1 ? effectiveAnnotations.first?.id : nil
            let diff = AnnotationTreeDiff(
                changeType: .updated,
                annotation: effectiveAnnotations.first,
                annotationId: repId
            )
            diffPublisher.send(diff)
        case .tag:
            let tagDiff = performBatchTagTreeUpdate(effectiveAnnotations, root: root)
            let repId: Int64? = effectiveAnnotations.count == 1 ? effectiveAnnotations.first?.id : nil
            let diff = AnnotationTreeDiff(
                changeType: .updated,
                annotation: effectiveAnnotations.first,
                annotationId: repId,
                tagDiff: tagDiff
            )
            diffPublisher.send(diff)
        }
    }

    // MARK: - Tree Rebuilding

    private func rebuildTree() {
        let root = AnnotationNode(title: "All Annotations", kind: .root)
        var anns = AnnotationStore.shared.loadAnnotations()

        if UserDefaults.standard.hideMissingBookAnnotations {
            let uniqueBkIds = Set(anns.map(\.bkId))
            let existingBkIds = Set(uniqueBkIds.filter { !LibraryDataManager.shared.getBook([$0]).isEmpty })
            anns = anns.filter { existingBkIds.contains($0.bkId) }
        }

        switch groupingMode {
        case .book:
            populateBookTree(root: root, annotations: anns)
        case .tag:
            populateTagTree(root: root, annotations: anns)
        case .timeline:
            populateTimelineTree(root: root, annotations: anns)
        }

        sortNodeChildren(root)
        rootNode = root
    }

    private func populateBookTree(root: AnnotationNode, annotations: [Annotation]) {
        let grouped = Dictionary(grouping: annotations, by: { $0.bkId })

        for bkId in grouped.keys {
            let annsForBook = grouped[bkId] ?? []
            let bookTitle = LibraryDataManager.shared.getBook([bkId]).first?.book ?? "Unknown Book (\(bkId))"
            let bookNode = AnnotationNode(title: bookTitle, kind: .book)

            for ann in annsForBook {
                let child = AnnotationNode(
                    title: displayTitle(for: ann),
                    kind: .annotation,
                    annotation: ann
                )
                bookNode.children.append(child)
            }

            root.children.append(bookNode)
        }
    }

    private func populateTagTree(root: AnnotationNode, annotations: [Annotation]) {
        var grouped: [String: [Annotation]] = [:]
        var untagged: [Annotation] = []

        for annotation in annotations {
            let tags = AnnotationRepository.shared.sanitizeTagNames(annotation.tags)
            if tags.isEmpty {
                untagged.append(annotation)
                continue
            }

            for tag in tags {
                grouped[tag, default: []].append(annotation)
            }
        }

        for tag in grouped.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let tagNode = AnnotationNode(title: tag, kind: .tag)
            for annotation in grouped[tag] ?? [] {
                tagNode.children.append(
                    AnnotationNode(
                        title: displayTitle(for: annotation),
                        kind: .annotation,
                        annotation: annotation
                    )
                )
            }
            root.children.append(tagNode)
        }

        if !untagged.isEmpty {
            let untaggedNode = AnnotationNode(title: String(localized: "Untagged"), kind: .untagged)
            for annotation in untagged {
                untaggedNode.children.append(
                    AnnotationNode(
                        title: displayTitle(for: annotation),
                        kind: .annotation,
                        annotation: annotation
                    )
                )
            }
            root.children.append(untaggedNode)
        }
    }

    // MARK: - Sorting

    private func sortNodeChildren(_ node: AnnotationNode) {
        if !node.children.isEmpty {
            node.children.sort(by: compareNodes)
        }
        for child in node.children {
            sortNodeChildren(child)
        }
    }

    private func compareNodes(_ lhs: AnnotationNode, _ rhs: AnnotationNode) -> Bool {
        if let left = lhs.annotation, let right = rhs.annotation {
            let orderedAscending: Bool
            switch sortOption.field {
            case .createdAt:
                orderedAscending = left.createdAt == right.createdAt
                    ? left.context.localizedCaseInsensitiveCompare(right.context) == .orderedAscending
                    : left.createdAt < right.createdAt
            case .context:
                let contextOrder = left.context.localizedCaseInsensitiveCompare(right.context)
                orderedAscending = contextOrder == .orderedSame
                    ? left.createdAt < right.createdAt
                    : contextOrder == .orderedAscending
            case .page:
                orderedAscending = left.page == right.page
                    ? left.createdAt < right.createdAt
                    : left.page < right.page
            case .part:
                if left.part == right.part {
                    orderedAscending = left.page == right.page
                        ? left.createdAt < right.createdAt
                        : left.page < right.page
                } else {
                    orderedAscending = left.part < right.part
                }
            }
            return sortOption.isAscending ? orderedAscending : !orderedAscending
        }

        if lhs.annotation == nil, rhs.annotation == nil {
            if lhs.kind == .dateBucket, rhs.kind == .dateBucket {
                let leftTime = lhs.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
                let rightTime = rhs.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
                if leftTime != rightTime {
                    let orderedAscending = leftTime < rightTime
                    return sortOption.isAscending ? orderedAscending : !orderedAscending
                }
            }
            if sortOption.field == .createdAt {
                let leftLatest = lhs.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
                let rightLatest = rhs.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
                if leftLatest != rightLatest {
                    let orderedAscending = leftLatest < rightLatest
                    return sortOption.isAscending ? orderedAscending : !orderedAscending
                }
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    // MARK: - Book Mode Helpers

    private func findOrCreateBookNode(for bkId: Int, in root: AnnotationNode) -> AnnotationNode {
        if let existing = root.children.first(where: { node in
            guard let firstChild = node.children.first,
                  let annotation = firstChild.annotation else { return false }
            return annotation.bkId == bkId
        }) {
            return existing
        }

        guard let book = LibraryDataManager.shared.getBook([bkId]).first else {
            let fallbackNode = AnnotationNode(title: "Unknown Book", kind: .book)
            let idx = root.children.insertionIndex(for: fallbackNode, using: compareNodes)
            root.children.insert(fallbackNode, at: idx)
            return fallbackNode
        }

        let bookNode = AnnotationNode(title: book.book, kind: .book)
        let idx = root.children.insertionIndex(for: bookNode, using: compareNodes)
        root.children.insert(bookNode, at: idx)

        return bookNode
    }

    private func findAnnotationNode(by id: Int64) -> AnnotationNode? {
        guard let root = rootNode else { return nil }

        for parent in root.children {
            if let found = parent.children.first(where: { $0.annotation?.id == id }) {
                return found
            }
        }
        return nil
    }

    // MARK: - Tag Mode Operations

    private func addAnnotationToTagTree(_ annotation: Annotation, root: AnnotationNode) -> TagUpdateDiff {
        let tags = AnnotationRepository.shared.sanitizeTagNames(annotation.tags)
        let title = displayTitle(for: annotation)
        var addedEntries: [TagUpdateDiff.AddedEntry] = []

        if tags.isEmpty {
            addedEntries.append(insertAnnotationIntoUntagged(annotation, title: title, root: root))
        } else {
            for tag in tags {
                addedEntries.append(insertAnnotation(annotation, title: title, intoTag: tag, root: root))
            }
        }

        return TagUpdateDiff(removed: [], added: addedEntries, updated: [])
    }

    private func updateAnnotationInTagTree(_ annotation: Annotation, root: AnnotationNode) -> TagUpdateDiff {
        guard let id = annotation.id else {
            return TagUpdateDiff(removed: [], added: [], updated: [])
        }

        let title = displayTitle(for: annotation)
        let newTags = Set(AnnotationRepository.shared.sanitizeTagNames(annotation.tags))
        let existingTagNodes = root.children.filter { $0.children.contains { $0.annotation?.id == id } }
        let existingTagNames = Set(existingTagNodes.compactMap { $0.kind == .tag ? $0.title : nil })
        let isCurrentlyUntagged = existingTagNodes.contains { $0.kind == .untagged }

        let updateContext = TagUpdateContext(
            annotation: annotation,
            title: title,
            root: root,
            existingTagNames: existingTagNames,
            newTags: newTags,
            isCurrentlyUntagged: isCurrentlyUntagged
        )

        let removedEntries = collectRemovedEntriesForUpdate(
            id: id,
            existingTagNodes: existingTagNodes,
            context: updateContext
        )

        let updatedNodes = updateExistingAnnotationNodes(
            id: id,
            context: updateContext
        )

        let addedEntries = collectAddedEntriesForUpdate(
            context: updateContext
        )

        return TagUpdateDiff(removed: removedEntries, added: addedEntries, updated: updatedNodes)
    }

    private func removeAnnotationFromTagTree(id: Int64, root: AnnotationNode) -> TagUpdateDiff {
        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        for tagNode in root.children {
            if let entry = removeAnnotationFromTagNode(id: id, tagNode: tagNode, root: root) {
                removedEntries.append(entry)
            }
        }

        return TagUpdateDiff(removed: removedEntries, added: [], updated: [])
    }

    private func performBatchTagTreeUpdate(_ annotations: [Annotation], root: AnnotationNode) -> TagUpdateDiff {
        let updatedAnnsDict = Dictionary(uniqueKeysWithValues: annotations.compactMap { ann in ann.id.map { ($0, ann) } })
        let (removedEntries, updatedNodes) = processBatchTagUpdates(root: root, updatedAnnsDict: updatedAnnsDict)

        root.children.removeAll { tagNode in
            tagNode.children.isEmpty && tagNode.kind != .root
        }

        let addedEntries = processBatchTagAdditions(root: root, annotations: annotations)

        return TagUpdateDiff(removed: removedEntries, added: addedEntries, updated: updatedNodes)
    }

    private func removeAnnotationFromTagNode(
        id: Int64,
        tagNode: AnnotationNode,
        root: AnnotationNode
    ) -> TagUpdateDiff.RemovedEntry? {
        guard let annIdx = tagNode.children.firstIndex(where: { $0.annotation?.id == id }) else {
            return nil
        }
        let annNode = tagNode.children[annIdx]
        let becomesEmpty = tagNode.children.count == 1
        let oldIndex = becomesEmpty ? (root.children.firstIndex(where: { $0 === tagNode }) ?? -1) : annIdx

        tagNode.children.remove(at: annIdx)
        if becomesEmpty {
            root.children.removeAll { $0 === tagNode }
        }

        return .init(
            annotationNode: annNode,
            tagNode: tagNode,
            tagNodeBecomesEmpty: becomesEmpty,
            oldIndex: oldIndex
        )
    }

    private func insertAnnotationIntoContainer(
        _ annotation: Annotation,
        title: String,
        container: AnnotationNode,
        isContainerNew: Bool
    ) -> TagUpdateDiff.AddedEntry {
        let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
        if isContainerNew {
            container.children.append(newNode)
        } else {
            let idx = container.children.insertionIndex(for: newNode, using: compareNodes)
            container.children.insert(newNode, at: idx)
        }
        return .init(annotationNode: newNode, tagNode: container, tagNodeIsNew: isContainerNew)
    }

    private func getOrCreateContainerNode(tag: String?, in root: AnnotationNode) -> (container: AnnotationNode, isNew: Bool) {
        if let tag {
            if let tagNode = root.children.first(where: { $0.kind == .tag && $0.title == tag }) {
                return (tagNode, false)
            }
            let tagNode = AnnotationNode(title: tag, kind: .tag)
            let insertIdx = root.children.firstIndex(where: { node in
                guard node.kind == .tag else { return node.kind == .untagged }
                return tag.localizedCaseInsensitiveCompare(node.title) == .orderedAscending
            }) ?? (root.children.firstIndex(where: { $0.kind == .untagged }) ?? root.children.endIndex)
            root.children.insert(tagNode, at: insertIdx)
            return (tagNode, true)
        } else {
            if let untaggedNode = root.children.first(where: { $0.kind == .untagged }) {
                return (untaggedNode, false)
            }
            let untaggedNode = AnnotationNode(title: String(localized: "Untagged"), kind: .untagged)
            root.children.append(untaggedNode)
            return (untaggedNode, true)
        }
    }

    private func insertAnnotation(
        _ annotation: Annotation,
        title: String,
        intoTag tag: String,
        root: AnnotationNode
    ) -> TagUpdateDiff.AddedEntry {
        let (container, isNew) = getOrCreateContainerNode(tag: tag, in: root)
        return insertAnnotationIntoContainer(annotation, title: title, container: container, isContainerNew: isNew)
    }

    private func insertAnnotationIntoUntagged(
        _ annotation: Annotation,
        title: String,
        root: AnnotationNode
    ) -> TagUpdateDiff.AddedEntry {
        let (container, isNew) = getOrCreateContainerNode(tag: nil, in: root)
        return insertAnnotationIntoContainer(annotation, title: title, container: container, isContainerNew: isNew)
    }

    private struct TagUpdateContext {
        let annotation: Annotation
        let title: String
        let root: AnnotationNode
        let existingTagNames: Set<String>
        let newTags: Set<String>
        let isCurrentlyUntagged: Bool
    }

    private func collectRemovedEntriesForUpdate(
        id: Int64,
        existingTagNodes: [AnnotationNode],
        context: TagUpdateContext
    ) -> [TagUpdateDiff.RemovedEntry] {
        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        for tagNode in existingTagNodes where context.existingTagNames.subtracting(context.newTags).contains(tagNode.title) {
            if let entry = removeAnnotationFromTagNode(id: id, tagNode: tagNode, root: context.root) {
                removedEntries.append(entry)
            }
        }
        if context.isCurrentlyUntagged, !context.newTags.isEmpty {
            if let untaggedNode = context.root.children.first(where: { $0.kind == .untagged }),
               let entry = removeAnnotationFromTagNode(id: id, tagNode: untaggedNode, root: context.root)
            {
                removedEntries.append(entry)
            }
        }
        return removedEntries
    }

    private func updateExistingAnnotationNodes(
        id: Int64,
        context: TagUpdateContext
    ) -> [AnnotationNode] {
        var updatedNodes: [AnnotationNode] = []
        for tagNode in context.root.children where context.existingTagNames.intersection(context.newTags).contains(tagNode.title) {
            if let node = tagNode.children.first(where: { $0.annotation?.id == id }) {
                node.title = context.title
                node.annotation = context.annotation
                updatedNodes.append(node)
            }
        }
        return updatedNodes
    }

    private func collectAddedEntriesForUpdate(
        context: TagUpdateContext
    ) -> [TagUpdateDiff.AddedEntry] {
        var addedEntries: [TagUpdateDiff.AddedEntry] = []
        for tag in context.newTags.subtracting(context.existingTagNames) {
            addedEntries.append(insertAnnotation(context.annotation, title: context.title, intoTag: tag, root: context.root))
        }
        if context.newTags.isEmpty, !context.isCurrentlyUntagged {
            addedEntries.append(insertAnnotationIntoUntagged(context.annotation, title: context.title, root: context.root))
        }
        return addedEntries
    }

    private func processBatchTagUpdates(
        root: AnnotationNode,
        updatedAnnsDict: [Int64: Annotation]
    ) -> (removed: [TagUpdateDiff.RemovedEntry], updated: [AnnotationNode]) {
        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        var updatedNodes: [AnnotationNode] = []

        for tagNode in root.children {
            var indicesToRemove: [Int] = []

            for (idx, child) in tagNode.children.enumerated() {
                guard let id = child.annotation?.id, let updatedAnn = updatedAnnsDict[id] else { continue }

                let newTags = Set(AnnotationRepository.shared.sanitizeTagNames(updatedAnn.tags))
                let title = displayTitle(for: updatedAnn)
                let shouldRemove = (tagNode.kind == .untagged) ? !newTags.isEmpty : !newTags.contains(tagNode.title)

                if shouldRemove {
                    indicesToRemove.append(idx)
                } else {
                    child.title = title
                    child.annotation = updatedAnn
                    updatedNodes.append(child)
                }
            }

            for idx in indicesToRemove.reversed() {
                if let entry = removeAnnotationFromTagNode(id: tagNode.children[idx].annotation?.id ?? -1, tagNode: tagNode, root: root) {
                    removedEntries.append(entry)
                }
            }
        }
        return (removedEntries, updatedNodes)
    }

    private func processBatchTagAdditions(
        root: AnnotationNode,
        annotations: [Annotation]
    ) -> [TagUpdateDiff.AddedEntry] {
        var addedEntries: [TagUpdateDiff.AddedEntry] = []
        for annotation in annotations {
            guard let id = annotation.id else { continue }
            let newTags = Set(AnnotationRepository.shared.sanitizeTagNames(annotation.tags))
            let title = displayTitle(for: annotation)

            if newTags.isEmpty {
                let untaggedNode = root.children.first(where: { $0.kind == .untagged })
                if untaggedNode?.children.contains(where: { $0.annotation?.id == id }) != true {
                    addedEntries.append(insertAnnotationIntoUntagged(annotation, title: title, root: root))
                }
            } else {
                for tag in newTags {
                    let tagNode = root.children.first(where: { $0.kind == .tag && $0.title == tag })
                    if tagNode?.children.contains(where: { $0.annotation?.id == id }) != true {
                        addedEntries.append(insertAnnotation(annotation, title: title, intoTag: tag, root: root))
                    }
                }
            }
        }
        return addedEntries
    }

    // MARK: - Timeline Mode Operations

    private func populateTimelineTree(root: AnnotationNode, annotations: [Annotation]) {
        let now = Date()
        let calendar = Calendar.current

        var grouped: [DateBucket: [Annotation]] = [:]
        for annotation in annotations {
            let bucket = DateBucket.bucket(for: annotation.createdAt, relativeTo: now, calendar: calendar)
            grouped[bucket, default: []].append(annotation)
        }

        let sortedBuckets = grouped.keys.sorted { lhs, rhs in
            sortOption.isAscending ? (lhs < rhs) : (lhs > rhs)
        }

        for bucket in sortedBuckets {
            let bucketNode = AnnotationNode(title: bucket.localizedTitle, kind: .dateBucket)
            for annotation in grouped[bucket] ?? [] {
                bucketNode.children.append(
                    AnnotationNode(
                        title: displayTitle(for: annotation),
                        kind: .annotation,
                        annotation: annotation
                    )
                )
            }
            root.children.append(bucketNode)
        }
    }

    private func addAnnotationToTimelineTree(_ annotation: Annotation, root: AnnotationNode) -> TagUpdateDiff {
        let bucket = DateBucket.bucket(for: annotation.createdAt)
        let title = displayTitle(for: annotation)

        if let existingBucketNode = root.children.first(where: { $0.kind == .dateBucket && $0.title == bucket.localizedTitle }) {
            let entry = insertAnnotationIntoContainer(annotation, title: title, container: existingBucketNode, isContainerNew: false)
            return TagUpdateDiff(removed: [], added: [entry], updated: [])
        } else {
            let newBucketNode = AnnotationNode(title: bucket.localizedTitle, kind: .dateBucket)
            let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
            newBucketNode.children.append(newNode)

            let insertIdx = root.children.insertionIndex(for: newBucketNode) { left, right in
                let leftTime = left.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
                let rightTime = right.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
                let orderedAscending = leftTime < rightTime
                return self.sortOption.isAscending ? orderedAscending : !orderedAscending
            }
            root.children.insert(newBucketNode, at: insertIdx)

            let entry = TagUpdateDiff.AddedEntry(annotationNode: newNode, tagNode: newBucketNode, tagNodeIsNew: true)
            return TagUpdateDiff(removed: [], added: [entry], updated: [])
        }
    }

    private func displayTitle(for annotation: Annotation) -> String {
        if let note = annotation.note, !note.isEmpty {
            return note
        }
        return annotation.context
    }
}
