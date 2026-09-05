//
//  Reader+Annotation.swift
//  Maktabah
//

import Foundation

extension ReaderViewModel {
    // MARK: - Shared: Annotations

    func loadAnnotations() {
        guard let book = currentBook else { return }
        let anns = annotationManager.loadAnnotations(
            bkId: book.id,
            contentId: currentContentId
        )

        currentAnnotations = anns
    }

    func findBestAnnotation(for range: NSRange) -> Annotation? {
        guard let book = currentBook else { return nil }
        return annotationCoordinator.findBestAnnotation(
            overlapping: range,
            bkId: book.id,
            contentId: currentContentId,
            showHarakat: TextViewState.shared.showHarakat
        )
    }

    func addAnnotation(
        in range: NSRange,
        mode: AnnotationMode,
        sourceText: String,
        color: PlatformColor
    ) throws {
        guard let book = currentBook else { return }
        let params = SaveHighlightParams(
            text: sourceText,
            range: range,
            color: color,
            bkId: book.id,
            contentId: currentContentId,
            page: currentPage ?? 0,
            part: currentPart ?? 0,
            diacriticsText: diacriticsText,
            showHarakat: showHarakat,
            mode: mode
        )
        _ = try annotationCoordinator.saveHighlight(params)
        loadAnnotations()
    }

    func deleteAnnotation(id: Int64) throws {
        try annotationManager.deleteAnnotation(id: id)
        loadAnnotations()
    }

    func updateAnnotation(_ annotation: Annotation) throws {
        try annotationManager.updateAnnotation(annotation)
        loadAnnotations()
    }
}
