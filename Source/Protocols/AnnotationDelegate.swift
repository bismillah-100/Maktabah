//
//  AnnotationDelegate.swift
//  maktab
//
//  Created by MacBook on 16/12/25.
//

import Foundation

protocol AnnotationDelegate: AnyObject {
    func didSelect(annotation: Annotation)
}

protocol AnnotationEditorDelegate: AnyObject {
    func annotationEditorDidSave(_ annotation: Annotation)
    func annotationEditorDidDelete(_ deleted: [Annotation])
}

extension IbarotTextVC: AnnotationDelegate {
    func didSelect(annotation: Annotation) {
        let bkId = annotation.bkId
        let contentId = annotation.contentId
        guard let book = LibraryDataManager.shared.getBook([bkId]).first else {
            return
        }

        Task.detached { [weak self, book, contentId, annotation] in
            guard let self else { return }

            await bookDB.connect(archive: book.archive)

            if await currentBook?.id != bkId {
                await didChangeBook(book: book)
            }

            await handleDelegate(contentId, fromResults: true)
            await highlighAndScrollToAnns(annotation)
        }
    }
}
