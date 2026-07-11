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

#if os(macOS)
extension IbarotTextVC: AnnotationDelegate {
    func didSelect(annotation: Annotation) {
        let bkId = annotation.bkId
        let contentId = annotation.contentId
        guard let book = LibraryDataManager.shared.getBook([bkId]).first else {
            DispatchQueue.main.async {
                ReusableFunc.showAlert(
                    title: String(localized: .bookNotFound(bookID: bkId)),
                    message: String(localized: .bookMissingOnAnnotationClick)
                )
            }
            return
        }

        Task.detached { [weak self, contentId] in
            guard let self else { return }

            do {
                if await currentBook?.id != bkId {
                    try await displayBook(book, loadContent: false)
                }
            } catch {
                await MainActor.run {
                    ReusableFunc.showAlert(
                        title: DatabaseError.bookNotFound(bkId).localizedDescription,
                        message: DatabaseError.noConnection.localizedDescription
                    )
                }
                return
            }
            if await contentId != viewModel.currentContentId {
                await handleDelegate(contentId)
            }

            await textDelegate?.highlightAndScrollToAnns(annotation)
        }
    }
}
#endif

