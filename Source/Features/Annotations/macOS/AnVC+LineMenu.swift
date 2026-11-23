//
//  AnVC+LineMenu.swift
//  Maktabah
//

import Cocoa

extension AnnotationsVC {
    func setupMaxLine() {
        for i in 1 ... 2 {
            let item = NSMenuItem(title: "\(i)", action: #selector(contextMenuAction(_:)), keyEquivalent: "")
            item.target = self
            // 'at' menentukan posisi index di dalam menu
            contextLineMenu.addItem(item)
        }
        for i in 1 ... 4 {
            let item = NSMenuItem(title: "\(i)", action: #selector(annotationMenuAction(_:)), keyEquivalent: "")
            item.target = self
            annotationLineMenu.addItem(item)
        }
        updateLineMenuState()
        setupDateSetting()
    }

    func setupDateSetting() {
        guard let menu = setting?.menu else { return }
        if menu.items.contains(where: { $0.action == #selector(toggleShowDateAction(_:)) }) {
            updateDateMenuState()
            return
        }

        let showDateItem = NSMenuItem(
            title: String(localized: .Annotation.showDate),
            action: #selector(toggleShowDateAction(_:)),
            keyEquivalent: ""
        )
        showDateItem.target = self

        let lineLimitsIndex = menu.items.firstIndex { item in
            item.submenu === annotationLineMenu?.supermenu ||
                item.submenu === contextLineMenu?.supermenu ||
                item.title == "Line Limits" ||
                item.submenu?.items.contains(where: { $0.submenu === annotationLineMenu }) == true
        }

        if let lineLimitsIndex {
            menu.insertItem(showDateItem, at: lineLimitsIndex + 1)
        } else if let reloadIndex = menu.items.firstIndex(where: { $0.action == #selector(reloadAnnotations(_:)) }) {
            menu.insertItem(showDateItem, at: reloadIndex)
        } else {
            menu.addItem(showDateItem)
        }
        updateDateMenuState()
    }

    func updateDateMenuState() {
        guard let menu = setting?.menu else { return }
        if let item = menu.items.first(where: { $0.action == #selector(toggleShowDateAction(_:)) }) {
            item.state = defaults.showAnnotationDate ? .on : .off
        }
    }

    @objc func toggleShowDateAction(_ sender: NSMenuItem) {
        defaults.showAnnotationDate.toggle()
        sender.state = defaults.showAnnotationDate ? .on : .off
        dataSource.showDate = defaults.showAnnotationDate
        refreshAnnotationRowHeights()
    }

    func updateLineMenuState() {
        for item in contextLineMenu.items {
            item.state = item.title == "\(defaults.ctxMaxNumberOfLines)" ? .on : .off
        }
        for item in annotationLineMenu.items {
            item.state = item.title == "\(defaults.annMaxNumberOfLines)" ? .on : .off
        }
    }

    func refreshAnnotationRowHeights() {
        outlineView.reloadData()
        guard outlineView.numberOfRows > 0 else { return }
        outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0 ..< outlineView.numberOfRows))
    }

    @objc func contextMenuAction(_ sender: NSMenuItem) {
        guard let lineLimit = Int(sender.title) else { return }
        defaults.ctxMaxNumberOfLines = lineLimit
        updateLineMenuState()
        refreshAnnotationRowHeights()
    }

    @objc func annotationMenuAction(_ sender: NSMenuItem) {
        guard let lineLimit = Int(sender.title) else { return }
        defaults.annMaxNumberOfLines = lineLimit
        updateLineMenuState()
        refreshAnnotationRowHeights()
    }
}
