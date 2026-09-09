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
        let bkId = annotation.bkId
        let contentId = annotation.contentId
        guard let book = LibraryDataManager.shared.getBook([bkId]).first else {
            ReusableFunc.showAlert(
                title: String(localized: .bookNotFound(bookID: bkId)),
                message: String(localized: .bookMissingOnAnnotationClick)
            )
            return
        }

        Task { [weak self] in
            guard let self else { return }

            do {
                if currentBook?.id != bkId {
                    try await displayBook(book, loadContent: false)
                }
            } catch {
                ReusableFunc.showAlert(
                    title: DatabaseError.bookNotFound(bkId).localizedDescription,
                    message: DatabaseError.noConnection.localizedDescription
                )
                return
            }
            if contentId != viewModel.currentContentId {
                handleDelegate(contentId)
            }

            await textDelegate?.highlightAndScrollToAnns(annotation)
        }
    }
}

