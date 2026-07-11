//
//  AnnotationManager+Tree.swift
//  Maktabah
//

import Foundation

extension AnnotationManager {
    // MARK: - Build Tree

    func buildAnnotationTree() {
        _treeQueue.async { [weak self] in
            guard let self else { return }

            let root = AnnotationNode(title: "All Annotations", kind: .root)
            var anns = loadAnnotations()

            if UserDefaults.standard.hideMissingBookAnnotations {
                let uniqueBkIds = Set(anns.map { $0.bkId })
                let existingBkIds = Set(uniqueBkIds.filter { !LibraryDataManager.shared.getBook([$0]).isEmpty })
                anns = anns.filter { existingBkIds.contains($0.bkId) }
            }

            switch _groupingMode {
            case .book:
                populateBookTree(root: root, annotations: anns)
            case .tag:
                populateTagTree(root: root, annotations: anns)
            }

            sortNodeChildren(root)

            _rootNode = root

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .annotationTreeDidUpdate,
                    object: self
                )
            }
        }
    }

    // MARK: - Invalidate / Grouping

    func invalidateTree() {
        _treeQueue.async { [weak self] in
            self?._rootNode = nil
        }
    }

    func updateGroupingMode(_ mode: AnnotationGroupingMode) {
        _groupingMode = mode
        invalidateTree()
        buildAnnotationTree()
    }

    // MARK: - Sorting

    func updateSorting(field: AnnotationSortField, isAscending: Bool) {
        _treeQueue.async { [weak self] in
            guard let self else { return }
            _sortOption = .init(field: field, isAscending: isAscending)
            guard let root = _rootNode else { return }
            sortNodeChildren(root)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .annotationTreeDidUpdate, object: self)
            }
        }
    }

    func sortNodeChildren(_ node: AnnotationNode) {
        if !node.children.isEmpty {
            node.children.sort(by: compareNodes)
        }
        for child in node.children {
            sortNodeChildren(child)
        }
    }

    func compareNodes(_ lhs: AnnotationNode, _ rhs: AnnotationNode) -> Bool {
        // KASUS 1: Anotasi (Item di dalam buku)
        if let left = lhs.annotation, let right = rhs.annotation {
            let orderedAscending: Bool
            switch _sortOption.field {
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
            return _sortOption.isAscending ? orderedAscending : !orderedAscending
        }

        // KASUS 2: Buku (Parent Nodes)
        if lhs.annotation == nil, rhs.annotation == nil {
            if _sortOption.field == .createdAt {
                let leftLatest = lhs.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
                let rightLatest = rhs.children.compactMap { $0.annotation?.createdAt }.max() ?? 0
                if leftLatest != rightLatest {
                    let orderedAscending = leftLatest < rightLatest
                    return _sortOption.isAscending ? orderedAscending : !orderedAscending
                }
            }
            // Selain Date Created: SELALU urutkan Buku berdasarkan Judul A-Z
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    // MARK: - Tree Mutations (Book Mode)

    func addAnnotationToTree(_ annotation: Annotation, uploadToCloudKit: Bool = true) {
        _treeQueue.async { [weak self] in
            guard let self else { return }
            guard _groupingMode == .book else {
                addAnnotationToTagTree(annotation, uploadToCloudKit: uploadToCloudKit)
                return
            }
            guard let root = _rootNode else {
                postChangeNotification(type: .added, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
                return
            }

            let bookNode = findOrCreateBookNode(for: annotation.bkId, in: root)

            let displayTitle: String = if let note = annotation.note, !note.isEmpty {
                note
            } else {
                annotation.context
            }

            let annotationNode = AnnotationNode(
                title: displayTitle,
                kind: .annotation,
                annotation: annotation
            )

            let index = bookNode.children.insertionIndex(for: annotationNode, using: compareNodes)
            bookNode.children.insert(annotationNode, at: index)

            var oldParentIdx: Int?
            var newParentIdx: Int?

            if _sortOption.field == .createdAt {
                if let oldIndex = root.children.firstIndex(where: { $0 === bookNode }) {
                    oldParentIdx = oldIndex
                    root.children.remove(at: oldIndex)
                }
                let newIndex = root.children.insertionIndex(for: bookNode, using: compareNodes)
                root.children.insert(bookNode, at: newIndex)
                newParentIdx = newIndex
            }

            postChangeNotification(type: .added, annotation: annotation, oldParentIndex: oldParentIdx, newParentIndex: newParentIdx, uploadToCloudKit: uploadToCloudKit)
        }
    }

    func updateAnnotationInTree(_ annotation: Annotation, uploadToCloudKit: Bool = true) {
        _treeQueue.async { [weak self] in
            guard let self else { return }
            guard _groupingMode == .book else {
                updateAnnotationInTagTree(annotation, uploadToCloudKit: uploadToCloudKit)
                return
            }
            guard let annotationId = annotation.id,
                  let node = findAnnotationNode(by: annotationId)
            else {
                postChangeNotification(type: .updated, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
                return
            }

            if let note = annotation.note, !note.isEmpty {
                node.title = note
            } else {
                node.title = annotation.context
            }
            node.annotation = annotation

            postChangeNotification(type: .updated, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
        }
    }

    func removeAnnotationFromTree(id: Int64, deletedAnnotation: Annotation?, uploadToCloudKit: Bool = true) {
        _treeQueue.async { [weak self] in
            guard let self else { return }
            guard _groupingMode == .book else {
                let diff = removeAnnotationFromTagTree(id: id)
                postChangeNotification(type: .deleted, annotation: deletedAnnotation, annotationId: id, diff: diff, uploadToCloudKit: uploadToCloudKit)
                return
            }
            guard let root = _rootNode else {
                postChangeNotification(type: .deleted, annotation: deletedAnnotation, annotationId: id, uploadToCloudKit: uploadToCloudKit)
                return
            }

            for bookNode in root.children {
                if let index = bookNode.children.firstIndex(where: { $0.annotation?.id == id }) {
                    bookNode.children.remove(at: index)

                    var oldParentIdx: Int?
                    var newParentIdx: Int?

                    if bookNode.children.isEmpty {
                        if let bookIndex = root.children.firstIndex(where: { $0 === bookNode }) {
                            root.children.remove(at: bookIndex)
                        }
                    } else if _sortOption.field == .createdAt {
                        if let oldIdx = root.children.firstIndex(where: { $0 === bookNode }) {
                            oldParentIdx = oldIdx
                            root.children.remove(at: oldIdx)
                        }
                        let newIdx = root.children.insertionIndex(for: bookNode, using: compareNodes)
                        root.children.insert(bookNode, at: newIdx)
                        newParentIdx = newIdx
                    }

                    postChangeNotification(type: .deleted, annotation: deletedAnnotation, annotationId: id, oldParentIndex: oldParentIdx, newParentIndex: newParentIdx, uploadToCloudKit: uploadToCloudKit)
                    return
                }
            }

            postChangeNotification(type: .deleted, annotation: deletedAnnotation, annotationId: id, uploadToCloudKit: uploadToCloudKit)
        }
    }

    // MARK: - Private Tree Helpers

    func findOrCreateBookNode(for bkId: Int, in root: AnnotationNode) -> AnnotationNode {
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

    func findAnnotationNode(by id: Int64) -> AnnotationNode? {
        guard let root = _rootNode else { return nil }

        for bookNode in root.children {
            if let found = bookNode.children.first(where: { $0.annotation?.id == id }) {
                return found
            }
        }
        return nil
    }

    // MARK: - Tree Population

    func populateBookTree(root: AnnotationNode, annotations: [Annotation]) {
        let grouped = Dictionary(grouping: annotations, by: { $0.bkId })

        for bkId in grouped.keys {
            let annsForBook = grouped[bkId] ?? []
            let bookTitle = LibraryDataManager
                .shared.getBook([bkId]).first?.book ?? "Unknown Book" + " (\(bkId))"
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

    func populateTagTree(root: AnnotationNode, annotations: [Annotation]) {
        var grouped: [String: [Annotation]] = [:]
        var untagged: [Annotation] = []

        for annotation in annotations {
            let tags = sanitizeTagNames(annotation.tags)
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
            let untaggedNode = AnnotationNode(title: "Untagged".localized, kind: .untagged)
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

    // MARK: - Shared Helpers

    func displayTitle(for annotation: Annotation) -> String {
        if let note = annotation.note, !note.isEmpty {
            return note
        }
        return annotation.context
    }

    func pushRecentColor(_ annotation: Annotation) {
        if annotation.type == .highlight,
           let color = PlatformColor(hex: annotation.colorHex)
        {
            TextViewState.shared.pushRecentHighlightColor(color)
        }
    }
}
