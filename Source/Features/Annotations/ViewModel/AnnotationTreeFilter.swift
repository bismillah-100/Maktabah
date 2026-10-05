//
//  AnnotationTreeFilter.swift
//  Maktabah
//
//  Created by Antigravity on 05/10/26.
//

import Foundation

enum AnnotationTreeFilter {
    static func filter(
        nodes: [AnnotationNode],
        selectedTags: Set<String>,
        tagFilterMode: TagFilterMode,
        searchText: String,
        searchScope: AnnotationSearchScope
    ) -> [AnnotationNode] {
        var result = nodes

        if !selectedTags.isEmpty {
            result = filterByTags(result, tags: selectedTags, mode: tagFilterMode)
        }

        if !searchText.isEmpty {
            result = filterByQuery(result, query: searchText, scope: searchScope)
        }

        return result
    }

    static func filterByTags(
        _ nodes: [AnnotationNode],
        tags: Set<String>,
        mode: TagFilterMode
    ) -> [AnnotationNode] {
        guard !tags.isEmpty else { return nodes }
        var result: [AnnotationNode] = []
        for node in nodes {
            if node.kind == .annotation, let ann = node.annotation {
                let annTags = Set(ann.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                let matches = mode == .and
                    ? tags.allSatisfy { annTags.contains($0) }
                    : !tags.isDisjoint(with: annTags)
                if matches {
                    result.append(node)
                }
            } else {
                let filteredChildren = filterByTags(node.children, tags: tags, mode: mode)
                if !filteredChildren.isEmpty {
                    let copy = AnnotationNode(
                        title: node.title,
                        kind: node.kind,
                        annotation: nil,
                        bookTitle: node.bookTitle,
                        normalizedBookTitle: node.normalizedBookTitle
                    )
                    copy.children = filteredChildren
                    result.append(copy)
                }
            }
        }
        return result
    }

    static func filterByQuery(
        _ nodes: [AnnotationNode],
        query: String,
        scope: AnnotationSearchScope
    ) -> [AnnotationNode] {
        guard !query.isEmpty else { return nodes }
        let normalizedQuery = query.normalizeArabic(false)
        return filterNodesRecursive(nodes, with: normalizedQuery, scope: scope)
    }

    private static func filterNodesRecursive(
        _ nodes: [AnnotationNode],
        with normalizedQuery: String,
        scope: AnnotationSearchScope
    ) -> [AnnotationNode] {
        var result: [AnnotationNode] = []

        for node in nodes {
            let matchingChildren = node.children.isEmpty ? [] : filterNodesRecursive(node.children, with: normalizedQuery, scope: scope)
            let matchesSelf = nodeMatchesQuery(node, query: normalizedQuery, scope: scope)

            if matchesSelf {
                let copy = AnnotationNode(
                    title: node.title,
                    kind: node.kind,
                    annotation: node.annotation,
                    bookTitle: node.bookTitle,
                    normalizedBookTitle: node.normalizedBookTitle
                )
                copy.children = node.children
                result.append(copy)
            } else if !matchingChildren.isEmpty {
                let copy = AnnotationNode(
                    title: node.title,
                    kind: node.kind,
                    annotation: node.annotation,
                    bookTitle: node.bookTitle,
                    normalizedBookTitle: node.normalizedBookTitle
                )
                copy.children = matchingChildren
                result.append(copy)
            }
        }
        return result
    }

    private static func nodeMatchesQuery(
        _ node: AnnotationNode,
        query: String,
        scope: AnnotationSearchScope
    ) -> Bool {
        if node.kind == .annotation {
            guard let ann = node.annotation else { return false }
            let bookTitle = node.normalizedBookTitle ?? node.bookTitle ?? ""
            return annotationMatchesQuery(ann, query: query, scope: scope, bookTitle: bookTitle)
        } else {
            return groupNodeMatchesQuery(node, query: query, scope: scope)
        }
    }

    private static func annotationMatchesQuery(
        _ ann: Annotation,
        query: String,
        scope: AnnotationSearchScope,
        bookTitle: String
    ) -> Bool {
        switch scope {
        case .all:
            if !bookTitle.isEmpty, bookTitle.localizedStandardContains(query) { return true }
            if ann.context.normalizeArabic(false).localizedStandardContains(query) { return true }
            if let note = ann.note, note.normalizeArabic(false).localizedStandardContains(query) { return true }
            return ann.tags.contains { $0.normalizeArabic(false).localizedStandardContains(query) }

        case .book:
            return !bookTitle.isEmpty && bookTitle.localizedStandardContains(query)

        case .context:
            return ann.context.normalizeArabic(false).localizedStandardContains(query)

        case .note:
            guard let note = ann.note else { return false }
            return note.normalizeArabic(false).localizedStandardContains(query)

        case .tag:
            return ann.tags.contains { $0.normalizeArabic(false).localizedStandardContains(query) }
        }
    }

    private static func groupNodeMatchesQuery(
        _ node: AnnotationNode,
        query: String,
        scope: AnnotationSearchScope
    ) -> Bool {
        let normalizedTitle = node.title.normalizeArabic(false)
        switch scope {
        case .all:
            return normalizedTitle.localizedStandardContains(query)
        case .book:
            return node.kind == .book && normalizedTitle.localizedStandardContains(query)
        case .tag:
            return (node.kind == .tag || node.kind == .untagged) && normalizedTitle.localizedStandardContains(query)
        case .context, .note:
            return false
        }
    }

    static func availableTags(
        for tags: Set<String>,
        in rootNodes: [AnnotationNode],
        allTags: [String],
        mode: TagFilterMode
    ) -> [String] {
        guard mode == .and, !tags.isEmpty else {
            return allTags
        }

        var coOccurringTags = Set(tags)
        let matchingNodes = filterByTags(rootNodes, tags: tags, mode: mode)
        gatherTags(from: matchingNodes, into: &coOccurringTags)
        return coOccurringTags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func gatherTags(from nodes: [AnnotationNode], into set: inout Set<String>) {
        for node in nodes {
            if let ann = node.annotation {
                for tag in ann.tags {
                    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        set.insert(trimmed)
                    }
                }
            }
            if !node.children.isEmpty {
                gatherTags(from: node.children, into: &set)
            }
        }
    }
}
