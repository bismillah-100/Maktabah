//
//  AnnotationEvent.swift
//  Maktabah
//

import Foundation

enum AnnotationEvent: Sendable {
    case added(Annotation)
    case updated(Annotation)
    case deleted(id: Int64, annotation: Annotation?)
    case batchUpdated([Annotation])
    case treeInvalidated
}
