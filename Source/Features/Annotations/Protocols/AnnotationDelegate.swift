//
//  AnnotationDelegate.swift
//  maktab
//
//  Created by MacBook on 16/12/25.
//

import Foundation

@MainActor
protocol AnnotationDelegate: AnyObject {
    func didSelect(annotation: Annotation)
}

extension IbarotTextVC: AnnotationDelegate {
    func didSelect(annotation: Annotation) {
        Task { [weak self] in
            try? await self?.openAnnotation(annotation)
        }
    }
}

