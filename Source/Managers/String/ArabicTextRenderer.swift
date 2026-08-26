//
//  ArabicTextRenderer.swift
//  Maktabah
//
//  Created by MacBook on 27/01/26.
//

import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ArabicRenderResult {
    let sourceText: String
    let attributedString: NSAttributedString
    let replacementEvents: [HonorificReplacementEvent]
    let footnoteRanges: [NSRange]

    func remapDisplayedRange(_ range: NSRange) -> NSRange {
        guard !replacementEvents.isEmpty else { return range }

        let start = displayedOffset(forSourceOffset: range.location, affinity: .leading)
        let end = displayedOffset(forSourceOffset: range.location + range.length, affinity: .trailing)
        return NSRange(location: start, length: max(0, end - start))
    }

    func remapSourceRange(_ range: NSRange) -> NSRange {
        guard !replacementEvents.isEmpty else { return range }

        let start = sourceOffset(forDisplayedOffset: range.location, affinity: .leading)
        let end = sourceOffset(forDisplayedOffset: range.location + range.length, affinity: .trailing)
        return NSRange(location: start, length: max(0, end - start))
    }

    func displayedOffset(forSourceOffset oldOffset: Int, affinity: HonorificBoundaryAffinity) -> Int {
        var delta = 0

        for event in replacementEvents {
            let start = event.oldRange.location
            let end = event.oldRange.location + event.oldRange.length

            if oldOffset < start {
                break
            }

            if oldOffset == start {
                return start + delta
            }

            if oldOffset < end {
                return start + delta + (affinity == .trailing ? event.newLength : 0)
            }

            delta += event.newLength - event.oldRange.length
        }

        return oldOffset + delta
    }

    func sourceOffset(forDisplayedOffset displayedOffset: Int, affinity: HonorificBoundaryAffinity) -> Int {
        var delta = 0

        for event in replacementEvents {
            let oldStart = event.oldRange.location
            let oldEnd = event.oldRange.location + event.oldRange.length
            let newStart = oldStart + delta
            let newEnd = newStart + event.newLength

            if displayedOffset < newStart {
                break
            }

            if displayedOffset == newStart {
                return oldStart
            }

            if displayedOffset < newEnd {
                return affinity == .trailing ? oldEnd : oldStart
            }

            delta += event.newLength - event.oldRange.length
        }

        return displayedOffset - delta
    }
}

struct HonorificReplacementEvent {
    let oldRange: NSRange
    let newLength: Int
}

enum HonorificBoundaryAffinity {
    case leading
    case trailing
}

/// ArabicTextRenderer.swift - NEW FILE
class ArabicTextRenderer {
    private let state = TextViewState.shared

    func render(
        bookId: Int? = nil,
        contentId: Int? = nil,
        text: String,
        highlightColor: PlatformColor = .header,
        showHarakat: Bool,
        isMultiLanguage: Bool = false,
        isImported: Bool = false
    ) -> ArabicRenderResult {
        let key = CleanedTextKey(
            showHarakat: showHarakat,
            isMultiLanguage: isMultiLanguage,
            isImported: isImported
        )

        let processed: ProcessedArabicContent
        if let bookId, let contentId, let cached = BookPageCache.shared.getProcessed(bookId: bookId, contentId: contentId, key: key) {
            processed = cached
        } else {
            processed = buildProcessedArabicContent(
                text: text,
                showHarakat: showHarakat,
                isMultiLanguage: isMultiLanguage,
                isImported: isImported
            )

            if let bookId, let contentId {
                BookPageCache.shared.setProcessed(bookId: bookId, contentId: contentId, key: key, content: processed)
            }
        }

        let attributedString = createAttributedString(
            from: processed,
            color: highlightColor,
            isMultiLanguage: isMultiLanguage
        )

        return ArabicRenderResult(
            sourceText: processed.sourceText,
            attributedString: attributedString,
            replacementEvents: processed.replacementEvents,
            footnoteRanges: processed.footnoteRanges
        )
    }

