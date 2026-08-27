//
//  AnnotationNode.swift
//  Maktabah
//

import Foundation

enum AnnotationNodeKind {
    case root
    case book
    case tag
    case untagged
    case annotation
}

final class AnnotationNode: Equatable, Hashable {
    var title: String
    var children: [AnnotationNode] = []
    var annotation: Annotation? // optional, kalau node ini representasi annotation
    var kind: AnnotationNodeKind

    init(
        title: String,
        kind: AnnotationNodeKind = .book,
        annotation: Annotation? = nil
    ) {
        self.title = title
        self.kind = kind
        self.annotation = annotation
    }

    func update(with annotation: Annotation) {
        if let note = annotation.note, !note.isEmpty {
            title = note
        } else {
            title = annotation.context
        }
        self.annotation = annotation
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    static func == (lhs: AnnotationNode, rhs: AnnotationNode) -> Bool {
        lhs === rhs
    }
}
