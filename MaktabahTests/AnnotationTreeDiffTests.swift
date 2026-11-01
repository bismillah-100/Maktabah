//
//  AnnotationTreeDiffTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 01/11/26.
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("Annotation Tree Diff & Section Identity Tests")
struct AnnotationTreeDiffTests {
    @Test("SwiftUIAnnotationNode produces unique ids for book nodes with different bookIds even if titles match")
    func testUniqueSectionIdsForMatchingTitles() {
        let node1 = AnnotationNode(title: "Unknown Book", kind: .book, bookId: 101)
        let node2 = AnnotationNode(title: "Unknown Book", kind: .book, bookId: 202)

        let id1 = SwiftUIAnnotationNode.id(from: node1)
        let id2 = SwiftUIAnnotationNode.id(from: node2)

        #expect(id1 != id2)
        #expect(id1 == "group-book-101")
        #expect(id2 == "group-book-202")
    }

    @Test("SwiftUIAnnotationNode fallback uses first child annotation bkId if bookId is not directly set")
    func testFallbackToChildAnnotationBkId() {
        let ann1 = Annotation(
            id: 1,
            bkId: 303,
            contentId: 1,
            range: NSRange(location: 0, length: 5),
            rangeDiacritics: NSRange(location: 0, length: 5),
            colorHex: "#FF0000",
            type: .highlight,
            createdAt: 1000,
            context: "Sample context 1",
            page: 1,
            part: 1
        )
        let child1 = AnnotationNode(title: "Child 1", kind: .annotation, annotation: ann1)
        let bookNode = AnnotationNode(title: "Unknown Book", kind: .book)
        bookNode.children.append(child1)

        let sectionId = SwiftUIAnnotationNode.id(from: bookNode)
        #expect(sectionId == "group-book-303")
    }

    @Test("SwiftUIAnnotationNode hierarchy maps children with parentId prefix to guarantee uniqueness")
    func testChildrenIdsWithParentPrefix() {
        let ann1 = Annotation(
            id: 42,
            bkId: 505,
            contentId: 1,
            range: NSRange(location: 0, length: 5),
            rangeDiacritics: NSRange(location: 0, length: 5),
            colorHex: "#00FF00",
            type: .highlight,
            note: "Sample note",
            createdAt: 2000,
            context: "Sample context 2",
            page: 1,
            part: 1
        )
        let childNode = AnnotationNode(title: "Child", kind: .annotation, annotation: ann1)
        let bookNode = AnnotationNode(title: "Custom Book", kind: .book, bookId: 505)
        bookNode.children.append(childNode)

        let swiftUIGroup = SwiftUIAnnotationNode(from: bookNode)
        #expect(swiftUIGroup.id == "group-book-505")
        #expect(swiftUIGroup.children?.count == 1)
        #expect(swiftUIGroup.children?.first?.id == "group-book-505-ann-42")
    }

    @Test("AnnotationTreeBuilder.withRootNode is reentrant-safe and AnnotationViewModel.swiftUINodes does not deadlock")
    @MainActor
    func testWithRootNodeReentrancyAndViewModelSwiftUINodes() {
        let nestedResult = AnnotationTreeBuilder.shared.withRootNode { outerRoot in
            AnnotationTreeBuilder.shared.withRootNode { innerRoot in
                outerRoot === innerRoot
            }
        }
        #expect(nestedResult)

        let vm = AnnotationViewModel()
        let nodes = vm.swiftUINodes
        let ids = nodes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
