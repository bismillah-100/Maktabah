//
//  ResultsViewTextField.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 27/08/26.
//


import Cocoa

extension ResultsViewManager: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let outlineView,
              let textField = obj.object as? NSTextField,
              let cell = textField.superview as? NSTableCellView
        else { return }

        let row = outlineView.row(for: cell)
        let item = outlineView.item(atRow: row)

        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            outlineView.reloadItem(item)
            return
        }

        if let folderNode = item as? FolderNode {
            renameFolderNode(folderNode, to: newName)
        } else if let resultNode = item as? ResultNode {
            renameResultNode(resultNode, to: newName)
        }
    }

    private func renameFolderNode(_ folderNode: FolderNode, to newName: String) {
        guard folderNode.name != newName else { return }
        do {
            try vm.updateFolderName(id: folderNode.id, newName: newName)
        } catch {
            showRenameError()
            outlineView.reloadItem(folderNode)
            #if DEBUG
            print(error)
            #endif
        }
    }

    private func renameResultNode(_ resultNode: ResultNode, to newName: String) {
        guard resultNode.name != newName else { return }
        do {
            try vm.updateResultQueryName(id: resultNode.id, newName: newName)
        } catch {
            showRenameError()
            outlineView.reloadItem(resultNode)
            #if DEBUG
            print(error)
            #endif
        }
    }

    private func showRenameError() {
        ReusableFunc.showAlert(
            title: Self.renameFolderErrorTitle,
            message: Self.renameFolderOrResultErrorDesc,
            style: .critical
        )
    }
}
