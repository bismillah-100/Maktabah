//
//  AnnotationManager+TagTree.swift
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
            let isNew: Bool
            let untaggedNode: AnnotationNode
            if let existing = root.children.first(where: { $0.kind == .untagged }) {
                untaggedNode = existing
                isNew = false
            } else {
                let fresh = AnnotationNode(title: "Untagged".localized, kind: .untagged)
                root.children.append(fresh)
                untaggedNode = fresh
                isNew = true
            }

            let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
            let idx = untaggedNode.children.insertionIndex(for: newNode, using: compareNodes)
            untaggedNode.children.insert(newNode, at: idx)
            addedEntries.append(.init(annotationNode: newNode, tagNode: untaggedNode, tagNodeIsNew: isNew))
        } else {
            for tag in tags {
                if let tagNode = root.children.first(where: { $0.kind == .tag && $0.title == tag }) {
                    let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
                    let idx = tagNode.children.insertionIndex(for: newNode, using: compareNodes)
                    tagNode.children.insert(newNode, at: idx)
                    addedEntries.append(.init(annotationNode: newNode, tagNode: tagNode, tagNodeIsNew: false))
                } else {
                    let tagNode = AnnotationNode(title: tag, kind: .tag)
                    let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
                    tagNode.children.append(newNode)

                    let insertIdx =
                        root.children.firstIndex(where: { node in
                            guard node.kind == .tag else { return node.kind == .untagged }
                            return tag.localizedCaseInsensitiveCompare(node.title) == .orderedAscending
                        })
                        ?? (root.children.firstIndex(where: { $0.kind == .untagged })
                            ?? root.children.endIndex)

                    root.children.insert(tagNode, at: insertIdx)
                    addedEntries.append(.init(annotationNode: newNode, tagNode: tagNode, tagNodeIsNew: true))
                }
            }
        }

        let diff = TagUpdateDiff(removed: [], added: addedEntries, updated: [])
        postChangeNotification(type: .added, annotation: annotation, diff: diff, uploadToCloudKit: uploadToCloudKit)
    }

    // MARK: - Update in Tag Tree

    func updateAnnotationInTagTree(_ annotation: Annotation, uploadToCloudKit: Bool = true) {
        guard let id = annotation.id, let root = _rootNode else {
            buildAnnotationTree()
            return
        }

        let title = displayTitle(for: annotation)
        let newTags = Set(sanitizeTagNames(annotation.tags))

        var existingTagNodes: [AnnotationNode] = []
        for tagNode in root.children {
            if tagNode.children.contains(where: { $0.annotation?.id == id }) {
                existingTagNodes.append(tagNode)
            }
        }

        let existingTagNames = Set(existingTagNodes.compactMap { $0.kind == .tag ? $0.title : nil })
        let isCurrentlyUntagged = existingTagNodes.contains(where: { $0.kind == .untagged })

        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        var addedEntries: [TagUpdateDiff.AddedEntry] = []
        var updatedNodes: [AnnotationNode] = []

        // Hapus dari tag yang sudah tidak ada
        for tagNode in existingTagNodes where existingTagNames.subtracting(newTags).contains(tagNode.title) {
            if let annIdx = tagNode.children.firstIndex(where: { $0.annotation?.id == id }) {
                let annNode = tagNode.children[annIdx]
                let becomesEmpty = tagNode.children.count == 1
                let oldIndex = becomesEmpty ? (root.children.firstIndex(where: { $0 === tagNode }) ?? -1) : annIdx

                removedEntries.append(.init(
                    annotationNode: annNode,
                    tagNode: tagNode,
                    tagNodeBecomesEmpty: becomesEmpty,
                    oldIndex: oldIndex
                ))

                tagNode.children.remove(at: annIdx)
                if becomesEmpty {
                    root.children.removeAll { $0 === tagNode }
                }
            }
        }

        // Hapus dari untagged jika sekarang punya tag
        if isCurrentlyUntagged, !newTags.isEmpty {
            if let untaggedNode = root.children.first(where: { $0.kind == .untagged }) {
                if let annIdx = untaggedNode.children.firstIndex(where: { $0.annotation?.id == id }) {
                    let annNode = untaggedNode.children[annIdx]
                    let becomesEmpty = untaggedNode.children.count == 1
                    let oldIndex = becomesEmpty ? (root.children.firstIndex(where: { $0 === untaggedNode }) ?? -1) : annIdx

                    removedEntries.append(.init(
                        annotationNode: annNode,
                        tagNode: untaggedNode,
                        tagNodeBecomesEmpty: becomesEmpty,
                        oldIndex: oldIndex
                    ))

                    untaggedNode.children.remove(at: annIdx)
                    if becomesEmpty {
                        root.children.removeAll { $0 === untaggedNode }
                    }
                }
            }
        }

        // Update node yang masih ada (tag tidak berubah, hanya teks/warna)
        for tagNode in root.children where existingTagNames.intersection(newTags).contains(tagNode.title) {
            if let node = tagNode.children.first(where: { $0.annotation?.id == id }) {
                node.title = title
                node.annotation = annotation
                updatedNodes.append(node)
            }
        }

        // Tambah ke tag baru
        for tag in newTags.subtracting(existingTagNames) {
            if let tagNode = root.children.first(where: { $0.kind == .tag && $0.title == tag }) {
                let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
                let idx = tagNode.children.insertionIndex(for: newNode, using: compareNodes)
                tagNode.children.insert(newNode, at: idx)
                addedEntries.append(.init(annotationNode: newNode, tagNode: tagNode, tagNodeIsNew: false))
            } else {
                let tagNode = AnnotationNode(title: tag, kind: .tag)
                let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
                tagNode.children.append(newNode)
                let insertIdx =
                    root.children.firstIndex(where: { node in
                        guard node.kind == .tag else { return node.kind == .untagged }
                        return tag.localizedCaseInsensitiveCompare(node.title) == .orderedAscending
                    })
                    ?? (root.children.firstIndex(where: { $0.kind == .untagged })
                        ?? root.children.endIndex)
                root.children.insert(tagNode, at: insertIdx)
                addedEntries.append(.init(annotationNode: newNode, tagNode: tagNode, tagNodeIsNew: true))
            }
        }

        // Masuk untagged jika sekarang tidak ada tag
        if newTags.isEmpty, !isCurrentlyUntagged {
            if let untaggedNode = root.children.first(where: { $0.kind == .untagged }) {
                let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
                let idx = untaggedNode.children.insertionIndex(for: newNode, using: compareNodes)
                untaggedNode.children.insert(newNode, at: idx)
                addedEntries.append(.init(annotationNode: newNode, tagNode: untaggedNode, tagNodeIsNew: false))
            } else {
                let untaggedNode = AnnotationNode(title: "Untagged".localized, kind: .untagged)
                let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
                untaggedNode.children.append(newNode)
                root.children.append(untaggedNode)
                addedEntries.append(.init(annotationNode: newNode, tagNode: untaggedNode, tagNodeIsNew: true))
            }
        }

        let diff = TagUpdateDiff(removed: removedEntries, added: addedEntries, updated: updatedNodes)
        postChangeNotification(type: .updated, annotation: annotation, diff: diff, uploadToCloudKit: uploadToCloudKit)
    }

    // MARK: - Remove from Tag Tree

    @discardableResult
    func removeAnnotationFromTagTree(id: Int64) -> TagUpdateDiff? {
        guard let root = _rootNode else { return nil }

        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        for tagNode in root.children {
            guard let annIdx = tagNode.children.firstIndex(where: { $0.annotation?.id == id }) else {
                continue
            }

            let annNode = tagNode.children[annIdx]
            let becomesEmpty = tagNode.children.count == 1
            let oldIndex = becomesEmpty ? (root.children.firstIndex(where: { $0 === tagNode }) ?? -1) : annIdx

            removedEntries.append(.init(
                annotationNode: annNode,
                tagNode: tagNode,
                tagNodeBecomesEmpty: becomesEmpty,
                oldIndex: oldIndex
            ))

            tagNode.children.remove(at: annIdx)
        }

        for entry in removedEntries where entry.tagNodeBecomesEmpty {
            root.children.removeAll { $0 === entry.tagNode }
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
                // Book mode: tidak ada tag node di tree.
                // Cukup post .updated untuk masing-masing anotasi agar badge tag ter-refresh.
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

            // Cukup satu entry untuk menghapus seluruh tag node dari root
            let removedEntries = [
                TagUpdateDiff.RemovedEntry(
                    annotationNode: tagNode,
                    tagNode: tagNode,
                    tagNodeBecomesEmpty: true,
                    oldIndex: tagIndex
                )
            ]

            root.children.remove(at: tagIndex)

            // Anotasi yang kini tidak punya tag → pindah ke Untagged
            let nowUntagged = updatedAnnotations.filter(\.tags.isEmpty)
            var addedEntries: [TagUpdateDiff.AddedEntry] = []

            if !nowUntagged.isEmpty {
                let isNewUntaggedNode: Bool
                let untaggedNode: AnnotationNode
                if let existing = root.children.first(where: { $0.kind == .untagged }) {
                    untaggedNode = existing
                    isNewUntaggedNode = false
                } else {
                    let fresh = AnnotationNode(title: "Untagged".localized, kind: .untagged)
                    root.children.append(fresh)
                    untaggedNode = fresh
                    isNewUntaggedNode = true
                }

                for (i, ann) in nowUntagged.enumerated() {
                    let newNode = AnnotationNode(
                        title: displayTitle(for: ann), kind: .annotation, annotation: ann
                    )
                    let idx = untaggedNode.children.insertionIndex(for: newNode, using: compareNodes)
                    untaggedNode.children.insert(newNode, at: idx)

                    if isNewUntaggedNode {
                        // Hanya satu entry yang dibutuhkan untuk DataSource insert node baru
                        if i == 0 {
                            addedEntries.append(.init(
                                annotationNode: newNode,
                                tagNode: untaggedNode,
                                tagNodeIsNew: true
                            ))
                        }
                    } else {
                        addedEntries.append(.init(
                            annotationNode: newNode,
                            tagNode: untaggedNode,
                            tagNodeIsNew: false
                        ))
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

    // MARK: - Batch Tag Tree Update

    func performBatchTagTreeUpdate(_ annotations: [Annotation], uploadToCloudKit: Bool = true) {
        guard let root = _rootNode else { return }

        var removedEntries: [TagUpdateDiff.RemovedEntry] = []
        var addedEntries: [TagUpdateDiff.AddedEntry] = []
        var updatedNodes: [AnnotationNode] = []

        let updatedAnnsDict = Dictionary(uniqueKeysWithValues: annotations.compactMap { ann in ann.id.map { ($0, ann) } })

        for tagNode in root.children {
            var indicesToRemove: [Int] = []

            for (idx, child) in tagNode.children.enumerated() {
                guard let id = child.annotation?.id, let updatedAnn = updatedAnnsDict[id] else { continue }

                let newTags = Set(sanitizeTagNames(updatedAnn.tags))
                let title = displayTitle(for: updatedAnn)

                let shouldRemove: Bool
                if tagNode.kind == .untagged {
                    shouldRemove = !newTags.isEmpty
                } else {
                    shouldRemove = !newTags.contains(tagNode.title)
                }

                if shouldRemove {
                    indicesToRemove.append(idx)
                } else {
                    child.title = title
                    child.annotation = updatedAnn
                    updatedNodes.append(child)
                }
            }

            if !indicesToRemove.isEmpty {
                let becomesEmpty = indicesToRemove.count == tagNode.children.count
                let oldTagIndex = root.children.firstIndex(where: { $0 === tagNode }) ?? -1

                for idx in indicesToRemove {
                    removedEntries.append(.init(
                        annotationNode: tagNode.children[idx],
                        tagNode: tagNode,
                        tagNodeBecomesEmpty: becomesEmpty,
                        oldIndex: becomesEmpty ? oldTagIndex : idx
                    ))
                }

                for idx in indicesToRemove.reversed() {
                    tagNode.children.remove(at: idx)
                }
            }
        }

        root.children.removeAll { tagNode in
            tagNode.children.isEmpty && tagNode.kind != .root
        }

        for annotation in annotations {
            guard let id = annotation.id else { continue }
            let newTags = Set(sanitizeTagNames(annotation.tags))
            let title = displayTitle(for: annotation)

            if newTags.isEmpty {
                if let untaggedNode = root.children.first(where: { $0.kind == .untagged }) {
                    if !untaggedNode.children.contains(where: { $0.annotation?.id == id }) {
                        let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
                        let idx = untaggedNode.children.insertionIndex(for: newNode, using: compareNodes)
                        untaggedNode.children.insert(newNode, at: idx)
                        addedEntries.append(.init(annotationNode: newNode, tagNode: untaggedNode, tagNodeIsNew: false))
                    }
                } else {
                    let untaggedNode = AnnotationNode(title: String(localized: "Untagged"), kind: .untagged)
                    let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
                    untaggedNode.children.append(newNode)
                    root.children.append(untaggedNode)
                    addedEntries.append(.init(annotationNode: newNode, tagNode: untaggedNode, tagNodeIsNew: true))
                }
            } else {
                for tag in newTags {
                    if let tagNode = root.children.first(where: { $0.kind == .tag && $0.title == tag }) {
                        if !tagNode.children.contains(where: { $0.annotation?.id == id }) {
                            let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
                            let idx = tagNode.children.insertionIndex(for: newNode, using: compareNodes)
                            tagNode.children.insert(newNode, at: idx)
                            addedEntries.append(.init(annotationNode: newNode, tagNode: tagNode, tagNodeIsNew: false))
                        }
                    } else {
                        let tagNode = AnnotationNode(title: tag, kind: .tag)
                        let newNode = AnnotationNode(title: title, kind: .annotation, annotation: annotation)
                        tagNode.children.append(newNode)

                        let insertIdx = root.children.firstIndex(where: { node in
                            guard node.kind == .tag else { return node.kind == .untagged }
                            return tag.localizedCaseInsensitiveCompare(node.title) == .orderedAscending
                        }) ?? (root.children.firstIndex(where: { $0.kind == .untagged }) ?? root.children.endIndex)

                        root.children.insert(tagNode, at: insertIdx)
                        addedEntries.append(.init(annotationNode: newNode, tagNode: tagNode, tagNodeIsNew: true))
                    }
                }
            }
        }

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
}
