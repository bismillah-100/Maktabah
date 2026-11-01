//
//  AnnotationChangeTypes.swift
//  Maktabah
//

import Foundation

// MARK: - Tree Update Models

struct TagUpdateDiff {
    struct RemovedEntry {
        let annotationNode: AnnotationNode // node anotasi yang dihapus
        let tagNode: AnnotationNode // tag node induknya
        let tagNodeBecomesEmpty: Bool // apakah tag node ikut hilang dari root
        let oldIndex: Int // Index item yang dihapus dalam parentnya
    }

    struct AddedEntry {
        let annotationNode: AnnotationNode // node anotasi yang ditambahkan
        let tagNode: AnnotationNode // tag node induknya
        let tagNodeIsNew: Bool // apakah tag node baru dibuat
    }

    let removed: [RemovedEntry]
    let added: [AddedEntry]
    let updated: [AnnotationNode] // annotation node yang hanya di-update teks/warna
}

struct BookDeletionDiff {
    struct RemovedChild {
        let annotationNode: AnnotationNode
        let parentNode: AnnotationNode
        let oldChildIndex: Int
    }

    struct RemovedParent {
        let parentNode: AnnotationNode
        let oldRootIndex: Int
    }

    struct MovedParent {
        let parentNode: AnnotationNode
        let oldIndex: Int
        let newIndex: Int
    }

    let removedChildren: [RemovedChild]
    let removedParents: [RemovedParent]
    let movedParents: [MovedParent]
}

struct BookAdditionDiff {
    struct AddedChild {
        let annotationNode: AnnotationNode
        let parentNode: AnnotationNode
        let newChildIndex: Int
    }

    struct AddedParent {
        let parentNode: AnnotationNode
        let newRootIndex: Int
    }

    let addedChildren: [AddedChild]
    let addedParents: [AddedParent]
    let movedParents: [BookDeletionDiff.MovedParent]

    var isEmpty: Bool {
        addedChildren.isEmpty && addedParents.isEmpty && movedParents.isEmpty
    }

    var totalChanges: Int {
        addedChildren.count + addedParents.count + movedParents.count
    }

    var requiresFullReload: Bool {
        totalChanges > 100 || !movedParents.isEmpty
    }
}

struct AnnotationTreeDiff {
    enum ChangeType {
        case added
        case updated
        case deleted
    }

    let changeType: ChangeType
    let annotation: Annotation?
    let annotationId: Int64?
    let oldParentIndex: Int?
    let newParentIndex: Int?
    let tagDiff: TagUpdateDiff?
    let bookDeletionDiff: BookDeletionDiff?
    let bookAdditionDiff: BookAdditionDiff?
    let updatedAnnotations: [Annotation]

    init(
        changeType: ChangeType,
        annotation: Annotation? = nil,
        annotationId: Int64? = nil,
        oldParentIndex: Int? = nil,
        newParentIndex: Int? = nil,
        tagDiff: TagUpdateDiff? = nil,
        bookDeletionDiff: BookDeletionDiff? = nil,
        bookAdditionDiff: BookAdditionDiff? = nil,
        updatedAnnotations: [Annotation] = []
    ) {
        self.changeType = changeType
        self.annotation = annotation
        self.annotationId = annotationId
        self.oldParentIndex = oldParentIndex
        self.newParentIndex = newParentIndex
        self.tagDiff = tagDiff
        self.bookDeletionDiff = bookDeletionDiff
        self.bookAdditionDiff = bookAdditionDiff
        self.updatedAnnotations = updatedAnnotations
    }
}
