//
//  AnnotationsOutlineDataSource.swift
//  maktab
//
//  Created by MacBook on 15/12/25.
//  Handle offline imported books
//

import Cocoa

@MainActor
class AnnotationOutlineDataSource: NSObject, NSOutlineViewDataSource {
    weak var delegate: AnnotationDelegate?
    weak var outlineView: NSOutlineView?
    var onAddTagsRequested: (([Int64], NSRect) -> Void)?
    var onRemoveTagsRequested: (([Int64], NSRect) -> Void)?

    let paragraphStyle = NSMutableParagraphStyle()

    let viewModel = AnnotationViewModel()

    /// Cache Formatter
    private let calendar = Calendar.current

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private lazy var relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var onSelectItem: ((Int) -> Void)?

    var groupingMode: AnnotationGroupingMode { viewModel.groupingMode }

    let menu = NSMenu()

    lazy var deleteMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = NSLocalizedString("Delete", comment: "")
        item.image = NSImage(
            systemSymbolName: "trash.slash",
            accessibilityDescription: ""
        )
        return item
    }()

    lazy var copyMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = NSLocalizedString("Copy", comment: "")
        item.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: ""
        )
        return item
    }()

    lazy var addTagMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = "Add Tags".localized + threeDots
        item.image = NSImage(
            systemSymbolName: "tag",
            accessibilityDescription: ""
        )
        return item
    }()

    lazy var removeTagMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = "Remove Tags".localized + threeDots
        item.image = NSImage(
            systemSymbolName: "tag.slash",
            accessibilityDescription: ""
        )
        return item
    }()

    lazy var renameTagMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = String(localized: "Rename Tag") + threeDots
        item.image = NSImage(
            systemSymbolName: "pencil.line",
            accessibilityDescription: ""
        )
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

    private func handleIncrementalChange(changeType: AnnotationChangeType, userInfo: [AnyHashable: Any]) {
        let annotation = userInfo[AnnotationNotificationKeys.annotation] as? Annotation
        let annotationId = (userInfo[AnnotationNotificationKeys.annotationId] as? Int64) ?? annotation?.id
        let oldParentIndex = userInfo[AnnotationNotificationKeys.oldParentIndex] as? Int
        let newParentIndex = userInfo[AnnotationNotificationKeys.newParentIndex] as? Int

        guard let annotationId else {
            outlineView?.reloadData()
            return
        }

        switch changeType {
        case .added:
            if groupingMode == .tag {
                let diff = userInfo[AnnotationNotificationKeys.tagDiff] as? TagUpdateDiff
                handleTagModeUpdate(annotationId: annotationId, diff: diff)
            } else {
                handleAddedAnnotation(annotationId: annotationId, oldParentIndex: oldParentIndex, newParentIndex: newParentIndex)
            }
        case .updated, .deleted:
            if groupingMode == .tag {
                let diff = userInfo[AnnotationNotificationKeys.tagDiff] as? TagUpdateDiff
                handleTagModeUpdate(annotationId: annotationId, diff: diff)
            } else if changeType == .updated {
                handleUpdatedAnnotation(annotationId: annotationId)
            } else {
                handleDeletedAnnotation(annotationId: annotationId, oldParentIndex: oldParentIndex, newParentIndex: newParentIndex)
            }
        }
    }

    private func handleAddedAnnotation(annotationId: Int64, oldParentIndex: Int?, newParentIndex: Int?) {
        guard let outlineView else { return }
        guard
            let location = findAnnotationLocation(in: AnnotationManager.shared.rootNode, annotationId: annotationId)
        else {
            outlineView.reloadData()
            return
        }

        let parentRow = outlineView.row(forItem: location.parentNode)

        if let oldIdx = oldParentIndex, let newIdx = newParentIndex, oldIdx != newIdx, parentRow != -1 {
            outlineView.moveItem(at: oldIdx, inParent: nil, to: newIdx, inParent: nil)
        }

        if parentRow == -1 {
            // Note: location.parentIndex will be the *new* index because we find location in the updated rootNode
            outlineView.insertItems(
                at: IndexSet(integer: location.parentIndex),
                inParent: nil,
                withAnimation: .slideDown
            )
            return
        }

        if outlineView.isItemExpanded(location.parentNode) {
            outlineView.insertItems(
                at: IndexSet(integer: location.annotationIndex),
                inParent: location.parentNode,
                withAnimation: .slideDown
            )
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
        outlineView.reloadData(
            forRowIndexes: IndexSet(integer: row),
            columnIndexes: columns
        )
    }

    private func handleTagModeUpdate(annotationId _: Int64, diff: TagUpdateDiff?) {
        guard let outlineView else { return }
        guard let diff = diff else {
            outlineView.reloadData()
            return
        }

        // Reload semua jika pembaruan terlalu banyak
        let totalChanges = diff.updated.count
            + diff.removed.count + diff.added.count
        if totalChanges > 100 {
            outlineView.reloadData()
            return
        }

        outlineView.beginUpdates()
        let columns = IndexSet(integersIn: 0 ..< outlineView.numberOfColumns)

        // 1. Reload annotation node yang hanya ganti teks/warna (tag tidak berubah)
        //    Outline view masih punya state lama, row masih valid.
        for annNode in diff.updated {
            let row = outlineView.row(forItem: annNode)
            if row != -1 {
                outlineView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: columns)
            }
        }

        // 2. Remove — gunakan oldIndex dari diff karena model sudah terupdate
        // Kelompokkan penghapusan berdasarkan parent node
        var removalsByParent: [AnnotationNode?: [Int]] = [:]
        for entry in diff.removed {
            let parent = entry.tagNodeBecomesEmpty ? nil : entry.tagNode
            removalsByParent[parent, default: []].append(entry.oldIndex)
        }

        for (parent, indices) in removalsByParent {
            let indexSet = IndexSet(indices.filter { $0 != -1 })
            if !indexSet.isEmpty {
                outlineView.removeItems(
                    at: indexSet,
                    inParent: parent,
                    withAnimation: .slideUp
                )
            }
        }

        // 3. Insert — gunakan index dari tree model yang sudah diupdate
        let root = AnnotationManager.shared.rootNode
        for entry in diff.added {
            if entry.tagNodeIsNew {
                // Tag node baru — insert ke root
                if let rootIdx = root?.children.firstIndex(where: { $0 === entry.tagNode }) {
                    outlineView.insertItems(
                        at: IndexSet(integer: rootIdx),
                        inParent: nil,
                        withAnimation: .slideDown
                    )
                    // Tag node baru collapsed by default, tidak perlu insert children
                }
            } else {
                // Tag node sudah ada — insert annotation node di dalamnya
                if outlineView.isItemExpanded(entry.tagNode) {
                    if let annIdx = entry.tagNode.children.firstIndex(where: { $0 === entry.annotationNode }) {
                        outlineView.insertItems(
                            at: IndexSet(integer: annIdx),
                            inParent: entry.tagNode,
                            withAnimation: .slideDown
                        )
                    }
                } else {
                    // Collapsed — reload supaya badge/count ter-update jika ada
                    outlineView.reloadItem(entry.tagNode, reloadChildren: false)
                }
            }
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
            outlineView.removeItems(
                at: IndexSet(integer: childIndex),
                inParent: parent,
                withAnimation: .slideUp
            )
        } else {
            outlineView.reloadItem(
                parent,
                reloadChildren: true
            )
        }

        if let oldIdx = oldParentIndex, let newIdx = newParentIndex, oldIdx != newIdx {
            outlineView.moveItem(at: oldIdx, inParent: nil, to: newIdx, inParent: nil)
        }

        if let parentNode = parent as? AnnotationNode,
           parentNode.children.isEmpty,
           !(AnnotationManager.shared.rootNode?.children.contains { $0 === parentNode } ?? false)
        {
            let parentIndex = outlineView.childIndex(forItem: parentNode)
            if parentIndex != -1 {
                outlineView.removeItems(
                    at: IndexSet(integer: parentIndex),
                    inParent: nil,
                    withAnimation: .slideUp
                )
            }
        }
    }

    private func rowIndex(forAnnotationId annotationId: Int64) -> Int? {
        guard let outlineView else { return nil }
        for row in 0 ..< outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? AnnotationNode else { continue }
            if node.annotation?.id == annotationId {
                return row
            }
        }
        return nil
    }

    private func findAnnotationLocation(in root: AnnotationNode?, annotationId: Int64) -> (
        parentNode: AnnotationNode,
        parentIndex: Int,
        annotationIndex: Int
    )? {
        guard let root else { return nil }

        for (parentIndex, parentNode) in root.children.enumerated() {
            if let annotationIndex = parentNode.children.firstIndex(where: { $0.annotation?.id == annotationId }) {
                return (parentNode, parentIndex, annotationIndex)
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

    // MARK: - Copy Action

    @objc func copyClickedAnnotation(_: NSMenuItem) {
        guard let rtfData = exportToRTF() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(rtfData, forType: .rtf)
    }

    @objc private func addTagClicked(_: NSMenuItem) {
        let annotationIDs = prepareContextMenuSelection()
        guard !annotationIDs.isEmpty else { return }
        onAddTagsRequested?(annotationIDs, contextMenuAnchorRect())
    }

    @objc private func removeTagClicked(_: NSMenuItem) {
        let annotationIDs = prepareContextMenuSelection()
        guard !annotationIDs.isEmpty else { return }
        onRemoveTagsRequested?(annotationIDs, contextMenuAnchorRect())
    }

    @objc private func renameTagClicked(_ sender: NSMenuItem) {
        guard let outlineView else { return }

        let nodes = effectiveNodes(for: outlineView)
        guard nodes.count == 1,
              let tagNode = nodes.first,
              tagNode.kind == .tag
        else { return }

        let row = outlineView.row(forItem: tagNode)
        guard row != -1,
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let textField = cell.textField else { return }

        textField.isEditable = true
        textField.target = self
        textField.action = #selector(tagRenameDidComplete(_:))
        outlineView.window?.makeFirstResponder(textField)
    }

    @objc private func tagRenameDidComplete(_ sender: NSTextField) {
        sender.isEditable = false
        sender.target = nil
        sender.action = nil

        guard let outlineView else { return }

        let row = outlineView.row(for: sender)
        guard row != -1,
              let tagNode = outlineView.item(atRow: row) as? AnnotationNode,
              tagNode.kind == .tag
        else {
            return
        }

        let currentName = tagNode.title
        let newName = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != currentName else {
            sender.stringValue = currentName
            return
        }

        func rename(from currentName: String, to newName: String) {
            do {
                try AnnotationManager.shared.renameTag(from: currentName, to: newName)
            } catch {
                sender.stringValue = currentName
                let errorAlert = NSAlert()
                errorAlert.messageText = String(localized: "Rename Failed")
                errorAlert.informativeText = error.localizedDescription
                errorAlert.runModal()
            }
        }

        // ── Deteksi merge: cek case-insensitively apakah newName sudah ada ──
        let existingTags = AnnotationManager.shared.allTagNames()
        let wouldMerge = existingTags.contains {
            $0.caseInsensitiveCompare(newName) == .orderedSame
                && $0.caseInsensitiveCompare(currentName) != .orderedSame
        }

        if wouldMerge {
            sender.stringValue = currentName
            let tagMergePopoverVC = TagMergePopoverVC(oldName: currentName, newName: newName)
            let popover = NSPopover()
            popover.contentViewController = tagMergePopoverVC
            popover.behavior = .transient
            popover.show(relativeTo: sender.frame, of: sender, preferredEdge: .maxY)

            tagMergePopoverVC.onConfirm = { [weak popover] in
                popover?.performClose(nil)
                rename(from: currentName, to: newName)
            }

            tagMergePopoverVC.onCancel = { [weak sender, weak popover] in
                print("Merge cancelled, keeping original name: \(currentName)")
                sender?.stringValue = currentName
                popover?.performClose(nil)
            }
        } else {
            rename(from: currentName, to: newName)
        }
    }

    // MARK: - Export RTF

    func exportToRTF(nodes: [AnnotationNode]? = nil) -> Data? {
        guard let outlineView else { return nil }

        let row = outlineView.clickedRow == -1
            ? outlineView.selectedRow
            : outlineView.clickedRow

        guard let item = outlineView.item(atRow: row) as? AnnotationNode else {
            return nil
        }

        let items = nodes ?? [item]
        let attr = buildAttributedString(nodes: items)

        do {
            return try attr.data(
                from: NSRange(location: 0, length: attr.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.rtf,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ]
            )
        } catch {
            print("Export RTF Gagal:", error)
            return nil
        }
    }

    private func buildAttributedString(nodes: [AnnotationNode])
        -> NSAttributedString
    {
        let result = NSMutableAttributedString()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.paragraphSpacingBefore = 4
        paragraphStyle.paragraphSpacing = 8

        for node in nodes {
            // =========================
            // HEADER BUKU / FOLDER
            // =========================
            if node.annotation == nil {
                let titleAttr = NSAttributedString(
                    string: "\(node.title)\n",
                    attributes: [
                        .font: NSFont.boldSystemFont(ofSize: 18),
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )

                result.append(titleAttr)

                if !node.children.isEmpty {
                    let childAttr = buildAttributedString(nodes: node.children)
                    result.append(childAttr)
                }
            }

            // =========================
            // ANOTASI
            // =========================
            else if let annotation = node.annotation {
                let color = NSColor(hex: annotation.colorHex) ?? .yellow

                let contextText = "\(annotation.context)\n"
                let attrContext = NSMutableAttributedString(
                    string: contextText,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 14),
                        .paragraphStyle: paragraphStyle,
                    ]
                )

                let fullRg = NSRange(location: 0, length: attrContext.length)

                if annotation.type == .highlight {
                    attrContext.addAttribute(
                        .backgroundColor,
                        value: color.withAlphaComponent(0.3),
                        range: fullRg
                    )
                } else if annotation.type == .underline {
                    attrContext.addAttribute(
                        .underlineStyle,
                        value: NSUnderlineStyle.single.rawValue,
                        range: fullRg
                    )
                    attrContext.addAttribute(
                        .underlineColor,
                        value: color,
                        range: fullRg
                    )
                }

                result.append(attrContext)

                // -------------------------
                // NOTE
                // -------------------------
                if let noteText = annotation.note {
                    let attrNote = NSAttributedString(
                        string: "\"\(noteText)\"\n",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 13),
                            .foregroundColor: NSColor.secondaryLabelColor,
                            .paragraphStyle: paragraphStyle,
                        ]
                    )
                    result.append(attrNote)
                }

                // -------------------------
                // METADATA
                // -------------------------
                let targetDate = Date(
                    timeIntervalSince1970: TimeInterval(annotation.createdAt)
                )
                let dateString =
                    calendar.isDateInToday(targetDate)
                        ? relativeFormatter.localizedString(
                            for: targetDate,
                            relativeTo: Date()
                        )
                        : dateFormatter.string(from: targetDate)

                let kitab = LibraryDataManager.shared.getBook([annotation.bkId]).first?.book ?? "<Unknown Book>"
                let metaText =
                    "\(kitab) • الجزء: \(annotation.partArb ?? "-") • الصفحة: \(annotation.pageArb ?? "-") \(annotation.tags.map { " -- \($0)" }.joined(separator: " "))\n\(dateString)"

                let attrMeta = NSAttributedString(
                    string: metaText + "\n",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )

                result.append(attrMeta)
                result.append(NSAttributedString(string: "\n\n\n"))
            }
        }

        return result
    }

    // MARK: - Delete Action

    @objc func deleteItem(_ sender: NSMenuItem) {
        guard let outlineView else { return }

        // Swipe-to-delete menyetel representedObject = row.
        // Context menu tidak, jadi gunakan effectiveNodes.
        let nodes: [AnnotationNode]
        if let row = sender.representedObject as? Int {
            guard let node = outlineView.item(atRow: row) as? AnnotationNode else { return }
            nodes = [node]
        } else {
            nodes = effectiveNodes(for: outlineView)
        }

        guard !nodes.isEmpty else { return }

        let annotationNodes = nodes.filter { $0.annotation != nil }
        let tagRootNodes = nodes.filter { $0.kind == .tag }
        let bookRootNodes = nodes.filter { $0.kind == .book }
        let untaggedNodes = nodes.filter { $0.kind == .untagged }

        // Untagged root tidak bisa dihapus
        guard untaggedNodes.isEmpty else { return }

        if groupingMode == .tag {
            if !annotationNodes.isEmpty, !tagRootNodes.isEmpty {
                // Mode Tag, seleksi campuran → hapus tag root + anotasi
                performDeleteTagRoots(tagRootNodes)
                performDeleteAnnotations(annotationNodes)
            } else if !tagRootNodes.isEmpty {
                // Hanya tag root
                performDeleteTagRoots(tagRootNodes)
            } else {
                // Hanya anotasi
                performDeleteAnnotations(annotationNodes)
            }
        } else {
            // Book mode
            if !annotationNodes.isEmpty, !bookRootNodes.isEmpty {
                // Seleksi campuran → hapus anotasi saja (bukan book root)
                performDeleteAnnotations(annotationNodes)
            } else if !bookRootNodes.isEmpty {
                // Hanya book root → hapus semua anotasi di dalamnya
                performDeleteBookRoots(bookRootNodes)
            } else {
                // Hanya anotasi
                performDeleteAnnotations(annotationNodes)
            }
        }
    }

    /// Hapus tag dari semua anotasi yang memilikinya (anotasi tidak dihapus)
    private func performDeleteTagRoots(_ nodes: [AnnotationNode]) {
        for node in nodes where node.kind == .tag {
            do {
                try AnnotationManager.shared.deleteTag(named: node.title)
            } catch {
                #if DEBUG
                    print("Error deleting tag '\(node.title)': \(error)")
                #endif
            }
        }
    }

    /// Hapus anotasi satu per satu (notification chain menangani UI update)
    private func performDeleteAnnotations(_ nodes: [AnnotationNode]) {
        for node in nodes {
            guard let annotation = node.annotation, let id = annotation.id else { continue }
            do {
                try AnnotationManager.shared.deleteAnnotation(id: id)
            } catch {
                #if DEBUG
                    print("Error deleting annotation \(id): \(error)")
                #endif
            }
        }
    }

    private func performDeleteBookRoots(_ nodes: [AnnotationNode]) {
        for bookNode in nodes where bookNode.kind == .book {
            for childNode in bookNode.children {
                guard let annotation = childNode.annotation, let id = annotation.id else {
                    continue
                }
                do {
                    try AnnotationManager.shared.deleteAnnotation(id: id)
                } catch {
                    #if DEBUG
                        print(
                            "Error deleting annotation \(id) from book '\(bookNode.title)': \(error)"
                        )
                    #endif
                }
            }
        }
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(
        _ outlineView: NSOutlineView,
        numberOfChildrenOfItem item: Any?
    ) -> Int {
        if item == nil {
            return viewModel.filteredNodes.count
        }
        if let node = item as? AnnotationNode {
            return node.children.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any)
        -> Bool
    {
        if let node = item as? AnnotationNode {
            return !node.children.isEmpty
        }
        return false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        child index: Int,
        ofItem item: Any?
    ) -> Any {
        if item == nil {
            return viewModel.filteredNodes[index]
        }
        if let node = item as? AnnotationNode {
            return node.children[index]
        }
        fatalError("Invalid item or index.")
    }
}

extension AnnotationOutlineDataSource: NSOutlineViewDelegate,
    NSTableViewDelegate
{
    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? AnnotationNode else { return nil }

        // Node buku (tanpa annotation)
        if node.annotation == nil {
            let cell =
                outlineView.makeView(
                    withIdentifier: NSUserInterfaceItemIdentifier("BooksCell"),
                    owner: self
                ) as? NSTableCellView
            cell?.textField?.stringValue = node.title
            return cell
        }

        // Node anotasi
        guard let annotation = node.annotation,
              let color = NSColor(hex: annotation.colorHex),
              let cell = outlineView.makeView(
                  withIdentifier: NSUserInterfaceItemIdentifier("AnnotationCell"),
                  owner: self
              ) as? AnnotationCellView
        else {
            return nil
        }

        let text = annotation.context
        let attributedString = NSMutableAttributedString(string: text)

        attributedString.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: text.count)
        )
        attributedString.addAttribute(
            .font,
            value: ReusableFunc.bundledArabicFont(ofSize: 17),
            range: NSRange(location: 0, length: text.count)
        )
        let fullRg = NSRange(location: 0, length: attributedString.length)

        switch annotation.type {
        case .highlight:
            attributedString.addAttribute(
                .backgroundColor,
                value: color.withAlphaComponent(0.3),
                range: fullRg
            )
        case .underline:
            attributedString.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: fullRg
            )
        }

        let page = "الجزء: \(annotation.partArb ?? "-") • الصفحة: \(annotation.pageArb ?? "-")"
        let tags = annotation.tags.map { " -- \($0)" }.joined(separator: " ")

        cell.pagePart.stringValue = switch groupingMode {
        case .book:
            page + tags
        case .tag:
            if let book = LibraryDataManager.shared
                .getBook([annotation.bkId]).first?.book
            {
                page + tags + "\n" + book
            } else {
                page + tags + "\n" + String(localized: .bookNotFound(bookID: annotation.bkId))
            }
        }

        cell.applyLineLimits()
        cell.context.attributedStringValue = attributedString

        if annotation.note == nil {
            cell.note.isHidden = true
        } else if let note = annotation.note {
            cell.note.isHidden = false
            cell.note.stringValue = note
        }

        let timestampInt64 = annotation.createdAt
        let targetDate = Date(
            timeIntervalSince1970: TimeInterval(timestampInt64)
        )

        let formattedString: String = if calendar.isDateInToday(targetDate) {
            relativeFormatter.localizedString(
                for: targetDate,
                relativeTo: Date()
            )
        } else {
            dateFormatter.string(from: targetDate)
        }

        cell.date.stringValue = formattedString
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any)
        -> CGFloat
    {
        guard let node = item as? AnnotationNode,
              let annotation = node.annotation
        else {
            return 30
        }

        let columnWidth = outlineView.outlineTableColumn?.width ?? outlineView.bounds.width
        let contentWidth = max(columnWidth - 40, 120)

        let contextHeight = measuredHeight(
            for: annotation.context,
            width: contentWidth * 0.72,
            font: ReusableFunc.bundledArabicFont(ofSize: 17),
            lineLimit: UserDefaults.standard.ctxMaxNumberOfLines,
            paragraphStyle: paragraphStyle
        )

        let noteHeight: CGFloat = if let note = annotation.note, !note.isEmpty {
            measuredHeight(
                for: note,
                width: contentWidth,
                font: NSFont.systemFont(ofSize: 15),
                lineLimit: UserDefaults.standard.annMaxNumberOfLines
            )
        } else {
            0
        }

        let page = "الجزء: \(annotation.partArb ?? "-") • الصفحة: \(annotation.pageArb ?? "-")"
        let tags = annotation.tags.map { " -- \($0)" }.joined(separator: " ")
        let pagePartText = switch groupingMode {
        case .book:
            page + tags
        case .tag:
            if let book = LibraryDataManager.shared
                .getBook([annotation.bkId]).first?.book
            {
                page + tags + "\n" + book
            } else {
                page + tags + "\n" + String(localized: .bookNotFound(bookID: annotation.bkId))
            }
        }

        let pagePartHeight = measuredHeight(
            for: pagePartText,
            width: contentWidth * 0.72,
            font: NSFont.systemFont(ofSize: 15),
            lineLimit: AnnotationCellView.pagePartLineLimit
        )

        let footnoteFont = NSFont.preferredFont(forTextStyle: .footnote)
        let dateHeight = ceil(
            footnoteFont.ascender - footnoteFont.descender + footnoteFont.leading
        )
        let topSectionHeight = max(contextHeight, dateHeight + 8)
        let stackSpacing: CGFloat = noteHeight > 0 ? 16 : 8

        return ceil(20 + topSectionHeight + pagePartHeight + noteHeight + stackSpacing)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else {
            return
        }

        let row = outlineView.selectedRow
        onSelectItem?(row)

        guard let item = outlineView.item(atRow: row) as? AnnotationNode,
              let annotation = item.annotation
        else {
            #if DEBUG
                print("outlineView item not as Annotations")
            #endif
            return
        }

        delegate?.didSelect(annotation: annotation)
    }

    func tableView(
        _ tableView: NSTableView,
        rowActionsForRow row: Int,
        edge: NSTableView.RowActionEdge
    ) -> [NSTableViewRowAction] {
        guard edge == .trailing else { return [] }

        let deleteAction = NSTableViewRowAction(
            style: .destructive,
            title: "Delete"
        ) { [weak self] _, _ in
            guard let self else { return }
            deleteMenuItem.representedObject = row
            deleteItem(deleteMenuItem)
        }

        if let baseImage = NSImage(
            systemSymbolName: "trash.slash.fill",
            accessibilityDescription: nil
        ) {
            // Konfigurasi simbol: pointSize sesuai tinggi row
            let config = NSImage.SymbolConfiguration(
                pointSize: 28,
                weight: .regular,
                scale: .large
            )
            let img = baseImage.withSymbolConfiguration(config)

            deleteAction.image = img
        }

        if let outlineView,
           let node = outlineView.item(atRow: row) as? AnnotationNode,
           node.annotation == nil,
           node.kind == AnnotationNodeKind.tag || node.kind == AnnotationNodeKind.untagged
        {
            return []
        }

        return [deleteAction]
    }
}

