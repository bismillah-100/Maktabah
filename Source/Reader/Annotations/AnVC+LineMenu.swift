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
