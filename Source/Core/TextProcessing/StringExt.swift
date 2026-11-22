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
            let val = scalar.value

            // 1. Fast-skip: Spasi dan kontrol ASCII standar
            if val == 0x20 || val == 0x09 || val == 0x0A || val == 0x0D {
                continue
            }

            // 2. Fast-skip: Simbol ASCII, tanda baca, dan angka (0-9, ., -, #)
            // Dalam Unicode Bidi Algorithm, ini karakter netral/weak (bukan strong character).
            if val < 0x0041 { // di bawah 'A'
                continue
            }

            // 3. Fast-path: Huruf Latin ASCII (A-Z, a-z) -> Pasti LTR
            if (0x0041 ... 0x005A).contains(val) || (0x0061 ... 0x007A).contains(val) {
                return false
            }

            // 4. Fast-path: Blok Arab, Ibrani, Syriak, dan Presentation Forms -> Pasti RTL
            if (0x0590 ... 0x08FF).contains(val) ||
                (0xFB1D ... 0xFDFF).contains(val) ||
                (0xFE70 ... 0xFEFF).contains(val) ||
                (0x10800 ... 0x1EFFF).contains(val)
            {
                return true
            }

            // 5. Fast-path: Latin Extended / Greek / Cyrillic (< 0x0590) -> Pasti LTR
            if val < 0x0590 {
                return false
            }

            // 6. Slow-path fallback: Hanya untuk aksara non-Latin/non-Arab langka
            if scalar.properties.isDefaultIgnorableCodePoint || scalar.properties.isWhitespace {
                continue
            }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                return false
            default:
                continue
            }
        }
        return true
    }
}

extension NSMutableAttributedString {
    /// Adjusts text alignment and writing direction line-by-line (paragraph-by-paragraph)
    /// based on the first strong letter of each paragraph.
    func applyAutoDirectionAlignments(
        font: PlatformFont? = nil,
        color: PlatformColor? = nil,
        lineBreakMode: NSLineBreakMode? = nil
    ) {
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
                let newStyle = existingStyle.mutableCopy() as? NSMutableParagraphStyle {
                    newStyle
                } else {
                    NSMutableParagraphStyle()
                }

            var needsStyleUpdate = currentStyle.alignment != targetAlignment || currentStyle.baseWritingDirection != targetDirection
            if needsStyleUpdate {
                currentStyle.alignment = targetAlignment
                currentStyle.baseWritingDirection = targetDirection
            }
            if let lineBreakMode, currentStyle.lineBreakMode != lineBreakMode {
                currentStyle.lineBreakMode = lineBreakMode
                needsStyleUpdate = true
            }

            if needsStyleUpdate {
                addAttribute(.paragraphStyle, value: currentStyle, range: paragraphRange)
            }

            if let font {
                addAttribute(.font, value: font, range: paragraphRange)
            }

            if let color {
                addAttribute(.foregroundColor, value: color, range: paragraphRange)
            }

            lineStart = NSMaxRange(paragraphRange)
        }
        endEditing()
    }
}

extension NSAttributedString {
    /// Builds an attributed string with per-paragraph RTL/LTR alignment and writing direction,
    /// reusing at most two paragraph style instances per call.
    static func autoDirectionString(
        _ text: String,
        font: PlatformFont,
        color: PlatformColor,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color]
        )
        let nsString = text as NSString
        guard nsString.length > 0 else { return result }

        var rtlStyle: NSParagraphStyle?
        var ltrStyle: NSParagraphStyle?

        result.beginEditing()
        var lineStart = 0
        while lineStart < nsString.length {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: lineStart, length: 0))
            let isRTL = nsString.substring(with: paragraphRange).isParagraphRTL

            let style: NSParagraphStyle
            if isRTL {
                if let cached = rtlStyle {
                    style = cached
                } else {
                    let created = NSMutableParagraphStyle()
                    created.alignment = .right
                    created.baseWritingDirection = .rightToLeft
                    created.lineBreakMode = lineBreakMode
                    rtlStyle = created
                    style = created
                }
            } else {
                if let cached = ltrStyle {
                    style = cached
                } else {
                    let created = NSMutableParagraphStyle()
                    created.alignment = .left
                    created.baseWritingDirection = .leftToRight
                    created.lineBreakMode = lineBreakMode
                    ltrStyle = created
                    style = created
                }
            }

            result.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            lineStart = NSMaxRange(paragraphRange)
        }
        result.endEditing()
        return result
    }
}

extension NSParagraphStyle {
    /// Resolves paragraph direction style for editor typing attributes at `location`,
    /// inheriting the previous paragraph direction when on a trailing empty newline.
    static func autoDirection(for text: String, at location: Int, fallbackRTL: Bool = true) -> NSParagraphStyle {
        let nsString = text as NSString
        let isRTL: Bool
        if nsString.length == 0 {
            isRTL = fallbackRTL
        } else {
            let clampedLocation = min(max(location, 0), nsString.length)
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: clampedLocation, length: 0))
            if paragraphRange.length == 0, clampedLocation > 0 {
                let prevRange = nsString.paragraphRange(for: NSRange(location: clampedLocation - 1, length: 0))
                isRTL = nsString.substring(with: prevRange).isParagraphRTL
            } else {
                isRTL = nsString.substring(with: paragraphRange).isParagraphRTL
            }
        }

        let style = NSMutableParagraphStyle()
        style.alignment = isRTL ? .right : .left
        style.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
        return style
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
        Bundle.main.localizedString(forKey: self, value: nil, table: nil)
    }

    /// Truncates long text safely at grapheme-cluster and newline boundaries before cell shaping/measurement.
    func truncatedForCellDisplay(maxCharacters: Int = 600, maxNewlines: Int = 8) -> String {
        guard maxCharacters > 0, maxNewlines > 0 else { return "" }
        var charCount = 0
        var newlineCount = 0
        var idx = startIndex
        while idx < endIndex {
            if charCount >= maxCharacters {
                return String(self[..<idx]) + "…"
            }
            if self[idx].isNewline {
                newlineCount += 1
                if newlineCount >= maxNewlines {
                    return String(self[..<idx]) + "…"
                }
            }
            idx = index(after: idx)
            charCount += 1
        }
        return self
    }
}
