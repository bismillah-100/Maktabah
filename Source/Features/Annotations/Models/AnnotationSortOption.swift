//
//  AnnotationSortOption.swift
//  Maktabah
//

import Foundation

enum AnnotationSortField: Int {
    case createdAt
    case context
    case page
    case part
}

enum AnnotationGroupingMode: Int {
    case book
    case tag
}

enum TagFilterMode {
    case or
    case and
}

struct AnnotationSortOption {
    let field: AnnotationSortField
    let isAscending: Bool
}
