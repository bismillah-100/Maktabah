//
//  AnnotationEvent.swift
//  Maktabah
//

import Foundation

enum AnnotationEvent {
    case added(Annotation)
    case updated(Annotation)
    case deleted(id: Int64, annotation: Annotation?)
    case batchUpdated([Annotation])
    case treeInvalidated
}
