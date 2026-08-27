//
//  BaseHierarchicalListViewController.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 11/06/26.
//

import UIKit

// MARK: - UICollectionViewListCell Helper

extension UICollectionViewListCell {
    /// Menerapkan warna background tema secara dinamis, dan mereset saat sel difokuskan (isFocused).
    func applyThemeConfigurationUpdateHandler() {
        if SettingsViewModel.shared.useDefaultTheme { return }
        configurationUpdateHandler = { cell, state in
            if state.isFocused {
                cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
                return
            }

            var backgroundConfig = UIBackgroundConfiguration.listCell()
            backgroundConfig.backgroundColor = .appCellBackground
            cell.backgroundConfiguration = backgroundConfig
        }
    }
}

extension UIView {
    func pinToEdges(of parentView: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parentView.topAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
        ])
    }
}

extension UICollectionLayoutListConfiguration {
    mutating func setStandardItemSeparatorHandler<Item>(
        dataSource: @escaping () -> UICollectionViewDiffableDataSource<some Any, Item>?,
        trailingOffset: @escaping (Item) -> CGFloat
    ) {
        itemSeparatorHandler = { indexPath, sectionSeparatorConfiguration in
            var separatorConfig = sectionSeparatorConfiguration
            guard let ds = dataSource(),
                  let item = ds.itemIdentifier(for: indexPath)
            else { return separatorConfig }

            let trailing = trailingOffset(item)
            separatorConfig.bottomSeparatorInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: ListLayoutMetrics.defaultPadding,
                bottom: 0,
                trailing: trailing
            )
            return separatorConfig
        }
    }
}

/// Base class generik untuk UICollectionView dengan layout hierarkis (outline).
class BaseHierarchicalListViewController<ItemType: Hashable & Sendable>: UIViewController {
    private(set) var collectionView: UICollectionView!
    var dataSource: UICollectionViewDiffableDataSource<Int, ItemType>!

    let font = UIFont(name: ArabicFont.kfgqpcUthmanTahaNaskh.rawValue, size: 20) ??
        .preferredFont(forTextStyle: .body)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        configureDataSource()
    }

    // MARK: - Subclass Overrides

    /// Wajib di-override oleh subclass untuk inisialisasi data source
    open func configureDataSource() {
        fatalError("Subclass must override configureDataSource()")
    }

    /// Wajib di-override oleh subclass untuk menentukan offset separator tiap item
    open func trailingOffset(for item: ItemType) -> CGFloat {
        16
    }

    // MARK: - Setup UI

    private func setupCollectionView() {
        let config = makeListConfiguration()
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = SettingsViewModel.shared.useDefaultTheme
            ? .systemGroupedBackground : .appBackground
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.semanticContentAttribute = .forceLeftToRight
        collectionView.pinToEdges(of: view)
    }

    private func makeListConfiguration() -> UICollectionLayoutListConfiguration {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.showsSeparators = true
        config.backgroundColor = .appBackground
        config.setStandardItemSeparatorHandler(dataSource: { [weak self] in self?.dataSource }, trailingOffset: { [weak self] item in
            self?.trailingOffset(for: item) ?? 16
        })
        return config
    }

    // MARK: - Shared Helpers & Logic

    /// Rumus matematika yang sama untuk menghitung offset separator
    func calculateTrailingOffset(isRoot root: Bool, indentationLevel: Int) -> CGFloat {
        if root, indentationLevel > 0 {
            86 /* 24 + 38 -image dan padding + 24 -untuk chevron */
        } else if indentationLevel > 1 {
            root ? 118 /* 56 + 38 + 24 */ : 94
        } else {
            root
                ? CGFloat(16 + (32 * indentationLevel) + 38 + 24)
                : CGFloat(16 + (32 * indentationLevel) + 38)
        }
    }

    /// Toggle expand/collapse dan jalankan animasi chevron otomatis
    func toggleExpansion(for item: ItemType, isExpanding: Bool, in section: Int = 0) {
        var sectionSnapshot = dataSource.snapshot(for: section)

        // Update state tracker utama Anda terlebih dahulu
        if isExpanding {
            sectionSnapshot.expand([item])
        } else {
            sectionSnapshot.collapse([item])
        }

        dataSource.apply(sectionSnapshot, to: section, animatingDifferences: true)

        if let indexPath = dataSource.indexPath(for: item),
           let cell = collectionView.cellForItem(at: indexPath)
        {
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
                if var config = cell.contentConfiguration as? ListContentConfiguration {
                    config.isExpanded = isExpanding
                    cell.contentConfiguration = config
                }
            }
        }
    }

    /// Reconfigure item yang sedang terlihat ditambah margin offset (buffer sebelum dan sesudahnya).
    func reloadVisibleItems(margin: Int = 10) {
        guard isViewLoaded, dataSource != nil else { return }

        let visiblePaths = collectionView.indexPathsForVisibleItems
        guard !visiblePaths.isEmpty else { return }

        var snapshot = dataSource.snapshot()
        var itemsToReconfigure = Set<ItemType>()

        let pathsBySection = Dictionary(grouping: visiblePaths, by: { $0.section })

        for (section, paths) in pathsBySection {
            guard section < snapshot.sectionIdentifiers.count else { continue }
            let sectionIdentifier = snapshot.sectionIdentifiers[section]
            let sectionItems = snapshot.itemIdentifiers(inSection: sectionIdentifier)

            let minRow = paths.map(\.row).min() ?? 0
            let maxRow = paths.map(\.row).max() ?? 0

            let startRow = max(0, minRow - margin)
            let endRow = min(sectionItems.count - 1, maxRow + margin)

            guard startRow <= endRow else { continue }

            for i in startRow ... endRow {
                itemsToReconfigure.insert(sectionItems[i])
            }
        }

        guard !itemsToReconfigure.isEmpty else { return }
        snapshot.reconfigureItems(Array(itemsToReconfigure))
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    /// Reconfigure specific items only.
    func reconfigureItems(_ items: [ItemType]) {
        guard isViewLoaded, dataSource != nil else { return }
        let validItems = items.compactMap { item -> ItemType? in
            guard dataSource.indexPath(for: item) != nil else { return nil }
            return item
        }
        guard !validItems.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(validItems)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Search Data Type
    func isGroup(_ item: LibraryItem?) -> Bool {
        switch item {
        case .category: true
        default: false
        }
    }
}
