//
//  AnnotationTreeDiffTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 01/11/26.
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("Annotation Tree Diff & Section Identity Tests", .serialized)
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

    @Test("addAnnotationsToBookTree produces correct BookAdditionDiff for existing and new parents")
    func testBatchAdditionInBookTree() {
        let ann1 = Annotation(id: 1, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 1000, context: "Ann 1", page: 1, part: 1)
        let child1 = AnnotationNode(title: "Child 1", kind: .annotation, annotation: ann1)
        let bookNode10 = AnnotationNode(title: "Book 10", kind: .book, bookId: 10)
        bookNode10.children = [child1]

        let root = AnnotationNode(title: "Root", kind: .root)
        root.children = [bookNode10]

        let ann2 = Annotation(id: 2, bkId: 10, contentId: 2, range: NSRange(location: 10, length: 5), rangeDiacritics: NSRange(location: 10, length: 5), colorHex: "#00FF00", type: .highlight, createdAt: 2000, context: "Ann 2", page: 2, part: 1)
        let ann3 = Annotation(id: 3, bkId: 20, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#0000FF", type: .highlight, createdAt: 3000, context: "Ann 3", page: 1, part: 1)

        let diff = AnnotationTreeBuilder.shared.addAnnotationsToBookTree([ann2, ann3], root: root)

        #expect(diff.addedChildren.count == 1)
        #expect(diff.addedChildren.first?.annotationNode.annotation?.id == 2)
        #expect(diff.addedParents.count == 1)
        #expect(diff.addedParents.first?.parentNode.bookId == 20)
        #expect(root.children.count == 2)
        #expect(bookNode10.children.count == 2)
    }

    @Test("addAnnotationsToBookTree detects movedParents when parent position changes by createdAt")
    func testBatchAdditionInBookTreeDetectsMovedParentsWhenCreatedAtChanges() {
        let originalSort = AnnotationTreeBuilder.shared.currentSortOptionForTesting()
        AnnotationTreeBuilder.shared.setSortOptionForTesting(.init(field: .createdAt, isAscending: false))
        defer { AnnotationTreeBuilder.shared.setSortOptionForTesting(originalSort) }

        let annA = Annotation(id: 1, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 3000, context: "Ann 1", page: 1, part: 1)
        let childA = AnnotationNode(title: "Child A", kind: .annotation, annotation: annA)
        let bookA = AnnotationNode(title: "Book 10", kind: .book, bookId: 10)
        bookA.children = [childA]

        let annB = Annotation(id: 2, bkId: 20, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#00FF00", type: .highlight, createdAt: 1000, context: "Ann 2", page: 1, part: 1)
        let childB = AnnotationNode(title: "Child B", kind: .annotation, annotation: annB)
        let bookB = AnnotationNode(title: "Book 20", kind: .book, bookId: 20)
        bookB.children = [childB]

        let root = AnnotationNode(title: "Root", kind: .root)
        root.children = [bookA, bookB]

        let annBNew = Annotation(id: 3, bkId: 20, contentId: 2, range: NSRange(location: 10, length: 5), rangeDiacritics: NSRange(location: 10, length: 5), colorHex: "#0000FF", type: .highlight, createdAt: 5000, context: "Ann 3", page: 2, part: 1)

        let diff = AnnotationTreeBuilder.shared.addAnnotationsToBookTree([annBNew], root: root)

        #expect(diff.addedChildren.count == 1)
        #expect(diff.addedParents.isEmpty)
        #expect(!diff.movedParents.isEmpty)
        #expect(root.children.first?.bookId == 20)
        #expect(root.children.last?.bookId == 10)
    }

    @Test("processBatchTagAdditions marks first entry as new tag and subsequent entry as existing")
    func testBatchTagAdditionsForSameNewTagDoesNotMarkSubsequentEntriesAsNew() {
        let ann1 = Annotation(id: 11, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, note: nil, createdAt: 1000, context: "Ann 11", page: 1, part: 1, tags: ["FiqhNew"])
        let ann2 = Annotation(id: 12, bkId: 10, contentId: 2, range: NSRange(location: 10, length: 5), rangeDiacritics: NSRange(location: 10, length: 5), colorHex: "#00FF00", type: .highlight, note: nil, createdAt: 2000, context: "Ann 12", page: 2, part: 1, tags: ["FiqhNew"])

        let root = AnnotationNode(title: "Root", kind: .root)
        let entries = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: root, annotations: [ann1, ann2])

        #expect(entries.count == 2)
        #expect(entries[0].tagNodeIsNew == true)
        #expect(entries[1].tagNodeIsNew == false)
        #expect(entries[0].tagNode === entries[1].tagNode)
        #expect(entries[0].tagNode.children.count == 2)
    }

    @Test("AnnotationViewModel forwards batch additions when missing book check is enabled")
    @MainActor
    func testViewModelForwardsBatchAdditionsWithMissingBookCheck() {
        let vm = AnnotationViewModel()
        var receivedDiff: AnnotationTreeDiff?
        vm.onIncrementalUpdate = { diff in
            receivedDiff = diff
        }

        let bookDiff = BookAdditionDiff(addedChildren: [], addedParents: [], movedParents: [])
        let dummyAnn = Annotation(id: 9999, bkId: 99999, contentId: 1, range: NSRange(location: 0, length: 1), rangeDiacritics: NSRange(location: 0, length: 1), colorHex: "#FF0000", type: .highlight, createdAt: 1000, context: "Context", page: 1, part: 1)
        let diff = AnnotationTreeDiff(
            changeType: .added,
            annotation: dummyAnn,
            annotationId: nil,
            bookAdditionDiff: bookDiff
        )

        let originalHideMissing = UserDefaults.standard.hideMissingBookAnnotations
        UserDefaults.standard.hideMissingBookAnnotations = true
        defer { UserDefaults.standard.hideMissingBookAnnotations = originalHideMissing }

        vm.handleTreeDiff(diff)
        #expect(receivedDiff != nil)
    }

    @Test("Tag sorting: sorts by createdAt, context (A-Z/Z-A), page, and part, with untagged always at bottom")
    func testTagSortingByCreatedAtAndContextWithUntaggedAtEnd() {
        let originalSort = AnnotationTreeBuilder.shared.currentSortOptionForTesting()
        defer { AnnotationTreeBuilder.shared.setSortOptionForTesting(originalSort) }

        let annZebra = Annotation(id: 1, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 10000, context: "Zebra Ann", page: 50, part: 2, tags: ["Zebra"])
        let annApple = Annotation(id: 2, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#00FF00", type: .highlight, createdAt: 1000, context: "Apple Ann", page: 10, part: 1, tags: ["Apple"])
        let annUntagged = Annotation(id: 3, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#0000FF", type: .highlight, createdAt: 50000, context: "Untagged Ann", page: 1, part: 1, tags: [])

        // 1. When sort field is .createdAt (descending) -> Zebra (10000) > Apple (1000), untagged pinned at bottom
        AnnotationTreeBuilder.shared.setSortOptionForTesting(.init(field: .createdAt, isAscending: false))
        let rootCreated = AnnotationNode(title: "Root", kind: .root)
        _ = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: rootCreated, annotations: [annApple, annZebra, annUntagged])

        #expect(rootCreated.children.count == 3)
        #expect(rootCreated.children[0].title == "Zebra")
        #expect(rootCreated.children[1].title == "Apple")
        #expect(rootCreated.children[2].kind == .untagged)

        // 2. When sort field is .context (ascending: A-Z) -> Apple < Zebra, untagged pinned at bottom
        AnnotationTreeBuilder.shared.setSortOptionForTesting(.init(field: .context, isAscending: true))
        let rootContextAsc = AnnotationNode(title: "Root", kind: .root)
        _ = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: rootContextAsc, annotations: [annZebra, annApple, annUntagged])

        #expect(rootContextAsc.children.count == 3)
        #expect(rootContextAsc.children[0].title == "Apple")
        #expect(rootContextAsc.children[1].title == "Zebra")
        #expect(rootContextAsc.children[2].kind == .untagged)

        // 3. When sort field is .context (descending: Z-A) -> Zebra > Apple, untagged pinned at bottom
        AnnotationTreeBuilder.shared.setSortOptionForTesting(.init(field: .context, isAscending: false))
        let rootContextDesc = AnnotationNode(title: "Root", kind: .root)
        _ = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: rootContextDesc, annotations: [annApple, annZebra, annUntagged])

        #expect(rootContextDesc.children.count == 3)
        #expect(rootContextDesc.children[0].title == "Zebra")
        #expect(rootContextDesc.children[1].title == "Apple")
        #expect(rootContextDesc.children[2].kind == .untagged)

        // 4. When sort field is .page (ascending) -> Apple (page 10) < Zebra (page 50), untagged pinned at bottom
        AnnotationTreeBuilder.shared.setSortOptionForTesting(.init(field: .page, isAscending: true))
        let rootPageAsc = AnnotationNode(title: "Root", kind: .root)
        _ = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: rootPageAsc, annotations: [annZebra, annApple, annUntagged])

        #expect(rootPageAsc.children.count == 3)
        #expect(rootPageAsc.children[0].title == "Apple")
        #expect(rootPageAsc.children[1].title == "Zebra")
        #expect(rootPageAsc.children[2].kind == .untagged)

        // 5. When sort field is .part (descending) -> Zebra (part 2) > Apple (part 1), untagged pinned at bottom
        AnnotationTreeBuilder.shared.setSortOptionForTesting(.init(field: .part, isAscending: false))
        let rootPartDesc = AnnotationNode(title: "Root", kind: .root)
        _ = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: rootPartDesc, annotations: [annApple, annZebra, annUntagged])

        #expect(rootPartDesc.children.count == 3)
        #expect(rootPartDesc.children[0].title == "Zebra")
        #expect(rootPartDesc.children[1].title == "Apple")
        #expect(rootPartDesc.children[2].kind == .untagged)
    }

    @Test("Updating annotation across tags correctly empties old tags and populates new tags")
    func testTagUpdateDiffAcrossTags() {
        let ann1 = Annotation(id: 50, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 1000, context: "Original", page: 1, part: 1, tags: ["OldTagA"])

        let root = AnnotationNode(title: "Root", kind: .root)
        _ = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: root, annotations: [ann1])

        #expect(root.children.count == 1)
        #expect(root.children.first?.title == "OldTagA")

        let updatedAnn = Annotation(id: 50, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 1000, context: "Updated", page: 1, part: 1, tags: ["NewTagB"])

        let diff = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: root, annotations: [updatedAnn])
        #expect(diff.count == 1)
        #expect(diff.first?.tagNode.title == "NewTagB")
    }

    @Test("Multi-annotation addition to new tag with ascending createdAt repositions tag node correctly")
    func testMultiAnnotationBatchAdditionRepositionsNewTagNode() {
        let originalSort = AnnotationTreeBuilder.shared.currentSortOptionForTesting()
        AnnotationTreeBuilder.shared.setSortOptionForTesting(.init(field: .createdAt, isAscending: false))
        defer { AnnotationTreeBuilder.shared.setSortOptionForTesting(originalSort) }

        let annTagA = Annotation(id: 1, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 5000, context: "Tag A", page: 1, part: 1, tags: ["TagA"])

        let root = AnnotationNode(title: "Root", kind: .root)
        _ = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: root, annotations: [annTagA])

        #expect(root.children.count == 1)
        #expect(root.children[0].title == "TagA")

        // Now add 2 annotations with new "TagB": first has createdAt 1000, second has 10000.
        // Initially TagB would be inserted after TagA (1000 < 5000).
        // After second annotation (10000 > 5000), TagB must be repositioned BEFORE TagA.
        let annTagB1 = Annotation(id: 2, bkId: 10, contentId: 2, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#00FF00", type: .highlight, createdAt: 1000, context: "Tag B1", page: 2, part: 1, tags: ["TagB"])
        let annTagB2 = Annotation(id: 3, bkId: 10, contentId: 3, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#0000FF", type: .highlight, createdAt: 10000, context: "Tag B2", page: 3, part: 1, tags: ["TagB"])

        let entries = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: root, annotations: [annTagB1, annTagB2])
        #expect(entries.count == 2)
        #expect(root.children.count == 2)
        #expect(root.children[0].title == "TagB")
        #expect(root.children[1].title == "TagA")
    }

    @Test("Strict weak ordering: sorting groups with identical titles in descending mode does not violate irreflexivity")
    func testStrictWeakOrderingIdenticalGroupTitles() {
        let originalSort = AnnotationTreeBuilder.shared.currentSortOptionForTesting()
        defer { AnnotationTreeBuilder.shared.setSortOptionForTesting(originalSort) }

        AnnotationTreeBuilder.shared.setSortOptionForTesting(.init(field: .context, isAscending: false))
        let ann1 = Annotation(id: 1, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 1000, context: "Ann 1", page: 1, part: 1, tags: ["SameTag"])
        let ann2 = Annotation(id: 2, bkId: 10, contentId: 2, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#00FF00", type: .highlight, createdAt: 2000, context: "Ann 2", page: 1, part: 1, tags: ["SameTag"])

        let root = AnnotationNode(title: "Root", kind: .root)
        _ = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: root, annotations: [ann1, ann2])
        #expect(root.children.count == 1)
        #expect(root.children[0].title == "SameTag")
    }

    @Test("Multi-tag batch addition correctly positions multiple new tags according to createdAt")
    func testMultiTagBatchAdditionMultipleNewTags() {
        let originalSort = AnnotationTreeBuilder.shared.currentSortOptionForTesting()
        AnnotationTreeBuilder.shared.setSortOptionForTesting(.init(field: .createdAt, isAscending: false))
        defer { AnnotationTreeBuilder.shared.setSortOptionForTesting(originalSort) }

        // 3 new tags added in one batch with interleaving createdAt
        let annTagA1 = Annotation(id: 1, bkId: 10, contentId: 1, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#FF0000", type: .highlight, createdAt: 2000, context: "A1", page: 1, part: 1, tags: ["TagA"])
        let annTagB1 = Annotation(id: 2, bkId: 10, contentId: 2, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#00FF00", type: .highlight, createdAt: 1000, context: "B1", page: 1, part: 1, tags: ["TagB"])
        let annTagC1 = Annotation(id: 3, bkId: 10, contentId: 3, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#0000FF", type: .highlight, createdAt: 3000, context: "C1", page: 1, part: 1, tags: ["TagC"])
        let annTagB2 = Annotation(id: 4, bkId: 10, contentId: 4, range: NSRange(location: 0, length: 5), rangeDiacritics: NSRange(location: 0, length: 5), colorHex: "#00FF00", type: .highlight, createdAt: 8000, context: "B2", page: 1, part: 1, tags: ["TagB"])

        let root = AnnotationNode(title: "Root", kind: .root)
        _ = AnnotationTreeBuilder.shared.processBatchTagAdditions(root: root, annotations: [annTagA1, annTagB1, annTagC1, annTagB2])

        #expect(root.children.count == 3)
        #expect(root.children[0].title == "TagB")
        #expect(root.children[1].title == "TagC")
        #expect(root.children[2].title == "TagA")
    }
}
