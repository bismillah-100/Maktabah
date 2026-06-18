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
                    
                    var items: [LibraryItem] = dataSource.snapshot().itemIdentifiers.filter {
                        if case .category = $0 { return true }
                        return false
                    }
                    items.append(contentsOf: getAllBooks(in: category).map { .book($0) })
                    reconfigureItems(items)
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
            let indentationLevel: Int
            if isAuthorMode {
                indentationLevel = 1
            } else {
                indentationLevel = (LibraryDataManager.shared.categoryLevel(for: book) ?? 0) == 0 ? 1 : 2
            }

            let config = ListContentConfiguration(
                text: book.book,
                font: font,
                isDownloaded: (isDownloaded && isSelectionMode),
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
                    guard let self else { return }
                    self.viewModel?.toggleBookSelection(book)
                    self.onSelectionChanged?()

                    var items: [LibraryItem] = self.dataSource.snapshot().itemIdentifiers.filter {
                        if case .category = $0 { return true }
                        return false
                    }
                    items.append(.book(book))
                    self.reconfigureItems(items)
                }
            }

            cell.applyThemeConfigurationUpdateHandler()
        }
    }
}

// MARK: - UICollectionViewDelegate

extension iOSLibraryViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        // In selection mode, category row tap should still expand/collapse
        // Selection is handled via checkbox tap (onCheckboxTap)
        switch item {
        case let .category(category):
            toggleCategory(category)
        case let .book(book):
            if viewModel?.isSelectionMode == true {
                viewModel?.toggleBookSelection(book)
                onSelectionChanged?()
                var items: [LibraryItem] = dataSource.snapshot().itemIdentifiers.filter {
                    if case .category = $0 { return true }
                    return false
                }
                items.append(.book(book))
                reconfigureItems(items)
            } else {
                onBookSelected?(book)
            }
        case .loadMore:
            viewModel?.loadMoreAuthors()
        }
    }

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        !isGroup(dataSource.itemIdentifier(for: indexPath))
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let item = dataSource.itemIdentifier(for: indexPath),
              case let .book(book) = item,
              let viewModel = viewModel
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

            let mainAction: UIAction
            if isDownloaded {
                mainAction = UIAction(
                    title: String(localized: "Delete Download"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self?.onDeleteBook?(book)
                }
            } else {
                mainAction = UIAction(title: String(localized: "Download"), image: UIImage(systemName: "icloud.and.arrow.down")) { _ in
                    self?.onDownloadBook?(book)
                }
            }

            return UIMenu(title: "", children: [mainAction, selectAction])
        }
    }
}
