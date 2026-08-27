import SwiftUI
import UIKit

// MARK: - View Controller

@MainActor
class iOSLibraryViewController: iOSHierarchicalCollectionViewController {
    var viewModel: LibraryViewModel?
    var onBookSelected: ((BooksData) -> Void)?
    var onSelectionChanged: (() -> Void)?
    var onDeleteBook: ((BooksData) -> Void)?
    var onDownloadBook: ((BooksData) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.delegate = self
    }

    // MARK: - Cell Registrations

    override func makeCategoryCellRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, CategoryData> {
        UICollectionView.CellRegistration { [weak self] cell, _, category in
            guard let self else { return }

            let isExpanded = expandedCategories.contains(category.id)
            let isSelectionMode = viewModel?.isSelectionMode == true

            let leadingAccessory: LeadingAccessoryType
            if isSelectionMode {
                let isSelected = viewModel?.isCategorySelected(category) == true
                let isPartial = viewModel?.isCategoryPartiallySelected(category) == true
                leadingAccessory = .checkbox(isPartial ? .partial : (isSelected ? .checked : .unchecked))
            } else {
                let isAuthorMode = viewModel?.viewMode == .author
                leadingAccessory = .icon(isAuthorMode ? "person.fill" : "folder.fill")
            }

            let config = ListContentConfiguration(
                text: category.name,
                font: font,
                leadingAccessory: leadingAccessory,
                isExpanded: isExpanded,
                root: true,
                indentationLevel: category.level
            )
            cell.contentConfiguration = config
            cell.accessories = []

            // Wire up checkbox tap handler for selection mode
            if isSelectionMode, let listContentView = cell.contentView as? ListContentView {
                listContentView.onCheckboxTap = { [weak self] in
                    guard let self else { return }
                    viewModel?.toggleCategorySelection(category)
                    onSelectionChanged?()
                    reconfigureCategories(includingBooks: getAllBooks(in: category))
                }
            }

            cell.applyThemeConfigurationUpdateHandler()
        }
    }

    override func makeBookCellRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, BooksData> {
        UICollectionView.CellRegistration { [weak self] cell, _, book in
            guard let self else { return }

            let isDownloaded = viewModel?.isBookDownloaded(book) == true
            let isSelectionMode = viewModel?.isSelectionMode == true

            let leadingAccessory: LeadingAccessoryType
            if isSelectionMode {
                let isSelected = viewModel?.isBookSelected(book) == true
                leadingAccessory = .checkbox(isSelected ? .checked : .unchecked)
            } else {
                leadingAccessory = .icon(isDownloaded ? "book.fill" : "icloud.and.arrow.down")
            }
            let isAuthorMode = viewModel?.viewMode == .author
            let indentationLevel: Int = if isAuthorMode {
                1
            } else {
                (LibraryDataManager.shared.categoryLevel(for: book) ?? 0) == 0 ? 1 : 2
            }

            let config = ListContentConfiguration(
                text: book.book,
                font: font,
                isDownloaded: isDownloaded && isSelectionMode,
                leadingAccessory: leadingAccessory,
                isExpanded: false,
                root: false,
                indentationLevel: indentationLevel
            )
            cell.contentConfiguration = config
            cell.accessories = []

            // Wire up checkbox tap handler for selection mode
            if isSelectionMode, let listContentView = cell.contentView as? ListContentView {
                listContentView.onCheckboxTap = { [weak self] in
                    self?.handleBookSelectionToggle(book)
                }
            }

            cell.applyThemeConfigurationUpdateHandler()
        }
    }

    private func handleBookSelectionToggle(_ book: BooksData) {
        viewModel?.toggleBookSelection(book)
        onSelectionChanged?()
        reconfigureCategories(includingBook: book)
    }

    override func didSelectBook(_ book: BooksData) {
        if viewModel?.isSelectionMode == true {
            handleBookSelectionToggle(book)
        } else {
            onBookSelected?(book)
        }
    }

    override func didSelectLoadMore() {
        viewModel?.loadMoreAuthors()
    }
}

// MARK: - UICollectionViewDelegate Context Menu

extension iOSLibraryViewController {
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let item = dataSource.itemIdentifier(for: indexPath),
              case let .book(book) = item,
              let viewModel
        else {
            return nil
        }

        let isDownloaded = viewModel.isBookDownloaded(book)

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let selectAction = UIAction(
                title: String(localized: "Select") + "...",
                image: UIImage(systemName: "checkmark.circle")
            ) { _ in
                viewModel.enterSelectionMode(selecting: book)
                self?.onSelectionChanged?()
            }

            let mainAction = if isDownloaded {
                UIAction(
                    title: String(localized: "Delete Download"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self?.onDeleteBook?(book)
                }
            } else {
                UIAction(title: String(localized: "Download"), image: UIImage(systemName: "icloud.and.arrow.down")) { _ in
                    self?.onDownloadBook?(book)
                }
            }

            return UIMenu(title: "", children: [mainAction, selectAction])
        }
    }
}
