//
//  ArabicTextRenderer.swift
//  Maktabah
//
//  Created by MacBook on 27/01/26.
//

import Foundation
import Cocoa

// ArabicTextRenderer.swift - NEW FILE
class ArabicTextRenderer {
    private let state = TextViewState.shared

    func render(
        text: String,
        highlightColor: NSColor = .header,
        showHarakat: Bool
    ) -> NSAttributedString {
        let processedText = showHarakat ? text : text.removingHarakat()
        let result = processedText.cleanedTextWithRanges()
        return createAttributedString(from: result, color: highlightColor)
    }

    func applyAnnotations(
        _ annotations: [Annotation],
        to textStorage: NSTextStorage,
        showHarakat: Bool
    ) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        for ann in annotations {
            let range = showHarakat ? ann.rangeDiacritics : ann.range
            guard range.location + range.length <= textStorage.length else { continue }

            applyAnnotation(ann, at: range, to: textStorage)
        }
    }

    func updateLineHeight(in textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        textStorage.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let oldStyle = (value as? NSParagraphStyle) ?? state.paragraphStyle
            let newStyle = oldStyle.mutableCopy() as! NSMutableParagraphStyle
            newStyle.lineHeightMultiple = state.lineHeight

            textStorage.addAttribute(.paragraphStyle, value: newStyle, range: range)
        }
    }

    private func createAttributedString(from result: CleanedTextResult, color: NSColor) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(
            string: result.text,
            attributes: state.defaultAttributes
        )

        let highlightAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color
        ]

        for range in result.coloredRanges {
            if range.location + range.length <= attributedString.length {
                attributedString.addAttributes(highlightAttributes, range: range)
            }
        }

        return attributedString
    }

    private func applyAnnotation(_ ann: Annotation, at range: NSRange, to textStorage: NSTextStorage) {
        if ann.type == .highlight {
            let color = NSColor(hex: ann.colorHex) ?? .yellow
            textStorage.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.6), range: range)
            textStorage.removeAttribute(.underlineStyle, range: range)
        } else if ann.type == .underline {
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            textStorage.removeAttribute(.backgroundColor, range: range)
        }

        if let id = ann.id {
            if state.clickableAnnotation {
                let linkURL = "\(id)"
                textStorage.addAttribute(.link, value: linkURL, range: range)
            }
            textStorage.addAttribute(NSAttributedString.Key("annotationID"), value: id, range: range)
        }
    }
}
