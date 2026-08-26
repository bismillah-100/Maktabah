//
//  AnnotationMenu.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//

import Cocoa

extension AnnotationOutlineDataSource: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let outlineView else { return }

        let nodes = effectiveNodes(for: outlineView)
        let annotationIDs = prepareContextMenuSelection()

        let hasAnnotations = nodes.contains { $0.annotation != nil }
        let hasTagRoots = nodes.contains { $0.kind == .tag }
        let hasBookRoots = nodes.contains { $0.kind == .book }
        let hasUntaggedRoot = nodes.contains { $0.kind == .untagged }

        let shouldHideDelete = nodes.isEmpty || hasUntaggedRoot

        deleteMenuItem.isHidden = shouldHideDelete
        deleteMenuItem.target = self
        deleteMenuItem.action = #selector(deleteItem(_:))

        if !shouldHideDelete {
            updateDeleteMenuItemTitle(hasAnnotations: hasAnnotations, hasTagRoots: hasTagRoots, hasBookRoots: hasBookRoots)
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

        let isSingleTagRoot = nodes.count == 1 && nodes.first?.kind == .tag
        renameTagMenuItem.isHidden = !isSingleTagRoot || groupingMode != .tag
        renameTagMenuItem.target = self
        renameTagMenuItem.action = #selector(renameTagClicked(_:))
    }

    private func updateDeleteMenuItemTitle(hasAnnotations: Bool, hasTagRoots: Bool, hasBookRoots: Bool) {
        if groupingMode == .tag, hasTagRoots {
            deleteMenuItem.title = hasAnnotations ? String(localized: .deleteTagAnnotation) : String(localized: .deleteTag)
        } else if groupingMode == .book, hasBookRoots, hasAnnotations {
            deleteMenuItem.title = String(localized: .deleteAnnotation)
        } else {
            deleteMenuItem.title = String(localized: "Delete")
        }
    }

    func setupOutlineMenu() {
        menu.delegate = self

        let itemsToAdd: [NSMenuItem] = [
            addTagMenuItem,
            removeTagMenuItem,
            renameTagMenuItem,
            .separator(),
            copyMenuItem,
            .separator(),
            deleteMenuItem,
        ]

        menu.removeAllItems()
        for item in itemsToAdd {
            menu.addItem(item)
        }

        outlineView?.menu = menu
    }

    // MARK: - Actions

    @objc func copyClickedAnnotation(_: NSMenuItem) {
        guard let rtfData = exportToRTF() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(rtfData, forType: .rtf)
    }

    @objc private func addTagClicked(_: NSMenuItem) {
        let annotationIDs = prepareContextMenuSelection()
        guard !annotationIDs.isEmpty else { return }
        onAddTagsRequested?(annotationIDs, outlineView?.contextMenuAnchorRect() ?? .zero)
    }

    @objc private func removeTagClicked(_: NSMenuItem) {
        let annotationIDs = prepareContextMenuSelection()
        guard !annotationIDs.isEmpty else { return }
        onRemoveTagsRequested?(annotationIDs, outlineView?.contextMenuAnchorRect() ?? .zero)
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
              let textField = cell.textField
        else { return }

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
        else { return }

        let currentName = tagNode.title
        let newName = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != currentName else {
            sender.stringValue = currentName
            return
        }

        let existingTags = AnnotationManager.shared.allTagNames()
        let wouldMerge = existingTags.contains {
            $0.caseInsensitiveCompare(newName) == .orderedSame && $0.caseInsensitiveCompare(currentName) != .orderedSame
        }

        if wouldMerge {
            presentTagMergePopover(from: currentName, to: newName, sender: sender)
        } else {
            performTagRename(from: currentName, to: newName, sender: sender)
        }
    }

    private func performTagRename(from currentName: String, to newName: String, sender: NSTextField) {
        do {
            try viewModel.renameTag(from: currentName, to: newName)
        } catch {
            sender.stringValue = currentName
            let errorAlert = NSAlert()
            errorAlert.messageText = String(localized: "Rename Failed")
            errorAlert.informativeText = error.localizedDescription
            errorAlert.runModal()
        }
    }

    private func presentTagMergePopover(from currentName: String, to newName: String, sender: NSTextField) {
        sender.stringValue = currentName
        let tagMergePopoverVC = TagMergePopoverVC(oldName: currentName, newName: newName)
        let popover = NSPopover()
        popover.contentViewController = tagMergePopoverVC
        popover.behavior = .transient
        popover.show(relativeTo: sender.frame, of: sender, preferredEdge: .maxY)

        tagMergePopoverVC.onConfirm = { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.performTagRename(from: currentName, to: newName, sender: sender)
        }

        tagMergePopoverVC.onCancel = { [weak sender, weak popover] in
            sender?.stringValue = currentName
            popover?.performClose(nil)
        }
    }

    // MARK: - Export RTF

    func exportToRTF(nodes: [AnnotationNode]? = nil) -> Data? {
        guard let outlineView else { return nil }
        let row = outlineView.clickedRow == -1 ? outlineView.selectedRow : outlineView.clickedRow
        guard let item = outlineView.item(atRow: row) as? AnnotationNode else { return nil }

        let items = nodes ?? [item]
        return AnnotationRTFExporter.rtfData(for: items, calendar: calendar)
    }

    // MARK: - Delete Action

    @objc func deleteItem(_ sender: NSMenuItem) {
        guard let outlineView else { return }

        let nodes: [AnnotationNode] = if let row = sender.representedObject as? Int,
                                         let node = outlineView.item(atRow: row) as? AnnotationNode
        {
            [node]
        } else {
            effectiveNodes(for: outlineView)
        }

        guard !nodes.isEmpty, !nodes.contains(where: { $0.kind == .untagged }) else { return }

        let annotationNodes = nodes.filter { $0.annotation != nil }
        let tagRootNodes = nodes.filter { $0.kind == .tag }
        let bookRootNodes = nodes.filter { $0.kind == .book }

        if groupingMode == .tag {
            performDeleteTagRoots(tagRootNodes)
            performDeleteAnnotations(annotationNodes)
        } else if !annotationNodes.isEmpty {
            performDeleteAnnotations(annotationNodes)
        } else if !bookRootNodes.isEmpty {
            performDeleteBookRoots(bookRootNodes)
        }
    }

    private func performDeleteTagRoots(_ nodes: [AnnotationNode]) {
        for node in nodes where node.kind == .tag {
            do {
                try viewModel.deleteTag(named: node.title)
            } catch {
                #if DEBUG
                print("Error deleting tag '\(node.title)': \(error)")
                #endif
            }
        }
    }

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
            performDeleteAnnotations(bookNode.children)
        }
    }
}

private extension AnnotationOutlineDataSource {
    func effectiveNodes(for outlineView: NSOutlineView) -> [AnnotationNode] {
        outlineView.effectiveRows().compactMap {
            outlineView.item(atRow: $0) as? AnnotationNode
        }
    }

    func prepareContextMenuSelection() -> [Int64] {
        guard let outlineView else { return [] }
        let nodes = effectiveNodes(for: outlineView)
        guard nodes.allSatisfy({ $0.annotation != nil }) else { return [] }
        return nodes.compactMap { $0.annotation?.id }
    }
}
