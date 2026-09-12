//
//  AnnotationsOutlineDelegate.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//

import Cocoa

extension AnnotationOutlineDataSource: NSOutlineViewDelegate, NSTableViewDelegate {
    private enum CellIdentifier {
        static let timelineGroup = NSUserInterfaceItemIdentifier("TimelineGroupCell")
        static let books = NSUserInterfaceItemIdentifier("BooksCell")
        static let annotation = NSUserInterfaceItemIdentifier("AnnotationCell")
    }

    private func isTimelineDateBucket(_ item: Any) -> Bool {
        groupingMode == .timeline && (item as? AnnotationNode)?.kind == .dateBucket
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        isTimelineDateBucket(item)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        !isTimelineDateBucket(item)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        !isTimelineDateBucket(item)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? AnnotationNode)?.annotation != nil
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? AnnotationNode else { return nil }

        if node.annotation == nil {
            if groupingMode == .timeline, node.kind == .dateBucket {
                var cell = outlineView.makeView(withIdentifier: CellIdentifier.timelineGroup, owner: self) as? TimelineGroupCellView
                if cell == nil {
                    cell = TimelineGroupCellView()
                    cell?.identifier = CellIdentifier.timelineGroup
                }
                cell?.configure(title: node.title)
                return cell
            }

            let cell = outlineView.makeView(withIdentifier: CellIdentifier.books, owner: self) as? NSTableCellView
            cell?.textField?.stringValue = node.title
            return cell
        }

        guard let annotation = node.annotation else { return nil }

        let cell = (outlineView.makeView(withIdentifier: CellIdentifier.annotation, owner: self) as? AnnotationCellView) ?? {
            let columnWidth = outlineView.outlineTableColumn?.width ?? outlineView.bounds.width
            let newCell = AnnotationCellView(frame: NSRect(x: 0, y: 0, width: max(columnWidth, 300), height: 124))
            newCell.identifier = CellIdentifier.annotation
            return newCell
        }()

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
        cell.setTimelineInset(groupingMode == .timeline)
    }

    private func makeContextAttributedString(for annotation: Annotation, color: NSColor) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: annotation.context)
        let fullRg = NSRange(location: 0, length: attributedString.length)

        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRg)
        attributedString.addAttribute(.font, value: ReusableFunc.bundledArabicFont(ofSize: 17), range: fullRg)

        switch annotation.type {
        case .highlight:
            attributedString.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.5), range: fullRg)
        case .underline:
            attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRg)
        }
        return attributedString
    }

    private func buildPageAndTagsString(for annotation: Annotation) -> String {
        AnnotationRowHeightCalculator.pageAndTagsText(for: annotation, groupingMode: groupingMode)
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
           node.kind == AnnotationNodeKind.tag || node.kind == AnnotationNodeKind.untagged || node.kind == AnnotationNodeKind.dateBucket
        {
            return []
        }

        return [deleteAction]
    }
}
