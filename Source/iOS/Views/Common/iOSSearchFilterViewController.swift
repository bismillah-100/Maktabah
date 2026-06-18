import SwiftUI
import UIKit

// MARK: - View Controller

class iOSSearchFilterViewController: iOSHierarchicalCollectionViewController {
    var selectedBookIds: Set<Int> = []

    var onSelectionChanged: ((Set<Int>) -> Void)?

    private var bookCache: [Int: [BooksData]] = [:] // key: category.id
    private var fullCategories: Set<Int> = [] // Cache untuk kategori yang semua bukunya terpilih

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.delegate = self
    }

    /// Reset cache saat categories berubah
    override func applyCategories(_ categories: [CategoryData]) {
        bookCache.removeAll()
        super.applyCategories(categories)
    }

    // MARK: - Cell Registrations

    override func makeCategoryCellRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, CategoryData> {
        UICollectionView.CellRegistration { [weak self] cell, _, category in
            guard let self else { return }

            let isExpanded = expandedCategories.contains(category.id)

            // Determine leading accessory: checkbox or folder icon
            let books = cachedBooks(for: category)
            let isSelected = !books.isEmpty && books.allSatisfy { [weak self] in
                guard let self else { return false }
                return selectedBookIds.contains($0.id)
            }
            let isPartial = !books.isEmpty && books.contains { [weak self] in
                guard let self else { return false }
                return selectedBookIds.contains($0.id)
            } && books.contains { [weak self] in
                guard let self else { return false }
                return !selectedBookIds.contains($0.id)
            }
            let checkboxState: CheckboxState = isPartial ? .partial : (isSelected ? .checked : .unchecked)
            let leadingAccessory: LeadingAccessoryType = .checkbox(checkboxState)

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

            // Wire up checkbox tap handler
            if let listContentView = cell.contentView as? ListContentView {
                listContentView.onCheckboxTap = { [weak self] in
                    guard let self else { return }
                    let currentBooks = cachedBooks(for: category)
                    let allSelected = currentBooks.allSatisfy { [weak self] in
                        guard let self else { return false }
                        return selectedBookIds.contains($0.id)
                    }

                    var newSelection = selectedBookIds
                    if allSelected {
                        currentBooks.forEach { newSelection.remove($0.id) }
                    } else {
                        currentBooks.forEach { newSelection.insert($0.id) }
                    }

                    selectedBookIds = newSelection
                    onSelectionChanged?(selectedBookIds)

                    // Reconfigure all categories so parents update their state
                    var items: [LibraryItem] = dataSource.snapshot().itemIdentifiers.filter {
                        if case .category = $0 { return true }
                        return false
                    }
                    items.append(contentsOf: currentBooks.map { .book($0) })
                    reconfigureItems(items)
                }
            }

            cell.applyThemeConfigurationUpdateHandler()
        }
    }

    override func makeBookCellRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, BooksData> {
        UICollectionView.CellRegistration { [weak self] cell, _, book in
            guard let self else { return }
            let isSelected = selectedBookIds.contains(book.id)
            let indentationLevel = LibraryDataManager.shared.categoryLevel(for: book)
            let config = ListContentConfiguration(
                text: book.book,
                font: font,
                leadingAccessory: .checkbox(isSelected ? .checked : .unchecked),
                isExpanded: false,
                root: false,
                indentationLevel: indentationLevel == 0 ? 1 : 2
            )
            cell.contentConfiguration = config
            cell.accessories = []

            // Wire up checkbox tap handler
            if let listContentView = cell.contentView as? ListContentView {
                listContentView.onCheckboxTap = { [weak self] in
                    guard let self else { return }
                    if selectedBookIds.contains(book.id) {
                        selectedBookIds.remove(book.id)
                    } else {
                        selectedBookIds.insert(book.id)
                    }
                    onSelectionChanged?(selectedBookIds)

                    // Reconfigure all categories to update parent states
                    var items: [LibraryItem] = dataSource.snapshot().itemIdentifiers.filter {
                        if case .category = $0 { return true }
                        return false
                    }
                    items.append(.book(book))
                    reconfigureItems(items)
                }
            }

            cell.applyThemeConfigurationUpdateHandler()
        }
    }

    func cachedBooks(for category: CategoryData) -> [BooksData] {
        if let cached = bookCache[category.id] { return cached }
        let books = getAllBooks(in: category)
        bookCache[category.id] = books
        return books
    }
}

// MARK: - UICollectionViewDelegate

extension iOSSearchFilterViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case let .category(category):
            toggleCategory(category)
        case let .book(book):
            if selectedBookIds.contains(book.id) { selectedBookIds.remove(book.id) }
            else { selectedBookIds.insert(book.id) }
            onSelectionChanged?(selectedBookIds)
            // Reconfigure all categories to update parent states
            var items: [LibraryItem] = dataSource.snapshot().itemIdentifiers.filter {
                if case .category = $0 { return true }
                return false
            }
            items.append(.book(book))
            reconfigureItems(items)
        case .loadMore:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        !isGroup(dataSource.itemIdentifier(for: indexPath))
    }
}

// MARK: - SwiftUI Wrapper

struct SearchFilterUIKitView: UIViewControllerRepresentable {
    @Bindable var viewModel: SearchViewModel
    var displayedCategories: [CategoryData]
    var updateTrigger: Int = 0
    var onTap: () -> Void = {}

    func makeUIViewController(context: Context) -> iOSSearchFilterViewController {
        let vc = iOSSearchFilterViewController()
        vc.selectedBookIds = viewModel.selectedBookIds
        vc.onSelectionChanged = { ids in
            viewModel.setSelectedBooks(ids)
        }
        vc.additionalSafeAreaInsets.bottom = 50

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.cancelsTouchesInView = false
        vc.view.addGestureRecognizer(tap)

        // Terapkan kategori awal
        context.coordinator.lastTrigger = updateTrigger
        vc.applyCategories(displayedCategories)

        return vc
    }

    func updateUIViewController(_ uiViewController: iOSSearchFilterViewController, context: Context) {
        context.coordinator.onTap = onTap

        let structureChanged = context.coordinator.hasChanged(trigger: updateTrigger)

        if structureChanged {
            uiViewController.selectedBookIds = viewModel.selectedBookIds
            uiViewController.applyCategories(displayedCategories)
        } else if uiViewController.selectedBookIds != viewModel.selectedBookIds {
            uiViewController.selectedBookIds = viewModel.selectedBookIds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    // MARK: - Coordinator

    class Coordinator {
        var lastTrigger: Int = -1
        var onTap: () -> Void

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap() { onTap() }

        func hasChanged(trigger: Int) -> Bool {
            if trigger != lastTrigger {
                lastTrigger = trigger
                return true
            }
            return false
        }
    }
}
