//
//  ReaderAnnotationEvent.swift
//  Maktabah
//
//  Created by Ays on 10/10/26.
//

import Foundation

struct ReaderAnnotationEvent: Equatable {
    let id: UUID
    let annotation: Annotation
    
    init(annotation: Annotation, id: UUID = UUID()) {
        self.id = id
        self.annotation = annotation
    }
}
