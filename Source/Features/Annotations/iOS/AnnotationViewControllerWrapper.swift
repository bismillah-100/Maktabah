//
//  AnnotationViewControllerWrapper.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 10/06/26.
//

import SwiftUI

struct AnnotationViewControllerWrapper: UIViewControllerRepresentable {
    let navigationManager: iOSNavigationManager
    @Bindable var viewModel: AnnotationViewModel
    var onEditAnnotation: ((Annotation) -> Void)?
    var onShowBookInfo: ((BooksData) -> Void)?

    func makeUIViewController(context: Context) -> iOSAnnotationViewController {
        let vc = iOSAnnotationViewController()
        vc.viewModel = viewModel
        vc.onShowBookInfo = onShowBookInfo
        vc.additionalSafeAreaInsets.bottom = 15
        vc.onAnnotationSelected = { node in
            context.coordinator.handleSelection(node)
        }
        vc.onAnnotationDeleted = { node in
            if let id = node.annotation?.id {
                viewModel.deleteAnnotation(id: id)
            }
        }
        vc.onAnnotationEditRequested = { [weak coordinator = context.coordinator] ann in
            coordinator?.onEditAnnotation?(ann)
        }

        vc.onRefreshRequested = { [weak vc] in
            CloudKitSyncManager.shared.fetchChanges()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                vc?.endRefreshing()
            }
        }

        vc.onNeedFullReload = { [weak viewModel] in
            viewModel?.applyFilter()
        }
        viewModel.onIncrementalUpdate = { [weak vc] diff in
            vc?.handleIncrementalUpdate(diff: diff)
        }
        viewModel.onTreeUpdate = { [weak vc] nodes, mode in
            vc?.handleTreeUpdate(nodes: nodes.map { SwiftUIAnnotationNode(from: $0) }, groupingMode: mode)
        }
        viewModel.onTagsChanged = { [weak vc] _ in
            vc?.updateTagFilterHeader()
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: iOSAnnotationViewController, context: Context) {
        uiViewController.viewModel = viewModel
        uiViewController.onShowBookInfo = onShowBookInfo
        context.coordinator.onEditAnnotation = onEditAnnotation
        // Only set initial data — incremental updates come from notifications via callback
        if !context.coordinator.hasAppliedOnce {
            context.coordinator.hasAppliedOnce = true
            uiViewController.applyNodes(
                viewModel.swiftUINodes,
                groupingMode: viewModel.groupingMode,
                animated: false
            )
        }
        uiViewController.updateTagFilterHeader()
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(navigationManager: navigationManager)
        coordinator.onEditAnnotation = onEditAnnotation
        return coordinator
    }

    class Coordinator {
        let navigationManager: iOSNavigationManager
        var hasAppliedOnce = false
        var onEditAnnotation: ((Annotation) -> Void)?
        init(navigationManager: iOSNavigationManager) {
            self.navigationManager = navigationManager
        }

        @MainActor
        func handleSelection(_ node: SwiftUIAnnotationNode) {
            guard node.kind == .annotation, let ann = node.annotation else { return }
            if let book = LibraryDataManager.shared.booksById[ann.bkId] ?? LibraryDataManager.shared.getBook([ann.bkId]).first {
                navigationManager.openBook(
                    book,
                    options: OpenBookOptions(
                        contentId: Int(ann.contentId),
                        annotationEvent: ReaderAnnotationEvent(annotation: ann)
                    )
                )
            } else {
                NotificationCenter.default.post(
                    name: .annotationMissingBook,
                    object: ann.bkId
                )
            }
        }
    }
}
