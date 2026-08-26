//
//  ResultsViewMenu.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 27/08/26.
//


import Cocoa

extension ResultsViewManager: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if menu == outlineView?.headerView?.menu {
            updateHeaderMenu(menu, outlineView: outlineView)
        } else if menu == outlineView?.menu {
            updateItemContextMenu(menu, outlineView: outlineView)
        }
    }

    private func updateHeaderMenu(_ menu: NSMenu, outlineView: NSOutlineView) {
        for column in outlineView.tableColumns {
            let title = columnMenuTitle(for: column)
            let menuItem = NSMenuItem(title: title, action: #selector(toggleColumnVisibility(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = column
            menuItem.state = column.isHidden ? .off : .on

            let isPrimaryColumn = column.identifier.rawValue == "AutomaticTableColumnIdentifier.0" || column == outlineView.outlineTableColumn
            menuItem.isEnabled = !isPrimaryColumn
            menu.addItem(menuItem)
        }
    }

    private func columnMenuTitle(for column: NSTableColumn) -> String {
        switch column.identifier.rawValue {
        case "AutomaticTableColumnIdentifier.0":
            "Title".localized
        case "query":
            "Query".localized
        case "modifiedDate":
            "Date Modified".localized
        default:
            column.title.isEmpty ? column.identifier.rawValue : column.title
        }
    }

    private func updateItemContextMenu(_ menu: NSMenu, outlineView: NSOutlineView) {
        let rows = outlineView.effectiveRows()
        let items = rows.compactMap { outlineView.item(atRow: $0) }
        guard !items.isEmpty else { return }

        func buildMenu(
            _ title: String, image: String, selector: Selector, representedObject: Any? = nil
        ) -> NSMenuItem {
            let menu: NSMenuItem = .init()
            menu.title = title.localized
            menu.target = self
            menu.action = selector
            menu.representedObject = representedObject
            menu.image = .init(systemSymbolName: image, accessibilityDescription: nil)
            return menu
        }

        menu.addItem(buildMenu(
            "Rename", image: "pencil", selector: #selector(renameSelectedItem(_:))
        ))

        menu.addItem(buildMenu(
            "Delete", image: "trash", selector: #selector(deleteSelectedItems(_:))
        ))

        if let result = items.first as? ResultNode {
            menu.addItem(.separator())
            menu.addItem(buildMenu(
                "Start Search", image: "play.fill",
                selector: #selector(startSearchSelectedItem(_:)), representedObject: result
            ))
        }
    }

    @objc private func startSearchSelectedItem(_ sender: NSMenuItem) {
        if let result = sender.representedObject as? ResultNode {
            delegate?.didSelect(savedResults: result.items)
            return
        }

        guard let firstRow = outlineView?.effectiveRows().first,
              let result = outlineView.item(atRow: firstRow) as? ResultNode
        else { return }

        delegate?.didSelect(savedResults: result.items)
    }

    @objc private func toggleColumnVisibility(_ sender: NSMenuItem) {
        guard let column = sender.representedObject as? NSTableColumn else { return }
        column.isHidden = !column.isHidden
    }

    @objc private func renameSelectedItem(_ sender: NSMenuItem) {
        guard let firstRow = outlineView?.effectiveRows().first, firstRow >= 0 else { return }
        outlineView.editColumn(0, row: firstRow, with: nil, select: true)
    }

    @objc private func deleteSelectedItems(_ sender: NSMenuItem) {
        guard let outlineView else { return }
        let items = outlineView.effectiveRows().compactMap { outlineView.item(atRow: $0) }

        for item in items {
            if let folder = item as? FolderNode {
                vm.deleteFolder(node: folder)
            } else if let result = item as? ResultNode {
                let parent = outlineView.parent(forItem: result) as? FolderNode
                vm.deleteResult(parent?.id, name: result.name)
            }
        }
    }
}