    private func buildProcessedArabicContent(
        text: String,
        showHarakat: Bool,
        isMultiLanguage: Bool,
        isImported: Bool
    ) -> ProcessedArabicContent {
        let textWithArabicDigits = text.convertToArabicDigits(isMultilingual: isMultiLanguage)
        let processedText = showHarakat ? textWithArabicDigits : textWithArabicDigits.removingHarakat()

        let (cleanedText, importedHeaderRanges) = isImported
            ? processedText.stripSpanTagsWithRanges()
            : (processedText, [NSRange]())

        let cleanedResultAndMappedRanges = cleanedText.cleanedTextWithRanges(mapping: importedHeaderRanges)
        let cleanedResult = cleanedResultAndMappedRanges.result
        let footnoteRanges = cleanedResultAndMappedRanges.footnoteRanges
        let mappedImportedHeaderRanges = cleanedResultAndMappedRanges.mappedRanges ?? []
        let replacementResult = cleanedResult.text.replacingHonorificPhrasesIfSupported()

        let remappedColoredRanges = cleanedResult.coloredRanges.map {
            replacementResult.remapDisplayedRange($0)
        }
        let remappedFootnoteRanges = footnoteRanges.map {
            replacementResult.remapDisplayedRange($0)
        }
        let remappedImportedHeaderRanges = mappedImportedHeaderRanges.map {
            replacementResult.remapDisplayedRange($0)
        }

        return ProcessedArabicContent(
            sourceText: cleanedResult.text,
            displayText: replacementResult.text,
            coloredRanges: remappedColoredRanges + replacementResult.replacementDisplayRanges,
            footnoteRanges: remappedFootnoteRanges,
            replacementEvents: replacementResult.events,
            importedHeaderRanges: remappedImportedHeaderRanges,
            ligatureRanges: replacementResult.replacementDisplayRanges
        )
    }

    func applyAnnotations(
        _ annotations: [Annotation],
        to textStorage: NSMutableAttributedString,
        showHarakat: Bool,
        replacementEvents: [HonorificReplacementEvent] = []
    ) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        let renderResult = ArabicRenderResult(
            sourceText: textStorage.string,
            attributedString: NSAttributedString(string: textStorage.string),
            replacementEvents: replacementEvents,
            footnoteRanges: []
        )

