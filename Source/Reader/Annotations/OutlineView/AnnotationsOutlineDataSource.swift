//
//  AnnotationsOutlineDataSource.swift
//  maktab
//
//  Created by MacBook on 15/12/25.
//

import Cocoa

@MainActor
class AnnotationOutlineDataSource: NSObject, NSOutlineViewDataSource {
    weak var delegate: AnnotationDelegate?
    weak var outlineView: NSOutlineView? {
        didSet {
            outlineView?.target = self
            outlineView?.doubleAction = #selector(onDoubleClick(_:))
        }
    }

    var onAddTagsRequested: (([Int64], NSRect) -> Void)?
    var onRemoveTagsRequested: (([Int64], NSRect) -> Void)?

    let paragraphStyle = NSMutableParagraphStyle()
    let viewModel = AnnotationViewModel()
    let calendar = Calendar.current
    var onSelectItem: ((Int) -> Void)?

    var groupingMode: AnnotationGroupingMode {
        viewModel.groupingMode
    }

    let menu = NSMenu()

    lazy var deleteMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = NSLocalizedString("Delete", comment: "")
        item.image = NSImage(systemSymbolName: "trash.slash", accessibilityDescription: "")
        return item
    }()

    lazy var copyMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = NSLocalizedString("Copy", comment: "")
        item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "")
        return item
    }()

    lazy var addTagMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = "Add Tags".localized + threeDots
        item.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "")
        return item
    }()

    lazy var removeTagMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = "Remove Tags".localized + threeDots
        item.image = NSImage(systemSymbolName: "tag.slash", accessibilityDescription: "")
        return item
    }()

    lazy var renameTagMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = String(localized: "Rename Tag") + threeDots
        item.image = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: "")
        return item
    }()

    private let threeDots = "..."

    override init() {
        super.init()
        paragraphStyle.alignment = .right
        setupViewModelBindings()
    }

    private func setupViewModelBindings() {
        viewModel.onTreeUpdate = { [weak self] _, _ in
            guard let self, let outlineView else { return }
            outlineView.reloadData()
            if !viewModel.searchText.isEmpty {
                outlineView.expandItem(nil, expandChildren: true)
            }
        }

        viewModel.onIncrementalUpdate = { [weak self] changeType, userInfo in
            self?.handleIncrementalChange(changeType: changeType, userInfo: userInfo)
        }
    }

    deinit {
        #if DEBUG
        print("Annotations Data Source deinit")
        #endif
    }

    // MARK: - Incremental Updates

    private func handleIncrementalChange(changeType: AnnotationChangeType, userInfo: [AnyHashable: Any]) {
        let annotation = userInfo[AnnotationNotificationKeys.annotation] as? Annotation
        let annotationId = (userInfo[AnnotationNotificationKeys.annotationId] as? Int64) ?? annotation?.id
        let oldParentIndex = userInfo[AnnotationNotificationKeys.oldParentIndex] as? Int
        let newParentIndex = userInfo[AnnotationNotificationKeys.newParentIndex] as? Int

        guard let annotationId else {
            outlineView?.reloadData()
            return
        }

        if groupingMode == .tag {
            let diff = userInfo[AnnotationNotificationKeys.tagDiff] as? TagUpdateDiff
            handleTagModeUpdate(annotationId: annotationId, diff: diff)
            return
        }

        switch changeType {
        case .added:
            handleAddedAnnotation(annotationId: annotationId, oldParentIndex: oldParentIndex, newParentIndex: newParentIndex)
        case .updated:
            handleUpdatedAnnotation(annotationId: annotationId)
        case .deleted:
            handleDeletedAnnotation(annotationId: annotationId, oldParentIndex: oldParentIndex, newParentIndex: newParentIndex)
        }
    }

    private func handleAddedAnnotation(annotationId: Int64, oldParentIndex: Int?, newParentIndex: Int?) {
        guard let outlineView else { return }
        guard let location = findAnnotationLocation(in: AnnotationManager.shared.rootNode, annotationId: annotationId) else {
            outlineView.reloadData()
            return
        }

        let parentRow = outlineView.row(forItem: location.parentNode)
        if let oldIdx = oldParentIndex, let newIdx = newParentIndex, oldIdx != newIdx, parentRow != -1 {
            outlineView.moveItem(at: oldIdx, inParent: nil, to: newIdx, inParent: nil)
        }

        if parentRow == -1 {
            outlineView.insertItems(at: IndexSet(integer: location.parentIndex), inParent: nil, withAnimation: .slideDown)
            return
        }

        if outlineView.isItemExpanded(location.parentNode) {
            outlineView.insertItems(at: IndexSet(integer: location.annotationIndex), inParent: location.parentNode, withAnimation: .slideDown)
        } else {
            outlineView.reloadItem(location.parentNode, reloadChildren: false)
        }
    }

    private func handleUpdatedAnnotation(annotationId: Int64) {
        guard let outlineView else { return }
        guard let row = rowIndex(forAnnotationId: annotationId) else {
            outlineView.reloadData()
            return
        }

        let columns = IndexSet(integersIn: 0 ..< outlineView.numberOfColumns)
        outlineView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: columns)
    }

    private func handleTagModeUpdate(annotationId _: Int64, diff: TagUpdateDiff?) {
        guard let outlineView else { return }
        guard let diff else {
            outlineView.reloadData()
            return
        }

        let totalChanges = diff.updated.count + diff.removed.count + diff.added.count
        if totalChanges > 100 {
            outlineView.reloadData()
            return
        }

        outlineView.beginUpdates()
        let columns = IndexSet(integersIn: 0 ..< outlineView.numberOfColumns)

        for annNode in diff.updated {
            let row = outlineView.row(forItem: annNode)
            if row != -1 {
                outlineView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: columns)
            }
        }

        applyTagModeRemovals(entries: diff.removed, in: outlineView)
        applyTagModeAdditions(entries: diff.added, in: outlineView)
        outlineView.endUpdates()
    }

    private func applyTagModeRemovals(entries: [TagUpdateDiff.RemovedEntry], in outlineView: NSOutlineView) {
        var removalsByParent: [AnnotationNode?: [Int]] = [:]
        for entry in entries {
            let parent = entry.tagNodeBecomesEmpty ? nil : entry.tagNode
            removalsByParent[parent, default: []].append(entry.oldIndex)
        }

        for (parent, indices) in removalsByParent {
            let indexSet = IndexSet(indices.filter { $0 != -1 })
            if !indexSet.isEmpty {
                outlineView.removeItems(at: indexSet, inParent: parent, withAnimation: .slideUp)
            }
        }
    }

    private func applyTagModeAdditions(entries: [TagUpdateDiff.AddedEntry], in outlineView: NSOutlineView) {
        let root = AnnotationManager.shared.rootNode
        for entry in entries {
            if entry.tagNodeIsNew {
                if let rootIdx = root?.children.firstIndex(where: { $0 === entry.tagNode }) {
                    outlineView.insertItems(at: IndexSet(integer: rootIdx), inParent: nil, withAnimation: .slideDown)
                }
            } else if outlineView.isItemExpanded(entry.tagNode) {
                if let annIdx = entry.tagNode.children.firstIndex(where: { $0 === entry.annotationNode }) {
                    outlineView.insertItems(at: IndexSet(integer: annIdx), inParent: entry.tagNode, withAnimation: .slideDown)
                }
            } else {
                outlineView.reloadItem(entry.tagNode, reloadChildren: false)
            }
        }
    }

    private func handleDeletedAnnotation(annotationId: Int64, oldParentIndex: Int?, newParentIndex: Int?) {
        guard let outlineView else { return }
        guard let row = rowIndex(forAnnotationId: annotationId),
              let item = outlineView.item(atRow: row) as? AnnotationNode
        else {
            outlineView.reloadData()
            return
        }

        let parent = outlineView.parent(forItem: item)
        let childIndex = outlineView.childIndex(forItem: item)
        if childIndex != -1 {
            outlineView.removeItems(at: IndexSet(integer: childIndex), inParent: parent, withAnimation: .slideUp)
        } else {
            outlineView.reloadItem(parent, reloadChildren: true)
        }

        if let oldIdx = oldParentIndex, let newIdx = newParentIndex, oldIdx != newIdx {
            outlineView.moveItem(at: oldIdx, inParent: nil, to: newIdx, inParent: nil)
        }

        cleanupEmptyParentNode(parent, in: outlineView)
    }

    private func cleanupEmptyParentNode(_ parent: Any?, in outlineView: NSOutlineView) {
        guard let parentNode = parent as? AnnotationNode,
              parentNode.children.isEmpty,
              !(AnnotationManager.shared.rootNode?.children.contains { $0 === parentNode } ?? false)
        else { return }

        let parentIndex = outlineView.childIndex(forItem: parentNode)
        if parentIndex != -1 {
            outlineView.removeItems(at: IndexSet(integer: parentIndex), inParent: nil, withAnimation: .slideUp)
        }
    }

    private func rowIndex(forAnnotationId annotationId: Int64) -> Int? {
        guard let outlineView else { return nil }
        for row in 0 ..< outlineView.numberOfRows where (outlineView.item(atRow: row) as? AnnotationNode)?.annotation?.id == annotationId {
            return row
        }
        return nil
    }

    private struct AnnotationLocation {
        let parentNode: AnnotationNode
        let parentIndex: Int
        let annotationIndex: Int
    }

    private func findAnnotationLocation(in root: AnnotationNode?, annotationId: Int64) -> AnnotationLocation? {
        guard let root else { return nil }
        for (parentIndex, parentNode) in root.children.enumerated() {
            if let annotationIndex = parentNode.children.firstIndex(where: { $0.annotation?.id == annotationId }) {
                return AnnotationLocation(parentNode: parentNode, parentIndex: parentIndex, annotationIndex: annotationIndex)
            }
        }
        return nil
    }

    // MARK: - Public Methods

    func reload() {
        AnnotationManager.shared.buildAnnotationTree()
    }

    func updateSorting(field: AnnotationSortField, isAscending: Bool) {
        AnnotationManager.shared.updateSorting(field: field, isAscending: isAscending)
    }

    func updateGrouping(mode: AnnotationGroupingMode) {
        viewModel.groupingMode = mode
        AnnotationManager.shared.updateGroupingMode(mode)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return viewModel.filteredNodes.count
        }
        if let node = item as? AnnotationNode {
            return node.children.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? AnnotationNode {
            return !node.children.isEmpty
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return viewModel.filteredNodes[index]
        }
        if let node = item as? AnnotationNode {
            return node.children[index]
        }
        fatalError("Invalid item or index.")
    }

    @objc private func onDoubleClick(_ sender: AnyObject) {
        guard let outlineView else { return }
        let clickedRow = outlineView.clickedRow
        guard clickedRow != -1, let item = outlineView.item(atRow: clickedRow) as? AnnotationNode else { return }
        if !item.children.isEmpty {
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
        }
    }
}