extension AnnotationOutlineDataSource {
    private func measuredHeight(
        for text: String,
        width: CGFloat,
        font: NSFont,
        lineLimit: Int,
        paragraphStyle: NSParagraphStyle? = nil
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }

        let attributes: [NSAttributedString.Key: Any] = {
            if let paragraphStyle {
                return [
                    .font: font,
                    .paragraphStyle: paragraphStyle,
                ]
            }
            return [.font: font]
        }()

        let measuredRect = NSString(string: text).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let maxHeight = lineHeight * CGFloat(max(lineLimit, 1))

        return max(lineHeight, min(ceil(measuredRect.height), maxHeight))
    }
}

// MARK: - Menu Delegate

extension AnnotationOutlineDataSource: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let outlineView else { return }

        let nodes = effectiveNodes(for: outlineView)
        let annotationIDs = prepareContextMenuSelection()

        let hasAnnotations = nodes.contains { $0.annotation != nil }
        let hasTagRoots = nodes.contains { $0.kind == .tag }
        let hasBookRoots = nodes.contains { $0.kind == .book }
        let hasUntaggedRoot = nodes.contains { $0.kind == .untagged }

        // Untagged root: tidak bisa dihapus via menu
        let shouldHideDelete = nodes.isEmpty || hasUntaggedRoot

        deleteMenuItem.isHidden = shouldHideDelete
        deleteMenuItem.target = self
        deleteMenuItem.action = #selector(deleteItem(_:))

        if !shouldHideDelete {
            switch (groupingMode, hasAnnotations, hasTagRoots, hasBookRoots) {
            case (.tag, true, true, _):
                // Mix anotasi + tag root → hapus keduanya
                deleteMenuItem.title = String(localized: .deleteTagAnnotation)
            case (.tag, false, true, _):
                // Hanya tag root
                deleteMenuItem.title = String(localized: .deleteTag)
            case (.book, true, _, true):
                // Mix anotasi + book root → hapus anotasi saja
                deleteMenuItem.title = String(localized: .deleteAnnotation)
            default:
                deleteMenuItem.title = String(localized: "Delete")
            }
        }

        copyMenuItem.isHidden = outlineView.clickedRow == -1
        copyMenuItem.target = self
        copyMenuItem.action = #selector(copyClickedAnnotation(_:))

        addTagMenuItem.isHidden = annotationIDs.isEmpty
        addTagMenuItem.target = self
        addTagMenuItem.action = #selector(addTagClicked(_:))

        removeTagMenuItem.isHidden = annotationIDs.isEmpty
        removeTagMenuItem.target = self
        removeTagMenuItem.action = #selector(removeTagClicked(_:))

        // Rename Tag: hanya tampil jika satu tag root dipilih, dan mode Tag
        let isSingleTagRoot = nodes.count == 1 && nodes.first?.kind == .tag
        renameTagMenuItem.isHidden = !isSingleTagRoot || groupingMode != .tag
        renameTagMenuItem.target = self
        renameTagMenuItem.action = #selector(renameTagClicked(_:))
    }

    func setupOutlineMenu() {
        menu.delegate = self

        if !menu.items.contains(addTagMenuItem) {
            menu.addItem(addTagMenuItem)
        }

        if !menu.items.contains(removeTagMenuItem) {
            menu.addItem(removeTagMenuItem)
        }

        if !menu.items.contains(renameTagMenuItem) {
            menu.addItem(renameTagMenuItem)
        }

        if !menu.items.contains(copyMenuItem) {
            menu.addItem(.separator())
            menu.addItem(copyMenuItem)
        }

        if !menu.items.contains(deleteMenuItem) {
            menu.addItem(.separator())
            menu.addItem(deleteMenuItem)
        }

        outlineView?.menu = menu
    }
}

