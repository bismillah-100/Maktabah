//
//  AnnotationsOutlineDelegate.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//

import Cocoa
import OSLog

extension AnnotationOutlineDataSource: NSOutlineViewDelegate, NSTableViewDelegate {
    private enum CellIdentifier {
        static let timelineGroup = NSUserInterfaceItemIdentifier("TimelineGroupCell")
        static let books = NSUserInterfaceItemIdentifier("BooksCell")
        static let annotation = NSUserInterfaceItemIdentifier("AnnotationCell")
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        groupingMode == .timeline && (item as? AnnotationNode)?.kind == .dateBucket
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        groupingMode != .timeline
    }

    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        groupingMode != .timeline
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

        if let note = annotation.note, !note.isEmpty {
            cell.note.isHidden = false
            cell.note.attributedStringValue = makeNoteAttributedString(for: note)
        } else {
            cell.note.isHidden = true
        }

        cell.date.stringValue = formatAnnotationDate(annotation.createdAt)
        cell.setTimelineInset(groupingMode == .timeline)
    }

    private func makeContextAttributedString(for annotation: Annotation, color: NSColor) -> NSAttributedString {
        let displayContext = AnnotationRowHeightCalculator.displayContext(annotation.context)
        let effectiveColor = annotation.type == .underline
            ? NSColor.effectiveAnnotationColor(hex: annotation.colorHex, isUnderline: true)
            : color

        return NSAttributedString.autoDirectionContextString(
            displayContext,
            font: ReusableFunc.bundledArabicFont(ofSize: 17),
            mode: annotation.type,
            effectiveColor: effectiveColor,
            lineBreakMode: .byWordWrapping
        )
    }

    private func makeNoteAttributedString(for note: String) -> NSAttributedString {
        let displayNote = AnnotationRowHeightCalculator.displayNote(note)
        return NSAttributedString.autoDirectionString(
            displayNote,
            font: ReusableFunc.bundledArabicFont(ofSize: 15),
            color: .labelColor,
            lineBreakMode: .byWordWrapping
        )
    }

    private func buildPageAndTagsString(for annotation: Annotation) -> String {
        AnnotationRowHeightCalculator.pageAndTagsText(for: annotation, groupingMode: groupingMode)
    }

    private func formatAnnotationDate(_ timestampInt64: Int64) -> String {
        AnnotationRowHeightCalculator.formatDate(timestampInt64)
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        AnnotationRowHeightCalculator.height(for: item, in: outlineView, groupingMode: groupingMode, paragraphStyle: paragraphStyle)
    }

    func outlineViewColumnDidResize(_ notification: Notification) {
        guard let outlineView else { return }
        let range = outlineView.rows(in: outlineView.visibleRect)
        guard range.location != NSNotFound, range.length > 0 else { return }
        outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: range.location ..< range.location + range.length))
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else { return }

        let row = outlineView.selectedRow
        onSelectItem?(row)

        guard outlineView.selectedRowIndexes.count == 1,
              let item = outlineView.item(atRow: row) as? AnnotationNode,
              let annotation = item.annotation
        else {
            Logger.annotations.debug("outlineView item not as Annotations")
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
