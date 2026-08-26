//
//  AnnotationRTFExporter.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//

import Cocoa

@MainActor
enum AnnotationRTFExporter {
    static func rtfData(for nodes: [AnnotationNode], calendar: Calendar) -> Data? {
        let attr = buildAttributedString(nodes: nodes, calendar: calendar)
        do {
            return try attr.data(
                from: NSRange(location: 0, length: attr.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.rtf,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ]
            )
        } catch {
            return nil
        }
    }

    static func buildAttributedString(nodes: [AnnotationNode], calendar: Calendar) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraphStyle = defaultParagraphStyle()

        for node in nodes {
            if node.annotation == nil {
                result.append(buildHeaderString(for: node, paragraphStyle: paragraphStyle))
                if !node.children.isEmpty {
                    result.append(buildAttributedString(nodes: node.children, calendar: calendar))
                }
            } else if let annotation = node.annotation {
                result.append(buildAnnotationString(for: annotation, calendar: calendar, paragraphStyle: paragraphStyle))
            }
        }
        return result
    }

    private static func defaultParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        style.baseWritingDirection = .rightToLeft
        style.paragraphSpacingBefore = 4
        style.paragraphSpacing = 8
        return style
    }

    private static func buildHeaderString(for node: AnnotationNode, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        NSAttributedString(
            string: "\(node.title)\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 18),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    private static func buildAnnotationString(for annotation: Annotation, calendar: Calendar, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(buildContentString(for: annotation, paragraphStyle: paragraphStyle))
        result.append(buildMetadataString(for: annotation, calendar: calendar, paragraphStyle: paragraphStyle))
        result.append(NSAttributedString(string: "\n\n\n"))
        return result
    }

    private static func buildContentString(for annotation: Annotation, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let color = NSColor(hex: annotation.colorHex) ?? .yellow

        // Context
        let attrContext = NSMutableAttributedString(
            string: "\(annotation.context)\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .paragraphStyle: paragraphStyle,
            ]
        )
        let fullRg = NSRange(location: 0, length: attrContext.length)
        if annotation.type == .highlight {
            attrContext.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.3), range: fullRg)
        } else if annotation.type == .underline {
            attrContext.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRg)
            attrContext.addAttribute(.underlineColor, value: color, range: fullRg)
        }
        result.append(attrContext)

        // Note
        if let noteText = annotation.note {
            let attrNote = NSAttributedString(
                string: "\"\(noteText)\"\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraphStyle,
                ]
            )
            result.append(attrNote)
        }

        return result
    }

    private static func buildMetadataString(for annotation: Annotation, calendar: Calendar, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let targetDate = Date(timeIntervalSince1970: TimeInterval(annotation.createdAt))
        let dateString = calendar.isDateInToday(targetDate)
            ? RelativeDateTimeFormatter.shared.localizedString(for: targetDate, relativeTo: Date())
            : DateFormatter.mediumDateShortTime.string(from: targetDate)

        let kitab = LibraryDataManager.shared.getBook([annotation.bkId]).first?.book ?? "<Unknown Book>"
        let metaText = "\(kitab) • الجزء: \(annotation.partArb ?? "-") • الصفحة: \(annotation.pageArb ?? "-") \(annotation.tags.map { " -- \($0)" }.joined(separator: " "))\n\(dateString)\n"

        return NSAttributedString(
            string: metaText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }
}
