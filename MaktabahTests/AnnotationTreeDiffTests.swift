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

    @Test("deleteAnnotationsFromBookTree generates correct BookDeletionDiff for multiple annotations")
    func testBatchDeletionDiffUnderSameBook() {
        let ann1 = Annotation(id: 1, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 1000, context: "Ann 1", page: 1, part: 1)
        let ann2 = Annotation(id: 2, bkId: 10, contentId: 1, range: NSRange(location: 10, length: 5), rangeDiacritics: NSRange(location: 10, length: 5), colorHex: "#00FF00", type: .highlight, createdAt: 2000, context: "Ann 2", page: 1, part: 1)
        let ann3 = Annotation(id: 3, bkId: 10, contentId: 1, range: NSRange(location: 20, length: 5), rangeDiacritics: NSRange(location: 20, length: 5), colorHex: "#0000FF", type: .highlight, createdAt: 3000, context: "Ann 3", page: 1, part: 1)

        let child1 = AnnotationNode(title: "Child 1", kind: .annotation, annotation: ann1)
        let child2 = AnnotationNode(title: "Child 2", kind: .annotation, annotation: ann2)
        let child3 = AnnotationNode(title: "Child 3", kind: .annotation, annotation: ann3)

        let bookNode = AnnotationNode(title: "Book 10", kind: .book, bookId: 10)
        bookNode.children = [child1, child2, child3]

        let root = AnnotationNode(title: "Root", kind: .root)
        root.children = [bookNode]

        let diff = AnnotationTreeBuilder.shared.deleteAnnotationsFromBookTree(ids: [1, 2], root: root)

        #expect(diff.removedChildren.count == 2)
        #expect(diff.removedChildren[0].oldChildIndex == 0)
        #expect(diff.removedChildren[1].oldChildIndex == 1)
        #expect(diff.removedParents.isEmpty)
        #expect(bookNode.children.count == 1)
        #expect(bookNode.children.first?.annotation?.id == 3)
        #expect(root.children.count == 1)
    }

    @Test("deleteAnnotationsFromBookTree removes parent when all annotations deleted")
    func testBatchDeletionDiffRemovingEntireBook() {
        let ann1 = Annotation(id: 101, bkId: 20, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 1000, context: "Ann 101", page: 1, part: 1)
        let ann2 = Annotation(id: 102, bkId: 20, contentId: 1, range: NSRange(location: 10, length: 5), rangeDiacritics: NSRange(location: 10, length: 5), colorHex: "#00FF00", type: .highlight, createdAt: 2000, context: "Ann 102", page: 1, part: 1)

        let child1 = AnnotationNode(title: "Child 101", kind: .annotation, annotation: ann1)
        let child2 = AnnotationNode(title: "Child 102", kind: .annotation, annotation: ann2)

        let bookNode = AnnotationNode(title: "Book 20", kind: .book, bookId: 20)
        bookNode.children = [child1, child2]

        let root = AnnotationNode(title: "Root", kind: .root)
        root.children = [bookNode]

        let diff = AnnotationTreeBuilder.shared.deleteAnnotationsFromBookTree(ids: [101, 102], root: root)

        #expect(diff.removedChildren.count == 2)
        #expect(diff.removedParents.count == 1)
        #expect(diff.removedParents.first?.oldRootIndex == 0)
        #expect(bookNode.children.isEmpty)
        #expect(root.children.isEmpty)
    }

    @Test("removeAnnotationsFromTagTree preserves distinct pre-removal child and root indices")
    func testBatchDeletionInTagTreePreservesPreRemovalIndices() {
        let ann1 = Annotation(id: 1, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 1000, context: "Ann 1", page: 1, part: 1)
        let ann2 = Annotation(id: 2, bkId: 10, contentId: 1, range: NSRange(location: 10, length: 5), rangeDiacritics: NSRange(location: 10, length: 5), colorHex: "#00FF00", type: .highlight, createdAt: 2000, context: "Ann 2", page: 1, part: 1)
        let ann3 = Annotation(id: 3, bkId: 10, contentId: 1, range: NSRange(location: 20, length: 5), rangeDiacritics: NSRange(location: 20, length: 5), colorHex: "#0000FF", type: .highlight, createdAt: 3000, context: "Ann 3", page: 1, part: 1)

        let tagA = AnnotationNode(title: "Fiqh", kind: .tag)
        tagA.children = [
            AnnotationNode(title: "Child 1", kind: .annotation, annotation: ann1),
            AnnotationNode(title: "Child 2", kind: .annotation, annotation: ann2),
            AnnotationNode(title: "Child 3", kind: .annotation, annotation: ann3),
        ]

        let root = AnnotationNode(title: "Root", kind: .root)
        root.children = [tagA]

        let diff = AnnotationTreeBuilder.shared.removeAnnotationsFromTagTree(ids: [1, 2], root: root)

        #expect(diff.removed.count == 2)
        #expect(diff.removed[0].oldIndex == 0)
        #expect(diff.removed[1].oldIndex == 1)
        #expect(diff.removed[0].tagNodeBecomesEmpty == false)
        #expect(diff.removed[1].tagNodeBecomesEmpty == false)
        #expect(tagA.children.count == 1)
        #expect(tagA.children.first?.annotation?.id == 3)
    }
}
