//
//  iOSAnnotationViewController.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 10/06/26.
//

import UIKit

class iOSAnnotationViewController: UIViewController {
    // MARK: - Public interface

    var onAnnotationSelected: ((SwiftUIAnnotationNode) -> Void)?
    var onAnnotationDeleted: ((SwiftUIAnnotationNode) -> Void)?
    var onNeedFullReload: (() -> Void)?

    // MARK: - Private

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<String, AnnotationItem>!
    private var expandedGroups: Set<String> = []

    private let font = UIFont.arabicFont(size: 20)

    private var currentNodes: [SwiftUIAnnotationNode] = []
    private var currentGroupingMode: AnnotationGroupingMode = .book

    private let sectionInsets: NSDirectionalEdgeInsets = .init(
        top: 5, leading: ListLayoutMetrics.defaultPadding, bottom: 5, trailing: ListLayoutMetrics.defaultPadding
    )

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        configureDataSource()
    }

    // MARK: - Full Rebuild (nodes passed from ViewModel)

    func handleTreeUpdate(nodes: [SwiftUIAnnotationNode], groupingMode: AnnotationGroupingMode) {
        currentNodes = nodes
        currentGroupingMode = groupingMode
        rebuildSnapshot(animated: true)
    }

    // MARK: - Incremental Update Entry Point

    func handleIncrementalUpdate(changeType: AnnotationChangeType, userInfo: [AnyHashable: Any]) {
        let annotation = userInfo[AnnotationNotificationKeys.annotation] as? Annotation
        let annotationId = (userInfo[AnnotationNotificationKeys.annotationId] as? Int64) ?? annotation?.id
        let diff = userInfo[AnnotationNotificationKeys.tagDiff] as? TagUpdateDiff
        let oldParentIndex = userInfo[AnnotationNotificationKeys.oldParentIndex] as? Int
        let newParentIndex = userInfo[AnnotationNotificationKeys.newParentIndex] as? Int

        switch changeType {
        case .added:
            handleAddedAnnotation(annotationId: annotationId, diff: diff, oldParentIndex: oldParentIndex, newParentIndex: newParentIndex)
        case .updated:
            handleUpdatedAnnotation(annotationId: annotationId, diff: diff)
        case .deleted:
            handleDeletedAnnotation(annotationId: annotationId, oldParentIndex: oldParentIndex, newParentIndex: newParentIndex)
        }
    }

    // MARK: - Incremental Updates

    private func handleAddedAnnotation(annotationId: Int64?, diff: TagUpdateDiff?, oldParentIndex: Int?, newParentIndex: Int?) {
        if let diff = diff {
            handleTagDiff(diff)
            return
        }

        // Book mode fallback
        onNeedFullReload?()
    }

    private func handleUpdatedAnnotation(annotationId: Int64?, diff: TagUpdateDiff?) {
        if let diff = diff {
            handleTagDiff(diff)
            return
        }

        // Book mode fallback
        if let annotationId = annotationId {
            guard let updatedAnnotation = AnnotationManager.shared.loadAnnotationById(annotationId) else {
                onNeedFullReload?()
                return
            }

            updateItemInSections(with: updatedAnnotation)
        }
    }

    private func handleTagDiff(_ diff: TagUpdateDiff) {
        // 1. Process Removed
        for entry in diff.removed {
            let sectionID = SwiftUIAnnotationNode.id(from: entry.tagNode)
            var sectionSnap = dataSource.snapshot(for: sectionID)
            let targetAnnotationId = entry.annotationNode.annotation?.id

            let itemsToDelete = sectionSnap.items.filter {
                if case .annotation(let node) = $0 { return node.annotation?.id == targetAnnotationId }
                return false
            }

            if !itemsToDelete.isEmpty {
                sectionSnap.delete(itemsToDelete)
                dataSource.apply(sectionSnap, to: sectionID, animatingDifferences: true)
            }

            if entry.tagNodeBecomesEmpty {
                var rootSnap = dataSource.snapshot()
                rootSnap.deleteSections([sectionID])
                expandedGroups.remove(sectionID)
                dataSource.apply(rootSnap, animatingDifferences: true)
            }
        }

        // 2. Process Added
        for entry in diff.added {
            let sectionID = SwiftUIAnnotationNode.id(from: entry.tagNode)

            var rootSnap = dataSource.snapshot()
            if !rootSnap.sectionIdentifiers.contains(sectionID) {
                // If the item needs to be sorted logically, ideally we reload, but append works for simple diffs
                rootSnap.appendSections([sectionID])
                dataSource.apply(rootSnap, animatingDifferences: true)
            }

            var sectionSnap = dataSource.snapshot(for: sectionID)
            let existingGroupItem = sectionSnap.items.first {
                if case .group = $0 { return true }
                return false
            }

            let groupItem: AnnotationItem
            if let existing = existingGroupItem {
                groupItem = existing
            } else {
                let groupNode = SwiftUIAnnotationNode(
                    id: sectionID,
                    title: entry.tagNode.title,
                    kind: entry.tagNode.kind,
                    annotation: nil,
                    children: nil
                )
                groupItem = AnnotationItem.group(groupNode)
                sectionSnap.append([groupItem])
            }

            let newNode = SwiftUIAnnotationNode(from: entry.annotationNode, parentId: sectionID)
            let newItem = AnnotationItem.annotation(newNode)
            
            if !sectionSnap.items.contains(where: { $0.node.annotation?.id == newNode.annotation?.id }) {
                sectionSnap.append([newItem], to: groupItem)
                dataSource.apply(sectionSnap, to: sectionID, animatingDifferences: true)
            }
        }

        // 3. Process Updated
        for node in diff.updated {
            if let ann = node.annotation {
                updateItemInSections(with: ann)
            }
        }
    }

    private func handleDeletedAnnotation(annotationId: Int64?, oldParentIndex: Int?, newParentIndex: Int?) {
        guard let annotationId = annotationId else {
            onNeedFullReload?()
            return
        }

        for sectionID in dataSource.snapshot().sectionIdentifiers {
            var sectionSnap = dataSource.snapshot(for: sectionID)

            let itemsToDelete = sectionSnap.items.filter {
                if case .annotation(let node) = $0 { return node.annotation?.id == annotationId }
                return false
            }

            guard !itemsToDelete.isEmpty else { continue }

            sectionSnap.delete(itemsToDelete)
            dataSource.apply(sectionSnap, to: sectionID, animatingDifferences: true)

            // Remove section if no annotations remain
            let hasAnnotations = dataSource.snapshot(for: sectionID).items.contains {
                if case .annotation = $0 { return true }
                return false
            }
            if !hasAnnotations {
                var rootSnap = dataSource.snapshot()
                rootSnap.deleteSections([sectionID])
                expandedGroups.remove(sectionID)
                dataSource.apply(rootSnap, animatingDifferences: true)
            }
        }

        onNeedFullReload?()
    }

    // MARK: - Reconfigure Items Helper

    /// Mengganti item lama dengan yang baru langsung di section snapshot untuk memastikan struktur hierarki terjaga
    private func updateItemInSections(with updatedAnnotation: Annotation) {
        guard isViewLoaded, dataSource != nil else { return }

        var found = false
        for sectionID in dataSource.snapshot().sectionIdentifiers {
            var sectionSnapshot = dataSource.snapshot(for: sectionID)

            let oldItems = sectionSnapshot.items.filter {
                $0.node.annotation?.id == updatedAnnotation.id
            }

            if !oldItems.isEmpty {
                for oldItem in oldItems {
                    let updatedNode = SwiftUIAnnotationNode(
                        id: oldItem.node.id, // Pertahankan ID unik yang ada (termasuk parent ID)
                        title: updatedAnnotation.note?.isEmpty == false ? updatedAnnotation.note! : updatedAnnotation.context,
                        kind: .annotation,
                        annotation: updatedAnnotation,
                        children: nil
                    )
                    let updatedItem = AnnotationItem.annotation(updatedNode)
                    
                    if oldItem == updatedItem { continue }
                    
                    sectionSnapshot.insert([updatedItem], after: oldItem)
                    sectionSnapshot.delete([oldItem])
                }
                dataSource.apply(sectionSnapshot, to: sectionID, animatingDifferences: true)
                found = true
            }
        }

        if !found {
            onNeedFullReload?()
        }
    }

    // MARK: - Setup

    private func setupCollectionView() {
        var listConfig = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfig.showsSeparators = true
        listConfig.backgroundColor = .appBackground
        listConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self,
                  let dataSource = self.dataSource,
                  let item = dataSource.itemIdentifier(for: indexPath),
                  case .annotation(let node) = item
            else { return nil }

            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, _ in
                guard let self else { return }
                // Remove from snapshot immediately for instant UI feedback
                var snap = dataSource.snapshot()
                snap.deleteItems([item])
                dataSource.apply(snap, animatingDifferences: true)

                // Execute actual deletion in background
                onAnnotationDeleted?(node)
            }
            delete.image = UIImage(systemName: "trash")
            return UISwipeActionsConfiguration(actions: [delete])
        }

        listConfig.itemSeparatorHandler = { [weak self] indexPath, sectionSeparatorConfiguration in
            var separatorConfig = sectionSeparatorConfiguration
            guard let self,
                  let dataSource = self.dataSource,
                  let item = dataSource.itemIdentifier(for: indexPath)
            else {
                return separatorConfig
            }

            let trailing = trailingOffset(for: item)
            separatorConfig.bottomSeparatorInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: ListLayoutMetrics.defaultPadding,
                bottom: 0,
                trailing: trailing
            )
            return separatorConfig
        }

        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard let self else {
                return NSCollectionLayoutSection.list(
                    using: listConfig,
                    layoutEnvironment: environment
                )
            }
            let section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
            section.contentInsets = sectionInsets
            return section
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = SettingsViewModel.shared.useDefaultTheme
            ? .systemGroupedBackground : .appBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.semanticContentAttribute = .forceLeftToRight
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func configureDataSource() {
        // Group cell — reuse ListContentView/ListContentConfiguration
        let groupCellReg = UICollectionView.CellRegistration<UICollectionViewListCell, SwiftUIAnnotationNode> {
            [weak self] cell, _, node in
            guard let self else { return }

            let isExpanded = expandedGroups.contains(node.id)
            let iconName = iconForKind(node.kind)

            let config = ListContentConfiguration(
                text: node.title,
                font: font,
                leadingAccessory: .icon(iconName),
                isExpanded: isExpanded,
                root: true,
                indentationLevel: 0
            )
            cell.contentConfiguration = config
            cell.accessories = []
            cell.applyThemeConfigurationUpdateHandler()
        }

        // Annotation (leaf) cell
        let annotationCellReg = UICollectionView.CellRegistration<UICollectionViewListCell, SwiftUIAnnotationNode> {
            cell, _, node in
            let config = AnnotationContentConfiguration(
                annotation: node.annotation,
                groupingMode: self.currentGroupingMode
            )
            cell.contentConfiguration = config
            cell.accessories = []
            cell.applyThemeConfigurationUpdateHandler()
        }

        dataSource = UICollectionViewDiffableDataSource<String, AnnotationItem>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            return collectionView.dequeueConfiguredReusableCell(
                using: item.isGroup ? groupCellReg : annotationCellReg,
                for: indexPath, item: item.node
            )
        }
    }

    // MARK: - Data

    func applyNodes(_ nodes: [SwiftUIAnnotationNode], groupingMode: AnnotationGroupingMode, animated: Bool = false) {
        currentNodes = nodes
        currentGroupingMode = groupingMode

        guard isViewLoaded, dataSource != nil else {
            return
        }
        rebuildSnapshot(animated: animated)
    }

    private func rebuildSnapshot(animated: Bool) {
        let newSectionIDs = currentNodes.map { $0.id }
        let currentSectionIDs = dataSource.snapshot().sectionIdentifiers

        if newSectionIDs != currentSectionIDs {
            var rootSnapshot = NSDiffableDataSourceSnapshot<String, AnnotationItem>()
            rootSnapshot.appendSections(newSectionIDs)
            dataSource.apply(rootSnapshot, animatingDifferences: false)
        }

        for node in currentNodes {
            let sectionID = node.id
            let existing = dataSource.snapshot(for: sectionID)

            var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<AnnotationItem>()
            let groupItem = AnnotationItem.group(node)
            sectionSnapshot.append([groupItem])

            let isExpanded = expandedGroups.contains(sectionID)

            if let children = node.children, !children.isEmpty {
                let childItems = children.map { AnnotationItem.annotation($0) }
                sectionSnapshot.append(childItems, to: groupItem)
                if isExpanded {
                    sectionSnapshot.expand([groupItem])
                }
            }

            // Ambil expanded state dari existing snapshot agar tidak konflik
            if !existing.items.isEmpty {
                let existingExpanded = existing.isExpanded(groupItem)
                if existingExpanded != isExpanded {
                    if existingExpanded {
                        expandedGroups.insert(sectionID)
                        sectionSnapshot.expand([groupItem])
                    } else {
                        expandedGroups.remove(sectionID)
                    }
                }
            }

            guard existing.items != sectionSnapshot.items ||
                  existing.visibleItems != sectionSnapshot.visibleItems else {
                continue
            }

            dataSource.apply(sectionSnapshot, to: sectionID, animatingDifferences: animated)
        }
    }

    // MARK: - Expand / Collapse

    private func toggleGroup(_ node: SwiftUIAnnotationNode) {
        let id = node.id
        let wasExpanded = expandedGroups.contains(id)
        let willExpand = !wasExpanded

        if willExpand { expandedGroups.insert(id) }
        else { expandedGroups.remove(id) }

        let groupItem = AnnotationItem.group(node)
        var sectionSnapshot = dataSource.snapshot(for: id)

        if willExpand { sectionSnapshot.expand([groupItem]) }
        else { sectionSnapshot.collapse([groupItem]) }

        dataSource.apply(sectionSnapshot, to: id, animatingDifferences: true)
        if let indexPath = dataSource.indexPath(for: groupItem),
           let cell = collectionView.cellForItem(at: indexPath) {

            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
                if var config = cell.contentConfiguration as? ListContentConfiguration {
                    config.isExpanded = willExpand
                    cell.contentConfiguration = config
                }
            }
        }
    }

    // MARK: - Helpers

    private func iconForKind(_ kind: AnnotationNodeKind) -> String {
        switch kind {
        case .book: return "book.pages.fill"
        case .tag: return "tag.fill"
        case .untagged: return "tag.slash.fill"
        default: return "folder.fill"
        }
    }

    private func trailingOffset(for item: AnnotationItem) -> CGFloat {
        item.isGroup
            ? ListLayoutMetrics.separatorTrailingOffset(isRoot: true, indentationLevel: 0)
            : ListLayoutMetrics.defaultPadding * 2
    }
}

// MARK: - UICollectionViewDelegate

extension iOSAnnotationViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        item.isGroup ? toggleGroup(item.node) : onAnnotationSelected?(item.node)
    }

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath)?.isGroup == true ? false : true
    }
}

extension Notification.Name {
    static let annotationMissingBook = Notification.Name("annotationMissingBook")
}
