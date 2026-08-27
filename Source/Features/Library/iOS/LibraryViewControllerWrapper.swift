import SwiftUI
import UIKit

struct LibraryViewControllerWrapper: UIViewControllerRepresentable {
    let navigationManager: iOSNavigationManager
    let viewModel: LibraryViewModel
    @Binding var showOnlyDownloaded: Bool
    var onDeleteSingleBook: ((BooksData) -> Void)?
    var onDownloadSingleBook: ((BooksData) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(navigationManager: navigationManager, viewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> iOSLibraryViewController {
        let vc = iOSLibraryViewController()
        vc.viewModel = viewModel
        vc.onBookSelected = { book in
            viewModel.selectBook(book, using: navigationManager)
        }
        vc.onSelectionChanged = {
            viewModel.notifySelectionChanged()
        }
        vc.onDeleteBook = onDeleteSingleBook
        vc.onDownloadBook = onDownloadSingleBook
        vc.showLoadMore = viewModel.hasMoreAuthors
        vc.loadMoreCount = viewModel.totalAuthorCount - viewModel.displayedCategories.count

        Task {
            await context.coordinator.viewModel.loadLibrary()
            await MainActor.run {
                context.coordinator.viewModel._showOnlyDownloadedTracker = context.coordinator.viewModel.showOnlyDownloaded
                let categories = context.coordinator.viewModel.displayedCategories
                let showLoadMore = context.coordinator.viewModel.hasMoreAuthors
                vc.showLoadMore = showLoadMore
                vc.loadMoreCount = context.coordinator.viewModel.totalAuthorCount - categories.count
                context.coordinator.lastUpdateTrigger = context.coordinator.viewModel.updateTrigger
                context.coordinator.lastSelectionMode = context.coordinator.viewModel.isSelectionMode
                context.coordinator.lastShowLoadMore = showLoadMore
                vc.applyCategories(categories)
            }
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: iOSLibraryViewController, context: Context) {
        uiViewController.viewModel = context.coordinator.viewModel
        uiViewController.onDeleteBook = onDeleteSingleBook
        uiViewController.onDownloadBook = onDownloadSingleBook

        let showLoadMore = context.coordinator.viewModel.hasMoreAuthors
        let loadMoreCount = context.coordinator.viewModel.totalAuthorCount - context.coordinator.viewModel.displayedCategories.count
        uiViewController.showLoadMore = showLoadMore
        uiViewController.loadMoreCount = loadMoreCount

        guard context.coordinator.viewModel.state != .loading else { return }

        let categories = context.coordinator.viewModel.displayedCategories
        let currentTrigger = context.coordinator.viewModel.updateTrigger
        let currentSelectionMode = context.coordinator.viewModel.isSelectionMode

        if currentTrigger != context.coordinator.lastUpdateTrigger || showLoadMore != context.coordinator.lastShowLoadMore {
            context.coordinator.lastUpdateTrigger = currentTrigger
            context.coordinator.lastSelectionMode = currentSelectionMode
            context.coordinator.lastShowLoadMore = showLoadMore
            uiViewController.applyCategories(categories)
        } else if currentSelectionMode != context.coordinator.lastSelectionMode {
            context.coordinator.lastSelectionMode = currentSelectionMode
            uiViewController.reloadVisibleItems()
        }
    }

    class Coordinator {
        let navigationManager: iOSNavigationManager
        let viewModel: LibraryViewModel
        var lastUpdateTrigger: Int = -1
        var lastSelectionMode: Bool = false
        var lastShowLoadMore: Bool = false

        init(navigationManager: iOSNavigationManager, viewModel: LibraryViewModel) {
            self.navigationManager = navigationManager
            self.viewModel = viewModel
        }
    }
}
