//
//  iOSAnVC+TagFilter.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 22/08/26.
//

import SwiftUI

// MARK: - Tag Filter Header & Sheet

extension iOSAnnotationViewController {
    func configureTagFilterHeader(_ header: iOSTagFilterHeaderView?) {
        guard let header, let viewModel else { return }
        header.configure(
            allTags: viewModel.availableTags,
            selectedTags: viewModel.selectedTags,
            isAndMode: viewModel.tagFilterMode == .and,
            onFilterTap: { [weak self] in
                self?.presentTagFilterSheet()
            },
            onModeTap: { [weak self] in
                self?.viewModel?.toggleTagFilterMode()
            },
            onTagToggle: { [weak self] tag in
                self?.viewModel?.toggleTagSelection(tag)
            }
        )
    }

    func updateTagFilterHeader() {
        guard let header = collectionView.visibleSupplementaryViews(
            ofKind: UICollectionView.elementKindSectionHeader
        ).first as? iOSTagFilterHeaderView else {
            return
        }
        configureTagFilterHeader(header)
    }

    func presentTagFilterSheet() {
        guard let viewModel else { return }
        let allTags = viewModel.allTags
        guard !allTags.isEmpty else { return }

        let isAndMode = viewModel.tagFilterMode == .and
        let selectedTags = viewModel.selectedTags

        let filterView = TagFilterSelectionView(
            allTags: allTags,
            selectedTags: selectedTags,
            isAndMode: isAndMode,
            availableTagsProvider: { [weak viewModel] tags in
                viewModel?.availableTags(for: tags) ?? []
            },
            onToggle: { [weak self] tag in
                self?.viewModel?.toggleTagSelection(tag)
            },
            onSelectAll: { [weak viewModel] in
                guard let viewModel else { return }
                viewModel.selectedTags = Set(viewModel.availableTags)
            },
            onDeselectAll: { [weak viewModel] in
                viewModel?.selectedTags = []
            }
        )

        let hostingVC = UIHostingController(rootView: filterView)
        if let sheet = hostingVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(hostingVC, animated: true)
    }
}
