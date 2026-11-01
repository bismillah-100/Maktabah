//
//  AnnotationsOutlineDataSource.swift
//  maktab
//
//  Created by MacBook on 15/12/25.
//

import Cocoa
import OSLog

@MainActor
class AnnotationOutlineDataSource: NSObject, NSOutlineViewDataSource {
    weak var delegate: AnnotationDelegate?
    weak var outlineView: NSOutlineView? {
        didSet {
            outlineView?.target = self
            outlineView?.doubleAction = #selector(onDoubleClick(_:))
            applyOutlineViewConfiguration()
        }
    }

    let treeBuilder: AnnotationTreeBuilder = .shared

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
    weak var editorPopover: NSPopover?

    lazy var editMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = String(localized: .Annotation.editAnnotation) + threeDots
        item.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "")
        return item
    }()

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
        item.title = String(localized: .Annotation.addTags) + threeDots
        item.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "")
        return item
    }()

    lazy var removeTagMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = String(localized: .Annotation.removeTags) + threeDots
        item.image = NSImage(systemSymbolName: "tag.slash", accessibilityDescription: "")
        return item
    }()

    lazy var renameTagMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = String(localized: .Annotation.renameTag) + threeDots
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
            if groupingMode == .timeline || !viewModel.searchText.isEmpty {
                outlineView.expandItem(nil, expandChildren: true)
            }
        }

        viewModel.onIncrementalUpdate = { [weak self] diff in
            self?.handleIncrementalChange(diff: diff)
        }
    }

    deinit {
        Logger.annotations.debug("Annotations Data Source deinit")
    }

    // MARK: - Incremental Updates

    private func handleIncrementalChange(diff: AnnotationTreeDiff) {
        if groupingMode == .tag || (groupingMode == .timeline && diff.tagDiff != nil) {
            handleTagModeUpdate(diff: diff.tagDiff)
            return
        }

        switch diff.changeType {
        case .added:
            if let bookDiff = diff.bookAdditionDiff, let outlineView {
                applyBookModeAdditions(diff: bookDiff, in: outlineView)
            } else if let annotationId = diff.annotationId {
                handleAddedAnnotation(annotationId: annotationId, oldParentIndex: diff.oldParentIndex, newParentIndex: diff.newParentIndex)
            } else {
                outlineView?.reloadData()
            }
        case .updated:
            if !diff.updatedAnnotations.isEmpty {
                handleUpdatedAnnotations(diff.updatedAnnotations)
            } else if let annotationId = diff.annotationId {
                handleUpdatedAnnotation(annotationId: annotationId)
            } else {
                outlineView?.reloadData()
            }
        case .deleted:
            if let bookDiff = diff.bookDeletionDiff, let outlineView {
                applyBookModeDeletions(diff: bookDiff, in: outlineView)
            } else if let annotationId = diff.annotationId {
                handleDeletedAnnotation(annotationId: annotationId, oldParentIndex: diff.oldParentIndex, newParentIndex: diff.newParentIndex)
            } else {
                outlineView?.reloadData()
            }
        }
    }

    private func handleAddedAnnotation(annotationId: Int64, oldParentIndex: Int?, newParentIndex: Int?) {
        guard let outlineView else { return }
        guard let location = findAnnotationLocation(in: treeBuilder.currentRootNode(), annotationId: annotationId) else {
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

    private func handleUpdatedAnnotations(_ annotations: [Annotation]) {
        guard let outlineView else { return }
        var rowsToReload = IndexSet()
        for ann in annotations {
            if let id = ann.id, let row = rowIndex(forAnnotationId: id) {
                rowsToReload.insert(row)
            }
        }
        guard !rowsToReload.isEmpty else { return }
        let columns = IndexSet(integersIn: 0 ..< outlineView.numberOfColumns)
        outlineView.reloadData(forRowIndexes: rowsToReload, columnIndexes: columns)
    }

    private func handleTagModeUpdate(diff: TagUpdateDiff?) {
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
        applyRemovals(removalsByParent, in: outlineView)
    }

    private func applyRemovals(
        _ removalsByParent: [AnnotationNode?: [Int]],
        in outlineView: NSOutlineView
    ) {
        for (parent, indices) in removalsByParent {
            if parent == nil || outlineView.isItemExpanded(parent) {
                let indexSet = IndexSet(indices.filter { $0 != -1 })
                if !indexSet.isEmpty {
                    outlineView.removeItems(at: indexSet, inParent: parent, withAnimation: .slideUp)
                }
            } else {
                outlineView.reloadItem(parent, reloadChildren: false)
            }
        }
    }

    private func applyTagModeAdditions(entries: [TagUpdateDiff.AddedEntry], in outlineView: NSOutlineView) {
        guard let root = treeBuilder.currentRootNode() else { return }
        guard !entries.isEmpty else { return }

        var insertedNewTagNodes = Set<ObjectIdentifier>()
        var childrenByTagNode: [AnnotationNode: [Int]] = [:]
        var nodesToExpand: [AnnotationNode] = []

        outlineView.beginUpdates()

        for entry in entries {
            if entry.tagNodeIsNew {
                let tagId = ObjectIdentifier(entry.tagNode)
                if !insertedNewTagNodes.contains(tagId) {
                    insertedNewTagNodes.insert(tagId)
                    if let rootIdx = root.children.firstIndex(where: { $0 === entry.tagNode }) {
                        outlineView.insertItems(at: IndexSet(integer: rootIdx), inParent: nil, withAnimation: .slideDown)
                        if groupingMode == .timeline {
                            nodesToExpand.append(entry.tagNode)
                        }
                    }
                }
            } else if !insertedNewTagNodes.contains(ObjectIdentifier(entry.tagNode)) {
                if let annIdx = entry.tagNode.children.firstIndex(where: { $0 === entry.annotationNode }) {
                    childrenByTagNode[entry.tagNode, default: []].append(annIdx)
                }
            }
        }

        for (tagNode, indices) in childrenByTagNode {
            if outlineView.isItemExpanded(tagNode) {
                let sortedIndices = indices.sorted()
                outlineView.insertItems(at: IndexSet(sortedIndices), inParent: tagNode, withAnimation: .slideDown)
            } else {
                outlineView.reloadItem(tagNode, reloadChildren: false)
            }
        }

        outlineView.endUpdates()

        for node in nodesToExpand {
            outlineView.expandItem(node, expandChildren: true)
        }
    }

    private func applyBookModeAdditions(diff: BookAdditionDiff, in outlineView: NSOutlineView) {
        guard !diff.isEmpty else { return }
        if diff.requiresFullReload {
            outlineView.reloadData()
            return
        }

        outlineView.beginUpdates()

        // 1. Insert new parents into root
        let parentIndices = IndexSet(diff.addedParents.map(\.newRootIndex))
        if !parentIndices.isEmpty {
            outlineView.insertItems(at: parentIndices, inParent: nil, withAnimation: .slideDown)
        }

        // 2. Insert children into existing parents
        var childrenByParent: [AnnotationNode: [Int]] = [:]
        for childEntry in diff.addedChildren {
            childrenByParent[childEntry.parentNode, default: []].append(childEntry.newChildIndex)
        }

        for (parent, indices) in childrenByParent {
            if outlineView.isItemExpanded(parent) {
                let sortedIndices = indices.sorted()
                outlineView.insertItems(at: IndexSet(sortedIndices), inParent: parent, withAnimation: .slideDown)
            } else {
                outlineView.reloadItem(parent, reloadChildren: false)
            }
        }

        outlineView.endUpdates()
    }

    private func applyBookModeDeletions(diff: BookDeletionDiff, in outlineView: NSOutlineView) {
        if diff.removedChildren.isEmpty, diff.removedParents.isEmpty, diff.movedParents.isEmpty {
            return
        }

        let totalChanges = diff.removedChildren.count + diff.removedParents.count
        if totalChanges > 100 {
            outlineView.reloadData()
            return
        }

        outlineView.beginUpdates()

        let removedParentIdentifiers = Set(diff.removedParents.map { ObjectIdentifier($0.parentNode) })

        // 1. Group removed children by parent (only for parents that aren't themselves removed)
        var removalsByParent: [AnnotationNode?: [Int]] = [:]
        for removed in diff.removedChildren where !removedParentIdentifiers.contains(ObjectIdentifier(removed.parentNode)) {
            removalsByParent[removed.parentNode, default: []].append(removed.oldChildIndex)
        }
        applyRemovals(removalsByParent, in: outlineView)

        // 2. Remove empty parents from root (sorted descending by oldRootIndex to keep indices valid)
        let sortedParents = diff.removedParents.sorted { $0.oldRootIndex > $1.oldRootIndex }
        for parentEntry in sortedParents where parentEntry.oldRootIndex >= 0 {
            outlineView.removeItems(at: IndexSet(integer: parentEntry.oldRootIndex), inParent: nil, withAnimation: .slideUp)
        }

        // 3. Move parents whose position changed
        for moved in diff.movedParents where moved.oldIndex != moved.newIndex {
            outlineView.moveItem(at: moved.oldIndex, inParent: nil, to: moved.newIndex, inParent: nil)
        }

        outlineView.endUpdates()
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
              !(treeBuilder.currentRootNode()?.children.contains { $0 === parentNode } ?? false)
        else { return }

        var parentIndex = outlineView.childIndex(forItem: parentNode)
        if parentIndex == -1 {
            let row = outlineView.row(forItem: parentNode)
            if row != -1 {
                parentIndex = (0 ..< row).reduce(0) { count, r in
                    let it = outlineView.item(atRow: r)
                    return outlineView.parent(forItem: it) == nil ? count + 1 : count
                }
            }
        }
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
        applyOutlineViewConfiguration()
        treeBuilder.buildAnnotationTree()
    }

    func updateSorting(field: AnnotationSortField, isAscending: Bool) {
        viewModel.sortField = field
        viewModel.sortAscending = isAscending
        treeBuilder.updateSorting(field: field, isAscending: isAscending)
    }

    func updateGrouping(mode: AnnotationGroupingMode) {
        viewModel.groupingMode = mode
        applyOutlineViewConfiguration()
        treeBuilder.updateGroupingMode(mode)
    }

    private func applyOutlineViewConfiguration() {
        let isTimeline = (groupingMode == .timeline)
        outlineView?.floatsGroupRows = isTimeline
        outlineView?.indentationPerLevel = isTimeline ? 0 : 13
        outlineView?.intercellSpacing = isTimeline ? .zero : NSSize(width: 17, height: 0)
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
        if groupingMode == .timeline, item.kind == .dateBucket {
            return
        }
        if !item.children.isEmpty {
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
        }
    }
}
