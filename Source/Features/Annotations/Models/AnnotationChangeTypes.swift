//
//  AnnotationChangeTypes.swift
//  Maktabah
//

import Foundation

// MARK: - Notification Names

extension Notification.Name {
    static let annotationDidChange = Notification.Name("annotationDidChange")
    static let annotationTreeDidUpdate = Notification.Name("annotationTreeDidUpdate")
}

// MARK: - Notification UserInfo Keys

enum AnnotationChangeType: String {
    case added
    case updated
    case deleted
}

enum AnnotationNotificationKeys {
    static let changeType = "changeType"
    static let annotation = "annotation"
    static let annotationId = "annotationId"
    static let tagDiff = "tagDiff"
    static let oldParentIndex = "oldParentIndex"
    static let newParentIndex = "newParentIndex"
}

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
