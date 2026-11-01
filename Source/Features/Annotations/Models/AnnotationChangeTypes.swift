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

    init(
        changeType: ChangeType,
        annotation: Annotation? = nil,
        annotationId: Int64? = nil,
        oldParentIndex: Int? = nil,
        newParentIndex: Int? = nil,
        tagDiff: TagUpdateDiff? = nil,
        bookDeletionDiff: BookDeletionDiff? = nil
    ) {
        self.changeType = changeType
        self.annotation = annotation
        self.annotationId = annotationId
        self.oldParentIndex = oldParentIndex
        self.newParentIndex = newParentIndex
        self.tagDiff = tagDiff
        self.bookDeletionDiff = bookDeletionDiff
    }
}
