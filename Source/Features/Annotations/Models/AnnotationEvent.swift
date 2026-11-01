//
//  AnnotationEvent.swift
//  Maktabah
//

import Foundation

enum AnnotationEvent: Sendable {
    case added(Annotation)
    case batchAdded([Annotation])
    case updated(Annotation)
    case deleted(id: Int64, annotation: Annotation?)
    case batchDeleted(ids: [Int64], annotations: [Annotation])
    case batchUpdated([Annotation])
    case treeInvalidated
}