private extension AnnotationOutlineDataSource {
    private func effectiveRows(for outlineView: NSOutlineView) -> IndexSet {
        let clickedRow = outlineView.clickedRow
        if clickedRow == -1 { return outlineView.selectedRowIndexes }
        return outlineView.selectedRowIndexes.contains(clickedRow)
            ? outlineView.selectedRowIndexes
            : IndexSet(integer: clickedRow)
    }

    private func effectiveNodes(for outlineView: NSOutlineView) -> [AnnotationNode] {
        effectiveRows(for: outlineView).compactMap {
            outlineView.item(atRow: $0) as? AnnotationNode
        }
    }

    func prepareContextMenuSelection() -> [Int64] {
        guard let outlineView else { return [] }
        let nodes = effectiveNodes(for: outlineView)
        // Kembalikan kosong jika ada node yang bukan annotation
        guard nodes.allSatisfy({ $0.annotation != nil }) else { return [] }
        return nodes.compactMap { $0.annotation?.id }
    }

    func contextMenuAnchorRect() -> NSRect {
        guard let outlineView else { return .zero }
        let anchorRow = outlineView.clickedRow >= 0
            ? outlineView.clickedRow
            : outlineView.selectedRow
        guard anchorRow >= 0 else { return outlineView.bounds }
        return outlineView.rect(ofRow: anchorRow)
    }
}
