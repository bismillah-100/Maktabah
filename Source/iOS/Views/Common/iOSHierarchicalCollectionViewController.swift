import UIKit

// MARK: - Shared Types

enum LibraryItem: Hashable, @unchecked Sendable {
    case category(CategoryData)
    case book(BooksData)
    case loadMore

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .category(c): hasher.combine("cat"); hasher.combine(c.id)
        case let .book(b): hasher.combine("book"); hasher.combine(b.id)
        case .loadMore: hasher.combine("loadMore")
        }
    }

    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        switch (lhs, rhs) {
        case let (.category(a), .category(b)): a.id == b.id
        case let (.book(a), .book(b)): a.id == b.id
        case (.loadMore, .loadMore): true
        default: false
        }
    }
}

// MARK: - Shared Hashable Conformances

extension CategoryData: Hashable {
    public static func == (lhs: CategoryData, rhs: CategoryData) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension BooksData: Hashable {
    public static func == (lhs: BooksData, rhs: BooksData) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Controller
class iOSHierarchicalCollectionViewController: BaseHierarchicalListViewController<LibraryItem> {

    private(set) var expandedCategories: Set<Int> = []
    private var previousExpandedCategories: Set<Int> = []
    private var pendingCategories: [CategoryData]?

    var loadMoreCount: Int = 0
    var showLoadMore: Bool = false
    var onLoadMore: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        if let pending = pendingCategories {
            applyCategories(pending)
            pendingCategories = nil
        }
    }

    override func trailingOffset(for item: LibraryItem) -> CGFloat {
        let root: Bool
        let indentationLevel: Int

        switch item {
        case .category(let category):
            root = true
            indentationLevel = category.level
        case .book(let book):
            root = false
            let level = LibraryDataManager.shared.categoryLevel(for: book)
            indentationLevel = level == 0 ? 1 : 2
        case .loadMore:
            return 16
        }
        // Menggunakan fungsi kalkulator dari Base Class
        return calculateTrailingOffset(isRoot: root, indentationLevel: indentationLevel)
    }

    // MARK: - Cell Registrations (Wajib di-override subclass seperti iOSSearchFilterViewController)

    func makeCategoryCellRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, CategoryData> {
        fatalError("\(type(of: self)) harus override makeCategoryCellRegistration()")
    }

    func makeBookCellRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, BooksData> {
        fatalError("\(type(of: self)) harus override makeBookCellRegistration()")
    }

    lazy var loadMoreCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, LibraryItem> = {
        UICollectionView.CellRegistration { [weak self] cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = "Load More... (\(self?.loadMoreCount ?? 0) remaining)"
            content.textProperties.color = .tintColor
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            cell.accessories = []
            cell.applyThemeConfigurationUpdateHandler()
        }
    }()

    // MARK: - Data Source

    override func configureDataSource() {
        let categoryCellReg = makeCategoryCellRegistration()
        let bookCellReg = makeBookCellRegistration()
        let loadMoreReg = loadMoreCellRegistration

        dataSource = UICollectionViewDiffableDataSource<Int, LibraryItem>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            switch item {
            case let .category(category):
                collectionView.dequeueConfiguredReusableCell(
                    using: categoryCellReg, for: indexPath, item: category
                )
            case let .book(book):
                collectionView.dequeueConfiguredReusableCell(
                    using: bookCellReg, for: indexPath, item: book
                )
            case .loadMore:
                collectionView.dequeueConfiguredReusableCell(
                    using: loadMoreReg, for: indexPath, item: item
                )
            }
        }
        // Note: We handle expand/collapse manually since we use custom chevron instead of outlineDisclosure.
    }

    // MARK: - Data Loading

    func applyCategories(_ categories: [CategoryData]) {
        guard isViewLoaded else {
            pendingCategories = categories
            return
        }

        if dataSource.snapshot().numberOfSections == 0 {
            var rootSnapshot = NSDiffableDataSourceSnapshot<Int, LibraryItem>()
            rootSnapshot.appendSections([0])
            dataSource.apply(rootSnapshot, animatingDifferences: false)
        }

        var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<LibraryItem>()
        buildSnapshot(&sectionSnapshot, from: categories, parent: nil)

        // Add Load More if needed
        if showLoadMore {
            sectionSnapshot.append([.loadMore])
        }

        dataSource.apply(sectionSnapshot, to: 0, animatingDifferences: false)

        // Sync chevrons and update item UI states for all visible items.
        // Needed when applyCategories is called after sorting/filter changes or integration state updates.
        syncVisibleItems()
    }

    private func syncVisibleItems() {
        let visibleItems = collectionView.indexPathsForVisibleItems.compactMap {
            dataSource.itemIdentifier(for: $0)
        }
        guard !visibleItems.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(visibleItems)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func buildSnapshot(
        _ snapshot: inout NSDiffableDataSourceSectionSnapshot<LibraryItem>,
        from categories: [CategoryData],
        parent: LibraryItem?
    ) {
        for category in categories {
            let catItem = LibraryItem.category(category)

            if let parent { snapshot.append([catItem], to: parent) }
            else { snapshot.append([catItem]) }

            if expandedCategories.contains(category.id) {
                snapshot.expand([catItem])
                previousExpandedCategories.insert(category.id)
            }

            var subCats: [CategoryData] = []
            var bookItems: [LibraryItem] = []

            for child in category.children {
                if let subCat = child as? CategoryData { subCats.append(subCat) }
                else if let book = child as? BooksData { bookItems.append(.book(book)) }
            }

            if !subCats.isEmpty { buildSnapshot(&snapshot, from: subCats, parent: catItem) }
            if !bookItems.isEmpty { snapshot.append(bookItems, to: catItem) }
        }
    }

    // MARK: - Expand/Collapse
    
    /// Toggles the expanded state of a CategoryData and animates the chevron.
    func toggleCategory(_ category: CategoryData) {
        let willBeExpanded = !expandedCategories.contains(category.id)

        if willBeExpanded {
            expandedCategories.insert(category.id)
            previousExpandedCategories.insert(category.id)
        } else {
            expandedCategories.remove(category.id)
            previousExpandedCategories.remove(category.id)
        }

        toggleExpansion(for: .category(category), isExpanding: willBeExpanded)
    }

    // MARK: - Helpers
    func getAllBooks(in category: CategoryData) -> [BooksData] {
        var books: [BooksData] = []
        _getAllBooks(in: category, books: &books)
        return books
    }

    private func _getAllBooks(in category: CategoryData, books: inout [BooksData]) {
        for child in category.children {
            if let book = child as? BooksData {
                books.append(book)
            } else if let sub = child as? CategoryData {
                _getAllBooks(in: sub, books: &books)
            }
        }
    }

    func getAllCategories(in category: CategoryData) -> [CategoryData] {
        var categories: [CategoryData] = []
        _getAllCategories(in: category, categories: &categories)
        return categories
    }

    private func _getAllCategories(in category: CategoryData, categories: inout [CategoryData]) {
        for child in category.children {
            if let sub = child as? CategoryData {
                categories.append(sub)
                _getAllCategories(in: sub, categories: &categories)
            }
        }
    }
}
