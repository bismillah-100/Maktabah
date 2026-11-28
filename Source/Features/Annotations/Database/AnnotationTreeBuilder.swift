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
    private let treeQueueKey = DispatchSpecificKey<Void>()
    private var rootNode: AnnotationNode?

    private var groupingMode: AnnotationGroupingMode = UserDefaults.standard.selectedAnnGroupingMode
    private var sortOption: AnnotationSortOption = .init(
        field: UserDefaults.standard.selectedAnnSortField,
        isAscending: UserDefaults.standard.selectedAnnAscending
    )

    private var cancellables = Set<AnyCancellable>()
    private var hideMissingObservation: NSKeyValueObservation?

    private init() {
        treeQueue.setSpecific(key: treeQueueKey, value: ())

        AnnotationStore.shared.events
            .sink { [weak self] event in
                self?.handle(event: event)
            }
            .store(in: &cancellables)

        hideMissingObservation = UserDefaults.standard.observe(\.hideMissingBookAnnotations, options: [.new]) { [weak self] _, _ in
            self?.buildAnnotationTree()
        }

        NotificationCenter.default.publisher(for: .bookLifecycleDidChange)
            .sink { [weak self] notification in
                guard let event = notification.bookLifecycleEvent else { return }
                switch event {
                case .deleted, .updated, .integrated, .idChanged, .libraryFolderChanged, .bundledDataCleaned:
                    self?.buildAnnotationTree()
                }
            }
            .store(in: &cancellables)

        buildAnnotationTree()
    }

    deinit {
        hideMissingObservation?.invalidate()
    }

    // MARK: - Public API

    func currentRootNode() -> AnnotationNode? {
        withRootNode { $0 }
    }

    func withRootNode<T>(_ body: (AnnotationNode?) -> T) -> T {
        if DispatchQueue.getSpecific(key: treeQueueKey) != nil {
            return body(rootNode)
        }
        return treeQueue.sync { body(rootNode) }
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

    func setSortOptionForTesting(_ option: AnnotationSortOption) {
        if DispatchQueue.getSpecific(key: treeQueueKey) != nil {
            sortOption = option
        } else {
            treeQueue.sync {
                sortOption = option
            }
        }
    }

    func currentSortOptionForTesting() -> AnnotationSortOption {
        if DispatchQueue.getSpecific(key: treeQueueKey) != nil {
            return sortOption
        }
        return treeQueue.sync { sortOption }
    }

    // MARK: - Event Handling

    private func handle(event: AnnotationEvent) {
        treeQueue.async { [weak self] in
            guard let self else { return }
            switch event {
            case let .added(annotation):
                handleAdd(annotation)
            case let .batchAdded(annotations):
                handleBatchAdd(annotations)
            case let .updated(annotation):
                handleUpdate(annotation)
            case let .deleted(id, annotation):
                handleDelete(id: id, annotation: annotation)
            case let .batchDeleted(ids, annotations):
                handleBatchDelete(ids: ids, annotations: annotations)
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
            handleAddBookGrouping(annotation, root: root, annotationId: annotationId)
        case .tag:
            handleAddTagGrouping(annotation, root: root, annotationId: annotationId)
        case .timeline:
            handleAddTimelineGrouping(annotation, root: root, annotationId: annotationId)
        }
    }

    private func handleAddBookGrouping(_ annotation: Annotation, root: AnnotationNode, annotationId: Int64) {
        let bookNode = findOrCreateBookNode(for: annotation.bkId, in: root)
        let annotationNode = AnnotationNode(
            title: displayTitle(for: annotation),
            kind: .annotation,
            annotation: annotation,
            bookTitle: bookNode.title,
            normalizedBookTitle: bookNode.title.normalizeArabic(false)
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
    }

    private func handleAddTagGrouping(_ annotation: Annotation, root: AnnotationNode, annotationId: Int64) {
        let tagDiff = addAnnotationToTagTree(annotation, root: root)
        let diff = AnnotationTreeDiff(
            changeType: .added,
            annotation: annotation,
            annotationId: annotationId,
            tagDiff: tagDiff
        )
        diffPublisher.send(diff)
    }

    private func handleAddTimelineGrouping(_ annotation: Annotation, root: AnnotationNode, annotationId: Int64) {
        let tagDiff = addAnnotationToTimelineTree(annotation, root: root)
        let diff = AnnotationTreeDiff(
            changeType: .added,
            annotation: annotation,
            annotationId: annotationId,
            tagDiff: tagDiff
        )
        diffPublisher.send(diff)
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
        let annotations = annotation != nil ? [annotation!] : []
        handleBatchDelete(ids: [id], annotations: annotations)
    }

    private func handleBatchDelete(ids: [Int64], annotations: [Annotation]) {
        guard let root = rootNode else {
            rebuildTree()
            diffPublisher.send(nil)
            return
        }

        var effectiveIds = ids
        var effectiveAnnotations = annotations
        if UserDefaults.standard.hideMissingBookAnnotations, !annotations.isEmpty {
            let uniqueBkIds = Array(Set(annotations.map(\.bkId)))
            let existingBkIds = Set(LibraryDataManager.shared.getBook(uniqueBkIds).map(\.id))
            effectiveAnnotations = annotations.filter { existingBkIds.contains($0.bkId) }
            let validIds = Set(effectiveAnnotations.compactMap(\.id))
            effectiveIds = ids.filter { validIds.contains($0) }
        }
        guard !effectiveIds.isEmpty else { return }

        switch groupingMode {
        case .book:
            let bookDiff = deleteAnnotationsFromBookTree(ids: effectiveIds, root: root)
            let diff = AnnotationTreeDiff(
                changeType: .deleted,
                annotation: effectiveAnnotations.first,
                annotationId: effectiveIds.count == 1 ? effectiveIds.first : nil,
                bookDeletionDiff: bookDiff
            )
            diffPublisher.send(diff)
        case .tag, .timeline:
            let tagDiff = removeAnnotationsFromTagTree(ids: effectiveIds, root: root)
            let diff = AnnotationTreeDiff(
                changeType: .deleted,
                annotation: effectiveAnnotations.first,
                annotationId: effectiveIds.count == 1 ? effectiveIds.first : nil,
                tagDiff: tagDiff
            )
            diffPublisher.send(diff)
        }
    }

    func deleteAnnotationsFromBookTree(ids: [Int64], root: AnnotationNode) -> BookDeletionDiff {
        let idSet = Set(ids)
        var removedChildren: [BookDeletionDiff.RemovedChild] = []
        var removedParents: [BookDeletionDiff.RemovedParent] = []
        var affectedNonEmptyBooks: [AnnotationNode] = []

        // Phase 1: Remove children from each bookNode and record original root indices for empty parents
        for (rootIdx, bookNode) in root.children.enumerated() {
            var indicesToRemove: [(node: AnnotationNode, index: Int)] = []
            for (idx, child) in bookNode.children.enumerated() where child.annotation?.id.map(idSet.contains) == true {
                indicesToRemove.append((node: child, index: idx))
            }

            guard !indicesToRemove.isEmpty else { continue }

            for item in indicesToRemove {
                removedChildren.append(.init(
                    annotationNode: item.node,
                    parentNode: bookNode,
                    oldChildIndex: item.index
                ))
            }

            for item in indicesToRemove.reversed() {
                bookNode.children.remove(at: item.index)
            }

            if bookNode.children.isEmpty {
                removedParents.append(.init(parentNode: bookNode, oldRootIndex: rootIdx))
            } else {
                affectedNonEmptyBooks.append(bookNode)
            }
        }

        // Phase 2: Remove empty parents from root.children in descending order of oldRootIndex
        let sortedParents = removedParents.sorted { $0.oldRootIndex > $1.oldRootIndex }
        for parentEntry in sortedParents {
            root.children.remove(at: parentEntry.oldRootIndex)
        }

        // Phase 3: Re-sort affected non-empty books if sorted by createdAt (matching NSOutlineView execution order)
        let movedParents = updateMovedParentsForDeletions(root: root, affectedBooks: affectedNonEmptyBooks)

        return BookDeletionDiff(
            removedChildren: removedChildren,
            removedParents: removedParents,
            movedParents: movedParents
        )
    }

    private func updateMovedParentsForDeletions(
        root: AnnotationNode,
        affectedBooks: [AnnotationNode]
    ) -> [BookDeletionDiff.MovedParent] {
        guard sortOption.field == .createdAt else { return [] }
        var moved: [BookDeletionDiff.MovedParent] = []
        for bookNode in affectedBooks {
            guard let oldIdx = root.children.firstIndex(where: { $0 === bookNode }) else { continue }
            root.children.remove(at: oldIdx)
            let newIdx = root.children.insertionIndex(for: bookNode, using: compareNodes)
            root.children.insert(bookNode, at: newIdx)
            if oldIdx != newIdx {
                moved.append(.init(parentNode: bookNode, oldIndex: oldIdx, newIndex: newIdx))
            }
        }
        return moved
    }

    func removeAnnotationsFromTagTree(ids: [Int64], root: AnnotationNode) -> TagUpdateDiff {
        let idSet = Set(ids)
        var diffEntries: [TagUpdateDiff.RemovedEntry] = []

        for (rootIdx, tagNode) in root.children.enumerated() {
            let matches = tagNode.children.indices.compactMap { idx -> (node: AnnotationNode, index: Int)? in
                let child = tagNode.children[idx]
                guard let childId = child.annotation?.id, idSet.contains(childId) else { return nil }
                return (child, idx)
            }

            diffEntries += pruneTagChildrenAndRecord(
                from: tagNode,
                rootIndex: rootIdx,
                indicesToRemove: matches
            )
        }

        root.children.removeAll { $0.children.isEmpty && $0.kind != .root }

        return TagUpdateDiff(removed: diffEntries, added: [], updated: [])
    }

    private func handleBatchUpdate(_ annotations: [Annotation]) {
        guard let root = rootNode else {
            rebuildTree()
            diffPublisher.send(nil)
            return
        }

        var effectiveAnnotations = annotations
        if UserDefaults.standard.hideMissingBookAnnotations {
            let uniqueBkIds = Array(Set(effectiveAnnotations.map(\.bkId)))
            let existingBkIds = Set(LibraryDataManager.shared.getBook(uniqueBkIds).map(\.id))
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
                annotationId: repId,
                updatedAnnotations: effectiveAnnotations
            )
            diffPublisher.send(diff)
        case .tag:
            let tagDiff = performBatchTagTreeUpdate(effectiveAnnotations, root: root)
            let repId: Int64? = effectiveAnnotations.count == 1 ? effectiveAnnotations.first?.id : nil
            let diff = AnnotationTreeDiff(
                changeType: .updated,
                annotation: effectiveAnnotations.first,
                annotationId: repId,
                tagDiff: tagDiff,
                updatedAnnotations: effectiveAnnotations
            )
            diffPublisher.send(diff)
        }
    }

    private func handleBatchAdd(_ annotations: [Annotation]) {
        guard let root = rootNode else {
            rebuildTree()
            diffPublisher.send(nil)
            return
        }

        let effectiveAnnotations = filterNewAnnotations(annotations, in: root)
        guard !effectiveAnnotations.isEmpty else { return }

        let repId: Int64? = effectiveAnnotations.count == 1 ? effectiveAnnotations.first?.id : nil

        switch groupingMode {
        case .book:
            let bookDiff = addAnnotationsToBookTree(effectiveAnnotations, root: root)
            let diff = AnnotationTreeDiff(
                changeType: .added,
                annotation: effectiveAnnotations.first,
                annotationId: repId,
                bookAdditionDiff: bookDiff
            )
            diffPublisher.send(diff)

        case .tag:
            let addedEntries = processBatchTagAdditions(root: root, annotations: effectiveAnnotations)
            let tagDiff = TagUpdateDiff(removed: [], added: addedEntries, updated: [])
            let diff = AnnotationTreeDiff(
                changeType: .added,
                annotation: effectiveAnnotations.first,
                annotationId: repId,
                tagDiff: tagDiff
            )
            diffPublisher.send(diff)

        case .timeline:
            let allAddedEntries = effectiveAnnotations.flatMap { addAnnotationToTimelineTree($0, root: root).added }
            let tagDiff = TagUpdateDiff(removed: [], added: allAddedEntries, updated: [])
            let diff = AnnotationTreeDiff(
                changeType: .added,
                annotation: effectiveAnnotations.first,
                annotationId: repId,
                tagDiff: tagDiff
            )
            diffPublisher.send(diff)
        }
    }

    private func filterNewAnnotations(_ annotations: [Annotation], in root: AnnotationNode) -> [Annotation] {
        var effective = annotations
        if UserDefaults.standard.hideMissingBookAnnotations {
            let uniqueBkIds = Array(Set(effective.map(\.bkId)))
            let existingBkIds = Set(LibraryDataManager.shared.getBook(uniqueBkIds).map(\.id))
            effective = effective.filter { existingBkIds.contains($0.bkId) }
        }

        let existingIds = Set(root.children.flatMap { parent in
            parent.children.compactMap { $0.annotation?.id }
        })
        return effective.filter { ann in
            guard let id = ann.id else { return false }
            return !existingIds.contains(id)
        }
    }

    func addAnnotationsToBookTree(_ annotations: [Annotation], root: AnnotationNode) -> BookAdditionDiff {
        let initialParents = root.children
        let initialParentSet = Set(initialParents.map { ObjectIdentifier($0) })
        let initialParentIndices = Dictionary(uniqueKeysWithValues: initialParents.enumerated().map { (ObjectIdentifier($0.element), $0.offset) })

        var affectedExistingParents = Set<AnnotationNode>()

        for annotation in annotations {
            let bookNode = findOrCreateBookNode(for: annotation.bkId, in: root)
            if initialParentSet.contains(ObjectIdentifier(bookNode)) {
                affectedExistingParents.insert(bookNode)
            }

            let bTitle = bookNode.title
            let annotationNode = AnnotationNode(
                title: displayTitle(for: annotation),
                kind: .annotation,
                annotation: annotation,
                bookTitle: bTitle,
                normalizedBookTitle: bTitle.normalizeArabic(false)
            )
            let insertIdx = bookNode.children.insertionIndex(for: annotationNode, using: compareNodes)
            bookNode.children.insert(annotationNode, at: insertIdx)
        }

        let movedParents = calculateMovedParents(
            root: root,
            initialParentSet: initialParentSet,
            initialParentIndices: initialParentIndices
        )

        var addedParents: [BookAdditionDiff.AddedParent] = []
        for (idx, node) in root.children.enumerated() where !initialParentSet.contains(ObjectIdentifier(node)) {
            addedParents.append(.init(parentNode: node, newRootIndex: idx))
        }

        let addedAnnIds = Set(annotations.compactMap(\.id))
        var addedChildren: [BookAdditionDiff.AddedChild] = []
        for parent in affectedExistingParents {
            for (childIdx, child) in parent.children.enumerated() where child.annotation?.id.map(addedAnnIds.contains) == true {
                addedChildren.append(.init(annotationNode: child, parentNode: parent, newChildIndex: childIdx))
            }
        }

        return BookAdditionDiff(
            addedChildren: addedChildren,
            addedParents: addedParents,
            movedParents: movedParents
        )
    }

    private func calculateMovedParents(
        root: AnnotationNode,
        initialParentSet: Set<ObjectIdentifier>,
        initialParentIndices: [ObjectIdentifier: Int]
    ) -> [BookDeletionDiff.MovedParent] {
        guard sortOption.field == .createdAt else { return [] }
        var existingParents = root.children.filter { initialParentSet.contains(ObjectIdentifier($0)) }
        var cache = [ObjectIdentifier: Int64]()
        existingParents.sort { compareNodes($0, $1, cache: &cache) }

        var moved: [BookDeletionDiff.MovedParent] = []
        for (newIdx, node) in existingParents.enumerated() where initialParentIndices[ObjectIdentifier(node)] != newIdx {
            if let oldIdx = initialParentIndices[ObjectIdentifier(node)] {
                moved.append(.init(parentNode: node, oldIndex: oldIdx, newIndex: newIdx))
            }
        }
        root.children.sort { compareNodes($0, $1, cache: &cache) }
        return moved
    }

    // MARK: - Tree Rebuilding

    private func rebuildTree() {
        let root = AnnotationNode(title: "All Annotations", kind: .root)
        var anns = AnnotationStore.shared.loadAnnotations()

        if UserDefaults.standard.hideMissingBookAnnotations {
            let uniqueBkIds = Array(Set(anns.map(\.bkId)))
            let existingBkIds = Set(LibraryDataManager.shared.getBook(uniqueBkIds).map(\.id))
            anns = anns.filter { existingBkIds.contains($0.bkId) }
        }

        var bookTitles: [Int: String] = [:]
        let uniqueBkIds = Array(Set(anns.map(\.bkId)))
        for book in LibraryDataManager.shared.getBook(uniqueBkIds) {
            bookTitles[book.id] = book.book
        }

        switch groupingMode {
        case .book:
            populateBookTree(root: root, annotations: anns, bookTitles: bookTitles)
        case .tag:
            populateTagTree(root: root, annotations: anns, bookTitles: bookTitles)
        case .timeline:
            populateTimelineTree(root: root, annotations: anns, bookTitles: bookTitles)
        }

        sortNodeChildren(root)
        rootNode = root
    }

    private func populateBookTree(root: AnnotationNode, annotations: [Annotation], bookTitles: [Int: String]) {
        let grouped = Dictionary(grouping: annotations, by: { $0.bkId })

        for bkId in grouped.keys {
            let annsForBook = grouped[bkId] ?? []
            let bookTitle = bookTitles[bkId] ?? "Unknown Book (\(bkId))"
            let bookNode = AnnotationNode(
                title: bookTitle,
                kind: .book,
                bookId: bkId,
                bookTitle: bookTitle,
                normalizedBookTitle: bookTitle.normalizeArabic(false)
            )

            for ann in annsForBook {
                let child = AnnotationNode(
                    title: displayTitle(for: ann),
                    kind: .annotation,
                    annotation: ann,
                    bookTitle: bookTitle,
                    normalizedBookTitle: bookTitle.normalizeArabic(false)
                )
                bookNode.children.append(child)
            }

            root.children.append(bookNode)
        }
    }

    private func populateTagTree(root: AnnotationNode, annotations: [Annotation], bookTitles: [Int: String]) {
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
                let bookTitle = bookTitles[annotation.bkId]
                tagNode.children.append(
                    AnnotationNode(
                        title: displayTitle(for: annotation),
                        kind: .annotation,
                        annotation: annotation,
                        bookTitle: bookTitle,
                        normalizedBookTitle: bookTitle?.normalizeArabic(false)
                    )
                )
            }
            root.children.append(tagNode)
        }

        if !untagged.isEmpty {
            let untaggedNode = AnnotationNode(title: String(localized: .Annotation.untagged),
                                              kind: .untagged)
            for annotation in untagged {
                let bookTitle = bookTitles[annotation.bkId]
                untaggedNode.children.append(
                    AnnotationNode(
                        title: displayTitle(for: annotation),
                        kind: .annotation,
                        annotation: annotation,
                        bookTitle: bookTitle,
                        normalizedBookTitle: bookTitle?.normalizeArabic(false)
                    )
                )
            }
            root.children.append(untaggedNode)
        }
    }

    // MARK: - Sorting

    private func sortNodeChildren(_ node: AnnotationNode) {
        var maxCreatedAtCache = [ObjectIdentifier: Int64]()
        sortNodeChildrenInternal(node, cache: &maxCreatedAtCache)
    }

    private func sortNodeChildrenInternal(_ node: AnnotationNode, cache: inout [ObjectIdentifier: Int64]) {
        if !node.children.isEmpty {
            node.children.sort { compareNodes($0, $1, cache: &cache) }
        }
        for child in node.children {
            sortNodeChildrenInternal(child, cache: &cache)
        }
    }

    private func compareNodes(_ lhs: AnnotationNode, _ rhs: AnnotationNode) -> Bool {
        var cache = [ObjectIdentifier: Int64]()
        return compareNodes(lhs, rhs, cache: &cache)
    }

    private func compareNodes(_ lhs: AnnotationNode, _ rhs: AnnotationNode, cache: inout [ObjectIdentifier: Int64]) -> Bool {
        if let left = lhs.annotation, let right = rhs.annotation {
            return compareAnnotationProperties(left, right)
        }

        if lhs.annotation == nil, rhs.annotation == nil {
            return compareGroupNodes(lhs, rhs, cache: &cache)
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func compareAnnotationProperties(_ left: Annotation, _ right: Annotation) -> Bool {
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

    private func maxCreatedAt(for node: AnnotationNode, cache: inout [ObjectIdentifier: Int64]) -> Int64 {
        let id = ObjectIdentifier(node)
        if let cached = cache[id] { return cached }
        let maxTime = node.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
        cache[id] = maxTime
        return maxTime
    }

    private func compareGroupNodes(_ lhs: AnnotationNode, _ rhs: AnnotationNode, cache: inout [ObjectIdentifier: Int64]) -> Bool {
        if lhs.kind == .untagged { return false }
        if rhs.kind == .untagged { return true }

        if lhs.kind == .dateBucket, rhs.kind == .dateBucket {
            let leftTime = maxCreatedAt(for: lhs, cache: &cache)
            let rightTime = maxCreatedAt(for: rhs, cache: &cache)
            if leftTime != rightTime {
                let orderedAscending = leftTime < rightTime
                return sortOption.isAscending ? orderedAscending : !orderedAscending
            }
        }
        if sortOption.field == .createdAt {
            let leftLatest = maxCreatedAt(for: lhs, cache: &cache)
            let rightLatest = maxCreatedAt(for: rhs, cache: &cache)
            if leftLatest != rightLatest {
                let orderedAscending = leftLatest < rightLatest
                return sortOption.isAscending ? orderedAscending : !orderedAscending
            }
        }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        return sortOption.isAscending
            ? (titleOrder == .orderedAscending)
            : (titleOrder == .orderedDescending)
    }

    // MARK: - Book Mode Helpers

    private func resolveBookTitle(for bkId: Int) -> String? {
        LibraryDataManager.shared.getBook([bkId]).first?.book
    }

    private func findOrCreateBookNode(for bkId: Int, in root: AnnotationNode) -> AnnotationNode {
        if let existing = root.children.first(where: { node in
            if node.kind == .book, let nodeBkId = node.bookId, nodeBkId == bkId {
                return true
            }
            guard let firstChild = node.children.first,
                  let annotation = firstChild.annotation else { return false }
            return annotation.bkId == bkId
        }) {
            return existing
        }

        guard let book = LibraryDataManager.shared.getBook([bkId]).first else {
            let fallbackTitle = "Unknown Book (\(bkId))"
            let fallbackNode = AnnotationNode(
                title: fallbackTitle,
                kind: .book,
                bookId: bkId,
                bookTitle: fallbackTitle,
                normalizedBookTitle: fallbackTitle.normalizeArabic(false)
            )
            let idx = root.children.insertionIndex(for: fallbackNode, using: compareNodes)
            root.children.insert(fallbackNode, at: idx)
            return fallbackNode
        }

        let bookNode = AnnotationNode(
            title: book.book,
            kind: .book,
            bookId: bkId,
            bookTitle: book.book,
            normalizedBookTitle: book.book.normalizeArabic(false)
        )
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
        let addedEntries = processBatchTagAdditions(root: root, annotations: [annotation])
        return TagUpdateDiff(removed: [], added: addedEntries, updated: [])
    }

    private func updateAnnotationInTagTree(_ annotation: Annotation, root: AnnotationNode) -> TagUpdateDiff {
        performBatchTagTreeUpdate([annotation], root: root)
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

    private func insertAnnotationIntoContainer(
        _ annotation: Annotation,
        title: String,
        container: AnnotationNode,
        isContainerNew: Bool
    ) -> TagUpdateDiff.AddedEntry {
        let bTitle = resolveBookTitle(for: annotation.bkId)
        let newNode = AnnotationNode(
            title: title,
            kind: .annotation,
            annotation: annotation,
            bookTitle: bTitle,
            normalizedBookTitle: bTitle?.normalizeArabic(false)
        )
        let idx = container.children.insertionIndex(for: newNode, using: compareNodes)
        container.children.insert(newNode, at: idx)
        return .init(annotationNode: newNode, tagNode: container, tagNodeIsNew: isContainerNew)
    }

    private func insertAnnotation(
        _ annotation: Annotation,
        title: String,
        intoTag tag: String,
        root: AnnotationNode
    ) -> TagUpdateDiff.AddedEntry {
        if let existingTagNode = root.children.first(where: { $0.kind == .tag && $0.title == tag }) {
            return insertAnnotationIntoContainer(annotation, title: title, container: existingTagNode, isContainerNew: false)
        } else {
            let tagNode = AnnotationNode(title: tag, kind: .tag)
            let entry = insertAnnotationIntoContainer(annotation, title: title, container: tagNode, isContainerNew: true)
            let insertIdx = root.children.insertionIndex(for: tagNode, using: compareNodes)
            root.children.insert(tagNode, at: insertIdx)
            return entry
        }
    }

    private func insertAnnotationIntoUntagged(
        _ annotation: Annotation,
        title: String,
        root: AnnotationNode
    ) -> TagUpdateDiff.AddedEntry {
        if let untaggedNode = root.children.first(where: { $0.kind == .untagged }) {
            return insertAnnotationIntoContainer(annotation, title: title, container: untaggedNode, isContainerNew: false)
        } else {
            let untaggedNode = AnnotationNode(title: String(localized: .Annotation.untagged), kind: .untagged)
            let entry = insertAnnotationIntoContainer(annotation, title: title, container: untaggedNode, isContainerNew: true)
            root.children.append(untaggedNode)
            return entry
        }
    }

    private func pruneTagChildrenAndRecord(
        from tagNode: AnnotationNode,
        rootIndex: Int,
        indicesToRemove: [(node: AnnotationNode, index: Int)],
        singleEntryWhenEmpty: Bool = false
    ) -> [TagUpdateDiff.RemovedEntry] {
        guard !indicesToRemove.isEmpty else { return [] }

        var entries: [TagUpdateDiff.RemovedEntry] = []
        let becomesEmpty = indicesToRemove.count == tagNode.children.count

        if becomesEmpty, singleEntryWhenEmpty {
            if let first = indicesToRemove.first {
                entries.append(.init(
                    annotationNode: first.node,
                    tagNode: tagNode,
                    tagNodeBecomesEmpty: true,
                    oldIndex: rootIndex
                ))
            }
        } else {
            for item in indicesToRemove {
                entries.append(.init(
                    annotationNode: item.node,
                    tagNode: tagNode,
                    tagNodeBecomesEmpty: becomesEmpty,
                    oldIndex: becomesEmpty ? rootIndex : item.index
                ))
            }
        }

        for item in indicesToRemove.reversed() {
            tagNode.children.remove(at: item.index)
        }

        return entries
    }

    private func processBatchTagUpdates(
        root: AnnotationNode,
        updatedAnnsDict: [Int64: Annotation]
    ) -> (removed: [TagUpdateDiff.RemovedEntry], updated: [AnnotationNode]) {
        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        var updatedNodes: [AnnotationNode] = []

        for (rootIdx, tagNode) in root.children.enumerated() {
            var indicesToRemove: [(node: AnnotationNode, index: Int)] = []

            for (idx, child) in tagNode.children.enumerated() {
                guard let id = child.annotation?.id, let updatedAnn = updatedAnnsDict[id] else { continue }

                let newTags = Set(AnnotationRepository.shared.sanitizeTagNames(updatedAnn.tags))
                let title = displayTitle(for: updatedAnn)
                let shouldRemove = (tagNode.kind == .untagged) ? !newTags.isEmpty : !newTags.contains(tagNode.title)

                if shouldRemove {
                    indicesToRemove.append((node: child, index: idx))
                } else {
                    child.title = title
                    child.annotation = updatedAnn
                    updatedNodes.append(child)
                }
            }

            removedEntries.append(contentsOf: pruneTagChildrenAndRecord(
                from: tagNode,
                rootIndex: rootIdx,
                indicesToRemove: indicesToRemove,
                singleEntryWhenEmpty: true
            ))
        }
        return (removedEntries, updatedNodes)
    }

    func processBatchTagAdditions(
        root: AnnotationNode,
        annotations: [Annotation]
    ) -> [TagUpdateDiff.AddedEntry] {
        var addedEntries: [TagUpdateDiff.AddedEntry] = []
        for annotation in annotations {
            guard let id = annotation.id else { continue }
            let newTags = AnnotationRepository.shared.sanitizeTagNames(annotation.tags)
                .sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
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

        if sortOption.field == .createdAt {
            var seen = Set<ObjectIdentifier>()
            let newTagNodes = addedEntries.compactMap { entry -> AnnotationNode? in
                guard entry.tagNodeIsNew, entry.tagNode.kind == .tag,
                      seen.insert(ObjectIdentifier(entry.tagNode)).inserted
                else { return nil }
                return entry.tagNode
            }

            if !newTagNodes.isEmpty {
                root.children.removeAll { seen.contains(ObjectIdentifier($0)) }
                for tagNode in newTagNodes {
                    let newIdx = root.children.insertionIndex(for: tagNode, using: compareNodes)
                    root.children.insert(tagNode, at: newIdx)
                }
            }
        }

        return addedEntries
    }

    // MARK: - Timeline Mode Operations

    private func populateTimelineTree(root: AnnotationNode, annotations: [Annotation], bookTitles: [Int: String]) {
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
                let bookTitle = bookTitles[annotation.bkId]
                bucketNode.children.append(
                    AnnotationNode(
                        title: displayTitle(for: annotation),
                        kind: .annotation,
                        annotation: annotation,
                        bookTitle: bookTitle,
                        normalizedBookTitle: bookTitle?.normalizeArabic(false)
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
            let bTitle = resolveBookTitle(for: annotation.bkId)
            let newNode = AnnotationNode(
                title: title,
                kind: .annotation,
                annotation: annotation,
                bookTitle: bTitle,
                normalizedBookTitle: bTitle?.normalizeArabic(false)
            )
            newBucketNode.children.append(newNode)

            var cache = [ObjectIdentifier: Int64]()
            let insertIdx = root.children.insertionIndex(for: newBucketNode) { left, right in
                let leftTime = self.maxCreatedAt(for: left, cache: &cache)
                let rightTime = self.maxCreatedAt(for: right, cache: &cache)
                let orderedAscending = leftTime < rightTime
                return self.sortOption.isAscending ? orderedAscending : !orderedAscending
            }
            root.children.insert(newBucketNode, at: insertIdx)

            let entry = TagUpdateDiff.AddedEntry(annotationNode: newNode, tagNode: newBucketNode, tagNodeIsNew: true)
            return TagUpdateDiff(removed: [], added: [entry], updated: [])
        }
    }

    private func displayTitle(for annotation: Annotation) -> String {
        annotation.displayTitle
    }
}
