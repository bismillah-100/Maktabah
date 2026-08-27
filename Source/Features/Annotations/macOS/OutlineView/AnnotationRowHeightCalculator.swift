//
//  AnnotationRowHeightCalculator.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//


import Cocoa

@MainActor
enum AnnotationRowHeightCalculator {
    static func height(for item: Any, in outlineView: NSOutlineView, groupingMode: AnnotationGroupingMode, paragraphStyle: NSParagraphStyle) -> CGFloat {
        guard let node = item as? AnnotationNode,
              let annotation = node.annotation
        else {
            return 30
        }

        let columnWidth = outlineView.outlineTableColumn?.width ?? outlineView.bounds.width
        let contentWidth = max(columnWidth - 40, 120)

        let contextHeight = measuredHeight(
            for: annotation.context,
            width: contentWidth * 0.72,
            font: ReusableFunc.bundledArabicFont(ofSize: 17),
            lineLimit: UserDefaults.standard.ctxMaxNumberOfLines,
            paragraphStyle: paragraphStyle
        )

        let noteHeight: CGFloat = if let note = annotation.note, !note.isEmpty {
            measuredHeight(
                for: note,
                width: contentWidth,
                font: NSFont.systemFont(ofSize: 15),
                lineLimit: UserDefaults.standard.annMaxNumberOfLines
            )
        } else {
            0
        }

        let page = "الجزء: \(annotation.partArb ?? "-") • الصفحة: \(annotation.pageArb ?? "-")"
        let tags = annotation.tags.map { " -- \($0)" }.joined(separator: " ")
        let pagePartText: String = switch groupingMode {
        case .book:
            page + tags
        case .tag:
            if let book = LibraryDataManager.shared.getBook([annotation.bkId]).first?.book {
                page + tags + "\n" + book
            } else {
                page + tags + "\n" + String(localized: .bookNotFound(bookID: annotation.bkId))
            }
        }

        let pagePartHeight = measuredHeight(
            for: pagePartText,
            width: contentWidth * 0.72,
            font: NSFont.systemFont(ofSize: 15),
            lineLimit: AnnotationCellView.pagePartLineLimit
        )

        let footnoteFont = NSFont.preferredFont(forTextStyle: .footnote)
        let dateHeight = ceil(footnoteFont.ascender - footnoteFont.descender + footnoteFont.leading)
        let topSectionHeight = max(contextHeight, dateHeight + 8)
        let stackSpacing: CGFloat = noteHeight > 0 ? 16 : 8

        return ceil(20 + topSectionHeight + pagePartHeight + noteHeight + stackSpacing)
    }

    static func measuredHeight(
        for text: String,
        width: CGFloat,
        font: NSFont,
        lineLimit: Int,
        paragraphStyle: NSParagraphStyle? = nil
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }

        let attributes: [NSAttributedString.Key: Any] = if let paragraphStyle {
            [.font: font, .paragraphStyle: paragraphStyle]
        } else {
            [.font: font]
        }

        let measuredRect = NSString(string: text).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let maxHeight = lineHeight * CGFloat(max(lineLimit, 1))

        return max(lineHeight, min(ceil(measuredRect.height), maxHeight))
    }
}