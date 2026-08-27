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

    func makeUIViewController(context: Context) -> iOSAnnotationViewController {
        let vc = iOSAnnotationViewController()
        vc.viewModel = viewModel
        vc.additionalSafeAreaInsets.bottom = 15
        vc.onAnnotationSelected = { node in
            context.coordinator.handleSelection(node)
        }
        vc.onAnnotationDeleted = { node in
            if let id = node.annotation?.id {
                viewModel.deleteAnnotation(id: id)
            }
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
        viewModel.onIncrementalUpdate = { [weak vc] changeType, userInfo in
            vc?.handleIncrementalUpdate(changeType: changeType, userInfo: userInfo)
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
        Coordinator(navigationManager: navigationManager)
    }

    class Coordinator {
        let navigationManager: iOSNavigationManager
        var hasAppliedOnce = false
        init(navigationManager: iOSNavigationManager) {
            self.navigationManager = navigationManager
        }

        @MainActor
        func handleSelection(_ node: SwiftUIAnnotationNode) {
            guard node.kind == .annotation, let ann = node.annotation else { return }
            if let book = LibraryDataManager.shared.getBook([ann.bkId]).first {
                navigationManager.openBook(book, initialContentId: Int(ann.contentId), targetAnnotation: ann)
            } else {
                NotificationCenter.default.post(
                    name: .annotationMissingBook,
                    object: ann.bkId
                )
            }
        }
    }
}
