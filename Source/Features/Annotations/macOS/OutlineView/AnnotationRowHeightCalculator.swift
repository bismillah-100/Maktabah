//
//  AnnotationRowHeightCalculator.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//

import Cocoa

@MainActor
enum AnnotationRowHeightCalculator {
    static func height(
        for item: Any,
        in outlineView: NSOutlineView,
        groupingMode: AnnotationGroupingMode,
        paragraphStyle: NSParagraphStyle,
        showDate: Bool = UserDefaults.standard.showAnnotationDate
    ) -> CGFloat {
        guard let node = item as? AnnotationNode,
              let annotation = node.annotation
        else {
            return 30
        }

        let columnWidth = outlineView.outlineTableColumn?.width ?? outlineView.bounds.width
        let horizontalInset: CGFloat = groupingMode == .timeline ? 16 : 26
        let contentWidth = max(columnWidth - horizontalInset, 100)

        let contextWidth: CGFloat
        if showDate {
            let footnoteFont = NSFont.preferredFont(forTextStyle: .footnote)
            let dateText = formatDate(annotation.createdAt)
            let dateWidth = ceil(NSString(string: dateText).size(withAttributes: [.font: footnoteFont]).width)
            let dateOccupiedWidth = dateWidth + 12
            contextWidth = max(contentWidth - dateOccupiedWidth, 60)
        } else {
            contextWidth = max(contentWidth, 60)
        }

        let displayContext = Self.displayContext(annotation.context)
        let contextHeight = measuredHeight(
            for: displayContext,
            width: contextWidth,
            font: ReusableFunc.bundledArabicFont(ofSize: 17),
            lineLimit: UserDefaults.standard.ctxMaxNumberOfLines,
            paragraphStyle: paragraphStyle
        )

        let noteHeight: CGFloat = if let note = annotation.note, !note.isEmpty {
            measuredHeight(
                for: Self.displayNote(note),
                width: contentWidth,
                font: ReusableFunc.bundledArabicFont(ofSize: 15),
                lineLimit: UserDefaults.standard.annMaxNumberOfLines
            )
        } else {
            0
        }

        let pagePartText = pageAndTagsText(for: annotation, groupingMode: groupingMode)
        let pagePartHeight = measuredHeight(
            for: pagePartText,
            width: contentWidth,
            font: ReusableFunc.bundledArabicFont(ofSize: 15),
            lineLimit: AnnotationCellView.pagePartLineLimit
        )

        let topSectionHeight = showDate ? max(contextHeight, 26) : max(contextHeight, 20)
        let stackSpacing: CGFloat = noteHeight > 0 ? 16 : 8

        return ceil(23 + topSectionHeight + pagePartHeight + noteHeight + stackSpacing)
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

    static func displayContext(_ text: String) -> String {
        text.truncatedForCellDisplay(maxCharacters: 350, maxNewlines: 2)
    }

    static func displayNote(_ text: String) -> String {
        text.truncatedForCellDisplay(maxCharacters: 500, maxNewlines: 4)
    }

    static func formatDate(_ timestampInt64: Int64) -> String {
        let targetDate = Date(timeIntervalSince1970: TimeInterval(timestampInt64))
        if Calendar.current.isDateInToday(targetDate) {
            return RelativeDateTimeFormatter.shared.localizedString(for: targetDate, relativeTo: Date())
        }
        return DateFormatter.mediumDateShortTime.string(from: targetDate)
    }

    static func pageAndTagsText(for annotation: Annotation, groupingMode: AnnotationGroupingMode) -> String {
        let page = "الجزء: \(annotation.partArb ?? "-") • الصفحة: \(annotation.pageArb ?? "-")"
        let tags = annotation.tags.map { " -- \($0)" }.joined(separator: " ")
        switch groupingMode {
        case .book:
            return page + tags
        case .tag, .timeline:
            let bookTitle = LibraryDataManager.shared.booksById[annotation.bkId]?.book ?? String(localized: .Library.bookNotFound(annotation.bkId))
            return page + tags + "\n" + bookTitle
        }
    }
}
