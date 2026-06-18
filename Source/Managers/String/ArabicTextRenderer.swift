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

// ArabicTextRenderer.swift - NEW FILE
class ArabicTextRenderer {
    private let state = TextViewState.shared

    func render(
        text: String,
        highlightColor: PlatformColor = .header,
        showHarakat: Bool,
        isMultiLanguage: Bool = false,
        isImported: Bool = false
    ) -> ArabicRenderResult {
        let textWithArabicDigits = text.convertToArabicDigits(isMultilingual: isMultiLanguage)
        let processedText = showHarakat ? textWithArabicDigits : textWithArabicDigits.removingHarakat()

        // Strip <span data-type="title"> tags for imported books and collect header ranges
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
        let displayResult = CleanedTextResult(
            text: replacementResult.text,
            coloredRanges: remappedColoredRanges + replacementResult.replacementDisplayRanges
        )

        let result = CleanedTextAndFootnoteRange(
            result: displayResult,
            footnoteRanges: remappedFootnoteRanges
        )

        return ArabicRenderResult(
            sourceText: cleanedResult.text,
            attributedString: createAttributedString(
                from: result,
                color: highlightColor,
                isMultiLanguage: isMultiLanguage,
                ligatureRanges: replacementResult.replacementDisplayRanges,
                importedHeaderRanges: remappedImportedHeaderRanges
            ),
            replacementEvents: replacementResult.events,
            footnoteRanges: remappedFootnoteRanges
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
            let newStyle = oldStyle.mutableCopy() as! NSMutableParagraphStyle
            newStyle.lineHeightMultiple = state.lineHeight

            textStorage.addAttribute(.paragraphStyle, value: newStyle, range: range)
        }
    }

    private func createAttributedString(from results: CleanedTextAndFootnoteRange, color: PlatformColor, isMultiLanguage: Bool, ligatureRanges: [NSRange] = [], importedHeaderRanges: [NSRange] = []) -> NSAttributedString {
        let result = results.result
        let footnoteRanges = results.footnoteRanges
        
        // Buat string dasar tanpa .paragraphStyle dulu
        var baseAttributes = state.defaultAttributes
        
        if !isMultiLanguage {
            let rtlStyle = (self.state.paragraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            rtlStyle.alignment = .right
            rtlStyle.baseWritingDirection = .rightToLeft
            baseAttributes[.paragraphStyle] = rtlStyle
        } else {
            baseAttributes.removeValue(forKey: .paragraphStyle)
        }
        
        let attributedString = NSMutableAttributedString(
            string: result.text,
            attributes: baseAttributes
        )

        if isMultiLanguage {
            // Cache style objek untuk efisiensi (agar tidak create objek di setiap paragraf)
            let ltrStyle = (self.state.paragraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            ltrStyle.alignment = .left
            ltrStyle.baseWritingDirection = .leftToRight
            
            let rtlStyle = (self.state.paragraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            rtlStyle.alignment = .right
            rtlStyle.baseWritingDirection = .rightToLeft

            // Deteksi dan terapkan arah/alignment per paragraf
            let nsString = result.text as NSString
            let fullRange = NSRange(location: 0, length: nsString.length)
            
            nsString.enumerateSubstrings(in: fullRange, options: .byParagraphs) { (substring, substringRange, _, _) in
                guard let substring = substring else { return }
                
                // Pilih style yang sudah di-cache
                let style: NSMutableParagraphStyle
                if substring.hasPrefix("\u{202A}") || substring.hasPrefix("\u{202D}") {
                    style = ltrStyle
                } else if substring.hasPrefix("\u{202B}") || substring.hasPrefix("\u{202E}") {
                    style = rtlStyle
                } else {
                    style = rtlStyle // Fallback RTL
                }
                
                attributedString.addAttribute(.paragraphStyle, value: style, range: substringRange)
            }
        }

        // Footnote: font lebih kecil + warna sekunder — apply sebelum coloredRanges
        // agar highlight simbol di dalam footnote tetap pakai warna header
        if !footnoteRanges.isEmpty {
            let baseFont = state.currentFont
            let smallerFont = baseFont.withSize(baseFont.pointSize - 2)
            #if os(macOS)
            let footnoteColor = PlatformColor.secondaryLabelColor
            #else
            let footnoteColor = PlatformColor.secondaryLabel
            #endif
            let footnoteAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: footnoteColor,
                .font: smallerFont
            ]
            for range in footnoteRanges {
                if range.location + range.length <= attributedString.length {
                    attributedString.addAttributes(footnoteAttributes, range: range)
                }
            }
        }

        let highlightAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color
        ]

        for range in result.coloredRanges {
            if range.location + range.length <= attributedString.length {
                attributedString.addAttributes(highlightAttributes, range: range)
            }
        }

        // Apply header color to imported book TOC spans
        if !importedHeaderRanges.isEmpty {
            let headerColorAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: color
            ]
            for range in importedHeaderRanges {
                if range.location + range.length <= attributedString.length {
                    attributedString.addAttributes(headerColorAttributes, range: range)
                }
            }
        }

        // Apply Lateef font fallback specifically for ligatures if they are missing from current font
        #if canImport(UIKit)
        if !ligatureRanges.isEmpty {
            let baseFont = state.currentFont
            let ctFont = baseFont as CTFont
            let fallbackFontName = "Lateef"

            let fallbackFont = UIFont(name: fallbackFontName, size: baseFont.pointSize) ?? baseFont

            for range in ligatureRanges {
                if range.location + range.length <= attributedString.length {
                    let substring = (attributedString.string as NSString).substring(with: range)
                    let unichars = Array(substring.utf16)
                    var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
                    
                    let hasGlyph = CTFontGetGlyphsForCharacters(ctFont, unichars, &glyphs, unichars.count)
                    
                    if !hasGlyph {
                        attributedString.addAttribute(.font, value: fallbackFont, range: range)
                    }
                }
            }
        }
        #endif

        return attributedString
    }

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

private struct HonorificReplacementResult {
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

private extension String {
    func replacingHonorificPhrasesIfSupported() -> HonorificReplacementResult {
        let replacements: [(phrase: String, glyph: String)] = [
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

        let source = self as NSString
        let normalized = normalizedArabicHonorificSearchText()
        let normalizedSource = normalized.text as NSString
        var matches: [(range: NSRange, glyph: String)] = []
        var searchLocation = 0

        while searchLocation < normalizedSource.length {
            var nextMatch: (range: NSRange, glyph: String)?

            for replacement in replacements {
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

        guard !matches.isEmpty else {
            return HonorificReplacementResult(sourceText: self, text: self, events: [])
        }

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

        return HonorificReplacementResult(sourceText: self, text: finalText, events: events)
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

private struct NormalizedArabicSearchText {
    let text: String
    let normalizedToOriginalOffsets: [Int]

    func originalRange(forNormalizedRange range: NSRange) -> NSRange {
        let start = normalizedToOriginalOffsets[range.location]
        let end = normalizedToOriginalOffsets[range.location + range.length]
        return NSRange(location: start, length: max(0, end - start))
    }
}
