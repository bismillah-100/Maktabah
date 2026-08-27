//
//  AnnotationsOutlineDelegate.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//


import Cocoa

extension AnnotationOutlineDataSource: NSOutlineViewDelegate, NSTableViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? AnnotationNode else { return nil }

        if node.annotation == nil {
            let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("BooksCell"), owner: self) as? NSTableCellView
            cell?.textField?.stringValue = node.title
            return cell
        }

        guard let annotation = node.annotation,
              let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("AnnotationCell"), owner: self) as? AnnotationCellView
        else {
            return nil
        }

        configureAnnotationCell(cell, for: annotation)
        return cell
    }

    private func configureAnnotationCell(_ cell: AnnotationCellView, for annotation: Annotation) {
        let color = NSColor(hex: annotation.colorHex) ?? .yellow
        cell.pagePart.stringValue = buildPageAndTagsString(for: annotation)
        cell.applyLineLimits()
        cell.context.attributedStringValue = makeContextAttributedString(for: annotation, color: color)

        if let note = annotation.note {
            cell.note.isHidden = false
            cell.note.stringValue = note
        } else {
            cell.note.isHidden = true
        }

        cell.date.stringValue = formatAnnotationDate(annotation.createdAt)
    }

    private func makeContextAttributedString(for annotation: Annotation, color: NSColor) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: annotation.context)
        let fullRg = NSRange(location: 0, length: attributedString.length)

        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRg)
        attributedString.addAttribute(.font, value: ReusableFunc.bundledArabicFont(ofSize: 17), range: fullRg)

        switch annotation.type {
        case .highlight:
            attributedString.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.3), range: fullRg)
        case .underline:
            attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRg)
        }
        return attributedString
    }

    private func buildPageAndTagsString(for annotation: Annotation) -> String {
        let page = "الجزء: \(annotation.partArb ?? "-") • الصفحة: \(annotation.pageArb ?? "-")"
        let tags = annotation.tags.map { " -- \($0)" }.joined(separator: " ")

        switch groupingMode {
        case .book:
            return page + tags
        case .tag:
            let bookTitle = LibraryDataManager.shared.getBook([annotation.bkId]).first?.book ?? String(localized: .bookNotFound(bookID: annotation.bkId))
            return page + tags + "\n" + bookTitle
        }
    }

    private func formatAnnotationDate(_ timestampInt64: Int64) -> String {
        let targetDate = Date(timeIntervalSince1970: TimeInterval(timestampInt64))
        if calendar.isDateInToday(targetDate) {
            return RelativeDateTimeFormatter.shared.localizedString(for: targetDate, relativeTo: Date())
        }
        return DateFormatter.mediumDateShortTime.string(from: targetDate)
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        AnnotationRowHeightCalculator.height(for: item, in: outlineView, groupingMode: groupingMode, paragraphStyle: paragraphStyle)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else { return }

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

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard edge == .trailing else { return [] }

        let deleteAction = NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self] _, _ in
            guard let self else { return }
            deleteMenuItem.representedObject = row
            deleteItem(deleteMenuItem)
        }

        if let baseImage = NSImage(systemSymbolName: "trash.slash.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular, scale: .large)
            deleteAction.image = baseImage.withSymbolConfiguration(config)
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
