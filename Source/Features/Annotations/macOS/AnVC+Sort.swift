//
//  AnVC+Sort.swift
//  Maktabah
//

import Cocoa

extension AnnotationsVC {
    func setupSortMenu() {
        guard let menu = sortingButton.menu else { return }

        let fields: [(String, Int)] = [
            ("Context".localized, SortMenuTag.fieldContext),
            ("Date Created".localized, SortMenuTag.fieldCreatedAt),
            ("Page".localized, SortMenuTag.fieldPage),
            ("Part".localized, SortMenuTag.fieldPart),
        ]
        for (title, tag) in fields {
            let item = NSMenuItem(title: title, action: #selector(selectSortField(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let orders: [(String, Int)] = [
            ("Ascending".localized, SortMenuTag.ascending),
            ("Descending".localized, SortMenuTag.descending),
        ]
        for (title, tag) in orders {
            let item = NSMenuItem(title: title, action: #selector(selectSortOrder(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let groupingItems: [(String, Int)] = [
            ("Group by Book".localized, SortMenuTag.groupingBook),
            ("Group by Tag".localized, SortMenuTag.groupingTag),
        ]
        for (title, tag) in groupingItems {
            let item = NSMenuItem(title: title, action: #selector(selectGroupingMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            menu.addItem(item)
        }

        sortingButton.image = NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: "Sort")
        sortingButton.title = ""
        updateSortMenuState()
    }

    @objc func selectSortField(_ sender: NSMenuItem) {
        selectedSortField = switch sender.tag {
        case SortMenuTag.fieldCreatedAt: .createdAt
        case SortMenuTag.fieldContext: .context
        case SortMenuTag.fieldPage: .page
        case SortMenuTag.fieldPart: .part
        default: .createdAt
        }
        applySorting()
    }

    @objc func selectSortOrder(_ sender: NSMenuItem) {
        selectedSortAscending = sender.tag == SortMenuTag.ascending
        applySorting()
    }

    @objc func selectGroupingMode(_ sender: NSMenuItem) {
        switch sender.tag {
        case SortMenuTag.groupingBook: selectedGroupingMode = .book
        case SortMenuTag.groupingTag: selectedGroupingMode = .tag
        default: return
        }
        dataSource.updateGrouping(mode: selectedGroupingMode)
        if !searchField.stringValue.isEmpty {
            outlineView.expandItem(nil, expandChildren: true)
        }
        updateSortMenuState()
    }

    func applySorting() {
        dataSource.updateSorting(field: selectedSortField, isAscending: selectedSortAscending)
        if !searchField.stringValue.isEmpty {
            outlineView.expandItem(nil, expandChildren: true)
        }
        updateSortMenuState()
    }

    func updateSortMenuState() {
        guard let menu = sortingButton.menu else { return }
        menu.items.forEach { $0.state = .off }
        menu.item(withTag: selectedSortAscending ? SortMenuTag.ascending : SortMenuTag.descending)?.state = .on
        menu.item(withTag: selectedGroupingMode == .book ? SortMenuTag.groupingBook : SortMenuTag.groupingTag)?.state = .on
        let fieldTag: Int = switch selectedSortField {
        case .createdAt: SortMenuTag.fieldCreatedAt
        case .context: SortMenuTag.fieldContext
        case .page: SortMenuTag.fieldPage
        case .part: SortMenuTag.fieldPart
        }
        menu.item(withTag: fieldTag)?.state = .on
    }
}
