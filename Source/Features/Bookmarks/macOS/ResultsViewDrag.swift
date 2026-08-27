//
//  ResultsViewDrag.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 27/08/26.
//


import Cocoa

extension ResultsViewManager {
    func outlineView(
        _ outlineView: NSOutlineView,
        pasteboardWriterForItem item: Any
    ) -> NSPasteboardWriting? {
        let pbItem = NSPasteboardItem()
        if let folder = item as? FolderNode {
            pbItem.setString(String(folder.id), forType: .folderNode)
            return pbItem
        }
        if let result = item as? ResultNode {
            pbItem.setString(String(result.id), forType: .resultNode)
            return pbItem
        }
        return nil
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard index == NSOutlineViewDropOnItemIndex, !(item is ResultNode) else { return [] }
        guard let targetFolder = item as? FolderNode,
              let pbItems = info.draggingPasteboard.pasteboardItems
        else { return .move }

        for pb in pbItems {
            guard let idStr = pb.string(forType: .folderNode),
                  let draggedId = Int64(idStr),
                  let draggedNode = vm.findFolder(draggedId)
            else { continue }

            if isDescendant(folder: targetFolder, of: draggedNode.id) {
                return []
            }
        }

        return .move
    }

    private func isDescendant(folder: FolderNode, of ancestorId: Int64) -> Bool {
        var current: FolderNode? = folder
        while let cur = current {
            if cur.id == ancestorId { return true }
            guard let parentId = vm.parentById[cur.id] ?? nil,
                  let nextParent = vm.findFolder(parentId)
            else {
                break
            }
            current = nextParent
        }
        return false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard let pbItem = info.draggingPasteboard.pasteboardItems?.first else { return false }
        let newParent = item as? FolderNode

        if let idStr = pbItem.string(forType: .folderNode), let draggedId = Int64(idStr) {
            return handleFolderDrop(draggedId: draggedId, newParent: newParent)
        }

        if let idStr = pbItem.string(forType: .resultNode), let resultId = Int64(idStr) {
            return handleResultDrop(resultId: resultId, newParentId: newParent?.id)
        }

        return false
    }

    private func handleFolderDrop(draggedId: Int64, newParent: FolderNode?) -> Bool {
        guard let draggedNode = vm.findFolder(draggedId) else { return false }
        do {
            try vm.moveNode(draggedNode: draggedNode, newParent: newParent)
            return true
        } catch {
            ReusableFunc.showAlert(
                title: Self.errorMovingFolderTitle,
                message: Self.errorMovingFolderDesc,
                style: .critical
            )
            return false
        }
    }

    private func handleResultDrop(resultId: Int64, newParentId: Int64?) -> Bool {
        do {
            try vm.moveResult(resultId, to: newParentId)
            return true
        } catch {
            ReusableFunc.showAlert(
                title: Self.errorMovingResultTitle,
                message: Self.errorMovingResultDesc,
                style: .critical
            )
            return false
        }
    }
}