        for ann in annotations {
            let sourceRange = showHarakat ? ann.rangeDiacritics : ann.range
            let range = renderResult.remapDisplayedRange(sourceRange)
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
            guard let newStyle = oldStyle.mutableCopy() as? NSMutableParagraphStyle else { return }
            newStyle.lineHeightMultiple = state.lineHeight

            textStorage.addAttribute(.paragraphStyle, value: newStyle, range: range)
        }
    }

    private func createAttributedString(
        from content: ProcessedArabicContent,
        color: PlatformColor,
        isMultiLanguage: Bool
    ) -> NSAttributedString {
        var baseAttributes = state.defaultAttributes

        if !isMultiLanguage {
            let rtlStyle = (state.paragraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            rtlStyle.alignment = .right
            rtlStyle.baseWritingDirection = .rightToLeft
            baseAttributes[.paragraphStyle] = rtlStyle
        } else {
            baseAttributes.removeValue(forKey: .paragraphStyle)
        }

        let attributedString = NSMutableAttributedString(
            string: content.displayText,
            attributes: baseAttributes
        )

        if isMultiLanguage {
            applyMultiLanguageParagraphStyles(to: attributedString, displayText: content.displayText)
        }

        if !content.footnoteRanges.isEmpty {
            applyFootnotes(to: attributedString, ranges: content.footnoteRanges)
        }

        let highlightAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
        applyRanges(ranges: content.coloredRanges, attributes: highlightAttributes, to: attributedString)
        applyRanges(ranges: content.importedHeaderRanges, attributes: highlightAttributes, to: attributedString)

        #if canImport(UIKit)
        if !content.ligatureRanges.isEmpty {
            applyLigatureFallbacks(to: attributedString, ligatureRanges: content.ligatureRanges)
        }
        #endif

        return attributedString
    }

    private func applyMultiLanguageParagraphStyles(to attributedString: NSMutableAttributedString, displayText: String) {
        let ltrStyle = (state.paragraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        ltrStyle.alignment = .left
        ltrStyle.baseWritingDirection = .leftToRight

        let rtlStyle = (state.paragraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        rtlStyle.alignment = .right
        rtlStyle.baseWritingDirection = .rightToLeft

        let nsString = displayText as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        nsString.enumerateSubstrings(in: fullRange, options: .byParagraphs) { substring, substringRange, _, _ in
            guard let substring else { return }
            let style = (substring.hasPrefix("\u{202A}") || substring.hasPrefix("\u{202D}")) ? ltrStyle : rtlStyle
            attributedString.addAttribute(.paragraphStyle, value: style, range: substringRange)
        }
    }

    private func applyFootnotes(to attributedString: NSMutableAttributedString, ranges: [NSRange]) {
        let baseFont = state.currentFont
        let smallerFont = baseFont.withSize(baseFont.pointSize - 2)
        #if os(macOS)
        let footnoteColor = PlatformColor.secondaryLabelColor
        #else
        let footnoteColor = PlatformColor.secondaryLabel
        #endif
        let footnoteAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: footnoteColor,
            .font: smallerFont,
        ]
        applyRanges(ranges: ranges, attributes: footnoteAttributes, to: attributedString)
    }

    private func applyRanges(ranges: [NSRange], attributes: [NSAttributedString.Key: Any], to attributedString: NSMutableAttributedString) {
        for range in ranges where range.location + range.length <= attributedString.length {
            attributedString.addAttributes(attributes, range: range)
        }
    }

    #if canImport(UIKit)
    private func applyLigatureFallbacks(to attributedString: NSMutableAttributedString, ligatureRanges: [NSRange]) {
        let baseFont = state.currentFont
        let ctFont = baseFont as CTFont
        let fallbackFontName = "Lateef"
        let fallbackFont = UIFont(name: fallbackFontName, size: baseFont.pointSize) ?? baseFont

        for range in ligatureRanges where range.location + range.length <= attributedString.length {
            let nsString = attributedString.string as NSString
            let length = range.length
            var unichars = [unichar](repeating: 0, count: length)
            var glyphs = [CGGlyph](repeating: 0, count: length)
            nsString.getCharacters(&unichars, range: range)

            let hasGlyph = CTFontGetGlyphsForCharacters(ctFont, unichars, &glyphs, length)
            if !hasGlyph {
                attributedString.addAttribute(.font, value: fallbackFont, range: range)
            }
        }
    }
    #endif

    private func applyAnnotation(_ ann: Annotation, at range: NSRange, to textStorage: NSMutableAttributedString) {
        if ann.type == .highlight {
            let color = PlatformColor(hex: ann.colorHex) ?? .yellow
            textStorage.removeAttribute(.backgroundColor, range: range)
            textStorage.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.6), range: range)
            textStorage.removeAttribute(.underlineStyle, range: range)
        } else if ann.type == .underline {
            textStorage.removeAttribute(.underlineStyle, range: range)
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

struct HonorificReplacementResult {
    let sourceText: String
    let text: String
    let events: [HonorificReplacementEvent]

    func remapDisplayedRange(_ range: NSRange) -> NSRange {
        guard !events.isEmpty else { return range }

        let renderResult = ArabicRenderResult(
            sourceText: sourceText,
            attributedString: NSAttributedString(string: text),
            replacementEvents: events,
            footnoteRanges: []
        )
        return renderResult.remapDisplayedRange(range)
    }

    var replacementDisplayRanges: [NSRange] {
        guard !events.isEmpty else { return [] }

        let renderResult = ArabicRenderResult(
            sourceText: sourceText,
            attributedString: NSAttributedString(string: text),
            replacementEvents: events,
            footnoteRanges: []
        )

        return events.map { event in
            renderResult.remapDisplayedRange(event.oldRange)
        }
    }
}

extension String {
    private static let honorificReplacements: [(phrase: String, glyph: String)] = [
        (.sholawat, "\u{FDFA}"),
        ("رحمهم الله", "\u{FD4F}"),
        ("رحمه الله", "\u{FD40}"),
        ("رضي الله عنهما", "\u{FD44}"),
        ("رضي الله عنهم", "\u{FD43}"),
        ("رضي الله عنها", "\u{FD42}"),
        ("رضي الله عنه", "\u{FD41}"),
        ("سبحانه وتعالى", "\u{FDFE}"),
        ("تبارك وتعالى", "\u{FD4E}"),
        ("عليهم السلام", "\u{FD48}"),
        ("عليها السلام", "\u{FD4D}"),
        ("عليه السلام", "\u{FD47}"),
        ("عز وجل", "\u{FDFF}"),
    ]

    func replacingHonorificPhrasesIfSupported() -> HonorificReplacementResult {
        let source = self as NSString
        let normalized = normalizedArabicHonorificSearchText()
        let matches = findHonorificMatches(in: normalized)

        guard !matches.isEmpty else {
            return HonorificReplacementResult(sourceText: self, text: self, events: [])
        }

        let (finalText, events) = buildHonorificReplacedText(source: source, matches: matches)
        return HonorificReplacementResult(sourceText: self, text: finalText, events: events)
    }

    private func findHonorificMatches(in normalized: NormalizedArabicSearchText) -> [(range: NSRange, glyph: String)] {
        let normalizedSource = normalized.text as NSString
        var matches: [(range: NSRange, glyph: String)] = []
        var searchLocation = 0

        while searchLocation < normalizedSource.length {
            var nextMatch: (range: NSRange, glyph: String)?

            for replacement in String.honorificReplacements {
                let foundRange = normalizedSource.range(
                    of: replacement.phrase,
                    options: [],
                    range: NSRange(location: searchLocation, length: normalizedSource.length - searchLocation)
                )

                guard foundRange.location != NSNotFound else { continue }

                if let current = nextMatch {
                    if foundRange.location < current.range.location {
                        nextMatch = (foundRange, replacement.glyph)
                    }
                } else {
                    nextMatch = (foundRange, replacement.glyph)
                }
            }

            guard let match = nextMatch else { break }
            let originalRange = normalized.originalRange(forNormalizedRange: match.range)
            matches.append((range: originalRange, glyph: match.glyph))
            searchLocation = match.range.location + match.range.length
        }

        return matches
    }

    private func buildHonorificReplacedText(
        source: NSString,
        matches: [(range: NSRange, glyph: String)]
    ) -> (text: String, events: [HonorificReplacementEvent]) {
        var finalText = ""
        finalText.reserveCapacity(source.length)
        var events: [HonorificReplacementEvent] = []
        var currentLocation = 0

        for match in matches {
            let prefixRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            if prefixRange.length > 0 {
                finalText += source.substring(with: prefixRange)
            }

            finalText += match.glyph
            events.append(
                HonorificReplacementEvent(
                    oldRange: match.range,
                    newLength: (match.glyph as NSString).length
                )
            )
            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < source.length {
            finalText += source.substring(from: currentLocation)
        }

        return (finalText, events)
    }

    func normalizedArabicHonorificSearchText() -> NormalizedArabicSearchText {
        var text = ""
        text.reserveCapacity(utf16.count)

        var normalizedToOriginalOffsets: [Int] = []
        normalizedToOriginalOffsets.reserveCapacity(utf16.count + 1)

        var originalOffset = 0
        for scalar in unicodeScalars {
            let scalarString = String(scalar)
            let scalarLength = scalarString.utf16.count

            defer { originalOffset += scalarLength }

            if scalar.isArabicHarakat {
                continue
            }

            normalizedToOriginalOffsets.append(originalOffset)
            text.append(contentsOf: scalarString)
        }

        normalizedToOriginalOffsets.append(utf16.count)

        return NormalizedArabicSearchText(
            text: text,
            normalizedToOriginalOffsets: normalizedToOriginalOffsets
        )
    }
}

struct NormalizedArabicSearchText {
    let text: String
    let normalizedToOriginalOffsets: [Int]

    func originalRange(forNormalizedRange range: NSRange) -> NSRange {
        let start = normalizedToOriginalOffsets[range.location]
        let end = normalizedToOriginalOffsets[range.location + range.length]
        return NSRange(location: start, length: max(0, end - start))
    }
}
