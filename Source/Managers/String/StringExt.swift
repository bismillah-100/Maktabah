//
//  StringExt.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension StringProtocol {
    /// Checks the first strong letter of the text/paragraph to determine if it is RTL (Arabic, Hebrew, etc.).
    /// Returns `true` if RTL or empty/neutral, and `false` if LTR.
    var isParagraphRTL: Bool {
        for scalar in unicodeScalars {
            if scalar.properties.isDefaultIgnorableCodePoint || scalar.properties.isWhitespace {
                continue
            }
            let category = scalar.properties.generalCategory
            switch category {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                let val = scalar.value
                if (0x0590 ... 0x08FF).contains(val) ||
                    (0xFB1D ... 0xFDFF).contains(val) ||
                    (0xFE70 ... 0xFEFF).contains(val) ||
                    (0x10800 ... 0x1EFFF).contains(val)
                {
                    return true
                } else {
                    return false
                }
            default:
                continue
            }
        }
        return true
    }
}

extension NSTextStorage {
    /// Adjusts text alignment and writing direction line-by-line (paragraph-by-paragraph)
    /// based on the first strong letter of each paragraph.
    func applyAutoDirectionAlignments(font: PlatformFont? = nil) {
        let nsString = string as NSString
        guard nsString.length > 0 else { return }

        beginEditing()
        var lineStart = 0
        while lineStart < nsString.length {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: lineStart, length: 0))
            let paragraphText = nsString.substring(with: paragraphRange)

            let isRTL = paragraphText.isParagraphRTL
            let targetAlignment: NSTextAlignment = isRTL ? .right : .left
            let targetDirection: NSWritingDirection = isRTL ? .rightToLeft : .leftToRight

            let currentStyle: NSMutableParagraphStyle =
            if let existingStyle = attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle,
               let newStyle = existingStyle.mutableCopy() as? NSMutableParagraphStyle
            {
                newStyle
            } else {
                NSMutableParagraphStyle()
            }

            if currentStyle.alignment != targetAlignment || currentStyle.baseWritingDirection != targetDirection {
                currentStyle.alignment = targetAlignment
                currentStyle.baseWritingDirection = targetDirection
                addAttribute(.paragraphStyle, value: currentStyle, range: paragraphRange)
            }

            if let font {
                addAttribute(.font, value: font, range: paragraphRange)
            }

            lineStart = NSMaxRange(paragraphRange)
        }
        endEditing()
    }
}

#if os(macOS)
extension NSTextField {
    /// Adjusts field alignment and writing direction based on stringValue's first strong character.
    func updateAutoDirectionAlignment() {
        let isRTL = stringValue.isParagraphRTL
        alignment = isRTL ? .right : .left
        baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
    }
}
#endif

extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
}
