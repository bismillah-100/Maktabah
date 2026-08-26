//
//  AnnMgr+TagTree.swift
//  Maktabah
//

import Foundation

extension AnnotationManager {
    // MARK: - Add to Tag Tree

    func addAnnotationToTagTree(_ annotation: Annotation, uploadToCloudKit: Bool = true) {
        guard let root = _rootNode else {
            postChangeNotification(type: .added, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
            return
        }

        let tags = sanitizeTagNames(annotation.tags)
        let title = displayTitle(for: annotation)
        var addedEntries: [TagUpdateDiff.AddedEntry] = []

        if tags.isEmpty {
            addedEntries.append(insertAnnotationIntoUntagged(annotation, title: title, root: root))
        } else {
            for tag in tags {
                addedEntries.append(insertAnnotation(annotation, title: title, intoTag: tag, root: root))
            }
        }

        let diff = TagUpdateDiff(removed: [], added: addedEntries, updated: [])
        postChangeNotification(type: .added, annotation: annotation, diff: diff, uploadToCloudKit: uploadToCloudKit)
    }

    // MARK: - Update in Tag Tree

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

    func updateAnnotationInTagTree(_ annotation: Annotation, uploadToCloudKit: Bool = true) {
        guard let id = annotation.id, let root = _rootNode else {
            buildAnnotationTree()
            return
        }

        let title = displayTitle(for: annotation)
        let newTags = Set(sanitizeTagNames(annotation.tags))
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

        let diff = TagUpdateDiff(removed: removedEntries, added: addedEntries, updated: updatedNodes)
        postChangeNotification(type: .updated, annotation: annotation, diff: diff, uploadToCloudKit: uploadToCloudKit)
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

    // MARK: - Remove from Tag Tree

    @discardableResult
    func removeAnnotationFromTagTree(id: Int64) -> TagUpdateDiff? {
        guard let root = _rootNode else { return nil }

        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        for tagNode in root.children {
            if let entry = removeAnnotationFromTagNode(id: id, tagNode: tagNode, root: root) {
                removedEntries.append(entry)
            }
        }

        return TagUpdateDiff(removed: removedEntries, added: [], updated: [])
    }

    // MARK: - Delete Tag from Tree

    func deleteTagFromTree(
        tagName: String,
        normalizedName _: String,
        updatedAnnotations: [Annotation]
    ) {
        _treeQueue.async { [weak self] in
            guard let self, let root = _rootNode else { return }

            guard _groupingMode == .tag else {
                for ann in updatedAnnotations {
                    postChangeNotification(type: .updated, annotation: ann)
                }
                return
            }

            guard
                let tagNode = root.children.first(where: {
                    $0.kind == .tag && $0.title == tagName
                }),
                let tagIndex = root.children.firstIndex(where: { $0 === tagNode })
            else {
                buildAnnotationTree()
                return
            }

            let removedEntries = [
                TagUpdateDiff.RemovedEntry(
                    annotationNode: tagNode,
                    tagNode: tagNode,
                    tagNodeBecomesEmpty: true,
                    oldIndex: tagIndex
                ),
            ]

            root.children.remove(at: tagIndex)

            let nowUntagged = updatedAnnotations.filter(\.tags.isEmpty)
            var addedEntries: [TagUpdateDiff.AddedEntry] = []

            if !nowUntagged.isEmpty {
                for (i, ann) in nowUntagged.enumerated() {
                    let entry = insertAnnotationIntoUntagged(ann, title: displayTitle(for: ann), root: root)
                    if i == 0 || !entry.tagNodeIsNew {
                        addedEntries.append(entry)
                    }
                }
            }

            let diff = TagUpdateDiff(removed: removedEntries, added: addedEntries, updated: [])
            let representativeId = updatedAnnotations.first?.id ?? -1
            postChangeNotification(
                type: .updated,
                annotation: updatedAnnotations.first,
                annotationsToSync: updatedAnnotations,
                annotationId: representativeId,
                diff: diff
            )
        }
    }

    // MARK: - Batch Tag Tree Operations

    func updateAnnotationsInTagTree(_ annotations: [Annotation]) {
        for annotation in annotations {
            updateAnnotationInTagTree(annotation, uploadToCloudKit: false)
        }
    }

    func performBatchTagTreeUpdate(
        for updatedAnnotations: [Annotation],
        representativeId: Int64
    ) {
        performBatchTagTreeUpdate(updatedAnnotations, uploadToCloudKit: false)

        let diff = TagUpdateDiff(removed: [], added: [], updated: [])
        DispatchQueue.main.async {
            self.postChangeNotification(
                type: .updated,
                annotation: updatedAnnotations.first,
                annotationsToSync: updatedAnnotations,
                annotationId: representativeId,
                diff: diff
            )
        }
    }

    // MARK: - Batch Tag Tree Update

    func performBatchTagTreeUpdate(_ annotations: [Annotation], uploadToCloudKit: Bool = true) {
        guard let root = _rootNode else { return }

        let updatedAnnsDict = Dictionary(uniqueKeysWithValues: annotations.compactMap { ann in ann.id.map { ($0, ann) } })
        let (removedEntries, updatedNodes) = processBatchTagUpdates(root: root, updatedAnnsDict: updatedAnnsDict)

        root.children.removeAll { tagNode in
            tagNode.children.isEmpty && tagNode.kind != .root
        }

        let addedEntries = processBatchTagAdditions(root: root, annotations: annotations)

        if !removedEntries.isEmpty || !addedEntries.isEmpty || !updatedNodes.isEmpty {
            let diff = TagUpdateDiff(removed: removedEntries, added: addedEntries, updated: updatedNodes)
            let representativeId = annotations.first?.id ?? -1
            postChangeNotification(
                type: .updated,
                annotation: annotations.first,
                annotationsToSync: annotations,
                annotationId: representativeId,
                diff: diff,
                uploadToCloudKit: uploadToCloudKit
            )
        }
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

                let newTags = Set(sanitizeTagNames(updatedAnn.tags))
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
            let newTags = Set(sanitizeTagNames(annotation.tags))
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
}
