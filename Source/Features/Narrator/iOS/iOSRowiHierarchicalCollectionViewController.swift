import UIKit

enum RowiItem: Hashable {
    case tabaqa(TabaqaGroup)
    case rowi(Rowi)
    case loadMore(TabaqaGroup)

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .tabaqa(t): hasher.combine("tabaqa"); hasher.combine(t.code)
        case let .rowi(r): hasher.combine("rowi"); hasher.combine(r.id)
        case let .loadMore(t): hasher.combine("loadMore"); hasher.combine(t.code)
        }
    }

    static func == (lhs: RowiItem, rhs: RowiItem) -> Bool {
        switch (lhs, rhs) {
        case let (.tabaqa(a), .tabaqa(b)): a.code == b.code
        case let (.rowi(a), .rowi(b)): a.id == b.id
        case let (.loadMore(a), .loadMore(b)): a.code == b.code
        default: false
        }
    }
}

extension TabaqaGroup: Hashable {
    public static func == (lhs: TabaqaGroup, rhs: TabaqaGroup) -> Bool {
        lhs.code == rhs.code
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }
}

extension Rowi: Hashable {
    public static func == (lhs: Rowi, rhs: Rowi) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class iOSRowiHierarchicalCollectionViewController: BaseHierarchicalListViewController<RowiItem> {

    private(set) var expandedTabaqas: Set<String> = []
    private var pendingGroups: [TabaqaGroup]?

    var onLoadMore: ((TabaqaGroup) -> Void)?
    var onSelectRowi: ((Rowi) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.delegate = self

        if let pending = pendingGroups {
            applyGroups(pending)
            pendingGroups = nil
        }
    }

    override func trailingOffset(for item: RowiItem) -> CGFloat {
        let root: Bool
        let indentationLevel: Int

        switch item {
        case .tabaqa:
            root = true
            indentationLevel = 0
        case .rowi:
            root = false
            indentationLevel = 1
        case .loadMore:
            return 16
        }
        // Menggunakan fungsi kalkulator dari Base Class
        return calculateTrailingOffset(isRoot: root, indentationLevel: indentationLevel)
    }

    override func configureDataSource() {
        let tabaqaCellReg = UICollectionView.CellRegistration<UICollectionViewListCell, TabaqaGroup> { [weak self] cell, _, group in
            let isExpanded = self?.expandedTabaqas.contains(group.code) ?? false
            let config = ListContentConfiguration(
                text: group.name,
                font: self?.font ?? UIFont(),
                leadingAccessory: .icon("folder.fill"),
                isExpanded: isExpanded,
                root: true
            )
            cell.contentConfiguration = config
            cell.accessories = []
            cell.applyThemeConfigurationUpdateHandler()
        }

        let rowiCellReg = UICollectionView.CellRegistration<UICollectionViewListCell, Rowi> { [weak self] cell, _, rowi in
            let config = ListContentConfiguration(
                text: rowi.isoName, font: self?.font ?? UIFont(),
                leadingAccessory: .icon("person.text.rectangle.fill"), isExpanded: false, root: false, indentationLevel: 1
            )
            cell.contentConfiguration = config
            cell.accessories = []
            cell.applyThemeConfigurationUpdateHandler()
        }

        let loadMoreCellReg = UICollectionView.CellRegistration<UICollectionViewListCell, TabaqaGroup> { cell, _, group in
            var content = cell.defaultContentConfiguration()
            content.text = "Load More..."
            content.textProperties.color = .tintColor
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            cell.accessories = []

            cell.applyThemeConfigurationUpdateHandler()
        }

        dataSource = UICollectionViewDiffableDataSource<Int, RowiItem>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            switch item {
            case let .tabaqa(group):
                collectionView.dequeueConfiguredReusableCell(using: tabaqaCellReg, for: indexPath, item: group)
            case let .rowi(rowi):
                collectionView.dequeueConfiguredReusableCell(using: rowiCellReg, for: indexPath, item: rowi)
            case let .loadMore(group):
                collectionView.dequeueConfiguredReusableCell(using: loadMoreCellReg, for: indexPath, item: group)
            }
        }
        // Note: We handle expand/collapse manually in didSelectItemAt, not via sectionSnapshotHandlers
        // since we removed the outlineDisclosure accessory.
    }

    func applyGroups(_ groups: [TabaqaGroup], isSearching: Bool = false) {
        guard isViewLoaded else {
            pendingGroups = groups
            return
        }

        if dataSource.snapshot().numberOfSections == 0 {
            var rootSnapshot = NSDiffableDataSourceSnapshot<Int, RowiItem>()
            rootSnapshot.appendSections([0])
            dataSource.apply(rootSnapshot, animatingDifferences: false)
        }

        var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<RowiItem>()
        for group in groups {
            let groupItem = RowiItem.tabaqa(group)
            sectionSnapshot.append([groupItem])

            if expandedTabaqas.contains(group.code) || isSearching {
                sectionSnapshot.expand([groupItem])
            }

            var childrenItems: [RowiItem] = group.displayedRowis.map { .rowi($0) }
            if group.hasMore {
                childrenItems.append(.loadMore(group))
            }
            sectionSnapshot.append(childrenItems, to: groupItem)
        }

        dataSource.apply(sectionSnapshot, to: 0, animatingDifferences: true)
    }
}

// MARK: - Delegate
extension iOSRowiHierarchicalCollectionViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case let .rowi(rowi):
            onSelectRowi?(rowi)
        case let .loadMore(group):
            onLoadMore?(group)
        case let .tabaqa(group):
            let willBeExpanded = !expandedTabaqas.contains(group.code)
            if willBeExpanded { expandedTabaqas.insert(group.code) }
            else { expandedTabaqas.remove(group.code) }

            // Panggil helper dari base class
            toggleExpansion(for: .tabaqa(group), isExpanding: willBeExpanded)
        }
    }

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        switch item {
        case .tabaqa(_): return false
        default: return true
        }
    }
}
