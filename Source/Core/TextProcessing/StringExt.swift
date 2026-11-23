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

enum AutoDirectionStyleCache {
    nonisolated(unsafe) static let rtlWordWrapping: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        style.baseWritingDirection = .rightToLeft
        style.lineBreakMode = .byWordWrapping
        return style
    }()

    nonisolated(unsafe) static let ltrWordWrapping: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.baseWritingDirection = .leftToRight
        style.lineBreakMode = .byWordWrapping
        return style
    }()

    nonisolated(unsafe) static let rtlTruncatingTail: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        style.baseWritingDirection = .rightToLeft
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    nonisolated(unsafe) static let ltrTruncatingTail: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.baseWritingDirection = .leftToRight
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    @inline(__always)
    static func style(isRTL: Bool, lineBreakMode: NSLineBreakMode) -> NSParagraphStyle {
        switch lineBreakMode {
        case .byTruncatingTail:
            return isRTL ? rtlTruncatingTail : ltrTruncatingTail
        case .byWordWrapping:
            return isRTL ? rtlWordWrapping : ltrWordWrapping
        default:
            let style = NSMutableParagraphStyle()
            style.alignment = isRTL ? .right : .left
            style.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
            style.lineBreakMode = lineBreakMode
            return style
        }
    }
}

extension NSAttributedString {
    /// Builds an attributed string with per-paragraph RTL/LTR alignment and writing direction,
    /// reusing cached paragraph style instances to achieve nanosecond performance.
    static func autoDirectionString(
        _ text: String,
        font: PlatformFont,
        color: PlatformColor,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) -> NSAttributedString {
        guard !text.isEmpty else {
            return NSAttributedString(string: "", attributes: [.font: font, .foregroundColor: color])
        }

        // Fast-path: single paragraph (no newline)
        if !text.contains(where: { $0 == "\n" || $0 == "\r" }) {
            let isRTL = text.isParagraphRTL
            let style = AutoDirectionStyleCache.style(isRTL: isRTL, lineBreakMode: lineBreakMode)
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: style
                ]
            )
        }

        return buildMultiParagraphAutoDirectionString(text, font: font, color: color, lineBreakMode: lineBreakMode)
    }

    private static func buildMultiParagraphAutoDirectionString(
        _ text: String,
        font: PlatformFont,
        color: PlatformColor,
        lineBreakMode: NSLineBreakMode
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
            let isRTL = if let swiftRange = Range(paragraphRange, in: text) {
                text[swiftRange].isParagraphRTL
            } else {
                nsString.substring(with: paragraphRange).isParagraphRTL
            }

            let style = resolveParagraphStyle(isRTL: isRTL, lineBreakMode: lineBreakMode, cachedRTL: &rtlStyle, cachedLTR: &ltrStyle)
            result.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            lineStart = NSMaxRange(paragraphRange)
        }
        result.endEditing()
        return result
    }

    private static func resolveParagraphStyle(
        isRTL: Bool,
        lineBreakMode: NSLineBreakMode,
        cachedRTL: inout NSParagraphStyle?,
        cachedLTR: inout NSParagraphStyle?
    ) -> NSParagraphStyle {
        if isRTL {
            if let cached = cachedRTL { return cached }
            let style = AutoDirectionStyleCache.style(isRTL: true, lineBreakMode: lineBreakMode)
            cachedRTL = style
            return style
        } else {
            if let cached = cachedLTR { return cached }
            let style = AutoDirectionStyleCache.style(isRTL: false, lineBreakMode: lineBreakMode)
            cachedLTR = style
            return style
        }
    }

    /// Optimized context attributed string builder with per-paragraph auto RTL/LTR direction
    /// and annotation highlight or underline attributes. Single-paragraph texts are constructed in one pass.
    static func autoDirectionContextString(
        _ text: String,
        font: PlatformFont,
        mode: AnnotationMode,
        effectiveColor: PlatformColor,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) -> NSAttributedString {
        #if canImport(AppKit)
        let textColor = PlatformColor.labelColor
        let highlightAlpha: CGFloat = 0.5
        #else
        let textColor = PlatformColor.label
        let highlightAlpha: CGFloat = 0.3
        #endif

        guard !text.isEmpty else {
            return NSAttributedString(string: "", attributes: [.font: font, .foregroundColor: textColor])
        }

        // Single paragraph fast-path (95%+ of annotation contexts)
        if !text.contains(where: { $0 == "\n" || $0 == "\r" }) {
            let isRTL = text.isParagraphRTL
            let style = AutoDirectionStyleCache.style(isRTL: isRTL, lineBreakMode: lineBreakMode)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: style
            ]
            switch mode {
            case .highlight:
                attributes[.backgroundColor] = effectiveColor.withAlphaComponent(highlightAlpha)
            case .underline:
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.underlineColor] = effectiveColor
            }
            return NSAttributedString(string: text, attributes: attributes)
        }

        let base = autoDirectionString(text, font: font, color: textColor, lineBreakMode: lineBreakMode)
        let mutable = NSMutableAttributedString(attributedString: base)
        let fullRg = NSRange(location: 0, length: mutable.length)
        switch mode {
        case .highlight:
            mutable.addAttribute(.backgroundColor, value: effectiveColor.withAlphaComponent(highlightAlpha), range: fullRg)
        case .underline:
            mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRg)
            mutable.addAttribute(.underlineColor, value: effectiveColor, range: fullRg)
        }
        return mutable
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
