//
//  TextStorage.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 21/06/26.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension NSMutableAttributedString {
    @discardableResult
    func highlightSearchText(
        searchText: String,
        mode: SearchMode?,
        baseColor: PlatformColor,
        nearDistance: Int = 10
    ) -> [NSRange] {
        let searchMode = mode ?? (searchText.uppercased().contains("NEAR") ? .near : .contains)

        let searchTerms = FtsQueryParser.extractKeywords(query: searchText, mode: searchMode)
            .map { $0.replacingHonorificPhrasesIfSupported().text }

        guard !searchTerms.isEmpty else { return [] }

        let colors: [PlatformColor] = [
            .highlightText,
            PlatformColor.magenta.withAlphaComponent(0.4),
            PlatformColor.systemPink.withAlphaComponent(0.4),
            PlatformColor.systemPurple.withAlphaComponent(0.4),
            PlatformColor.systemIndigo.withAlphaComponent(0.4),
        ]

        var ranges: [NSRange]

        // Hanya highlight keyword yang merupakan bagian dari valid cluster jika mode NEAR
        if searchMode == .near, searchTerms.count > 1 {
            let rangesWithIndex = string.findArabicMatchingRangesWithIndex(keywords: searchTerms)
            ranges = string.filterRangesForNearMode(rangesWithIndex: rangesWithIndex, keywordsCount: searchTerms.count, nearDistance: nearDistance)
        } else {
            ranges = string.findArabicMatchingRanges(keywords: searchTerms)
        }

        guard !ranges.isEmpty else { return [] }

        beginEditing()
        for (index, range) in ranges.enumerated() {
            let color = colors[index % colors.count]
            if range.location + range.length <= length {
                var hasBackground = false
                enumerateAttribute(.backgroundColor, in: range, options: []) { value, _, stop in
                    if value != nil { hasBackground = true; stop.pointee = true }
                }

                if !hasBackground {
                    addAttribute(.backgroundColor, value: color, range: range)
                }
            }
        }
        endEditing()

        // Kembalikan semua range match untuk popup multi-keyword (misal mode NEAR)
        return ranges
    }

    #if os(macOS)
    func applyFont(footnoteRanges: [NSRange], fontName: String, fontSize: CGFloat) {
        let baseFont = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let fullRange = NSRange(location: 0, length: length)

        beginEditing()
        addAttribute(.font, value: baseFont, range: fullRange)

        if !footnoteRanges.isEmpty {
            let footnoteFont = NSFont(name: fontName, size: fontSize - 2) ?? baseFont.withSize(fontSize - 2)
            for range in footnoteRanges where range.location + range.length <= length {
                self.addAttribute(.font, value: footnoteFont, range: range)
            }
        }
        endEditing()
    }
    #endif
}

extension NSAttributedString.Key {
    static let enhancedUnderline = NSAttributedString.Key("enhancedUnderline")
}

extension NSTextStorage {
    private static let annotationAttributeKeys: [NSAttributedString.Key] = [
        .backgroundColor,
        .underlineStyle,
        .underlineColor,
        .link,
        NSAttributedString.Key("annotationID"),
        NSAttributedString.Key("annotationNote"),
        .enhancedUnderline,
    ]

    func removeAnnotationAttributes(in ranges: [NSRange]) {
        for range in ranges {
            for key in Self.annotationAttributeKeys {
                removeAttribute(key, range: range)
            }
        }
    }

    func findAnnotationRanges(matching predicate: (Any?) -> Bool) -> [NSRange] {
        var ranges: [NSRange] = []
        enumerateAttribute(
            NSAttributedString.Key("annotationID"),
            in: NSRange(location: 0, length: length),
            options: []
        ) { value, range, _ in
            if predicate(value) {
                ranges.append(range)
            }
        }
        return ranges
    }
}

extension NSTextLayoutManager {
    func ensureFullDocumentLayout() {
        enumerateTextLayoutFragments(
            from: documentRange.location,
            options: [.ensuresLayout]
        ) { _ in true }
    }

    /// Memastikan layout TextKit 2 telah dikomputasi untuk rentang NSRange tertentu tanpa memblokir seluruh dokumen.
    func ensureLayout(for range: NSRange) {
        guard range.location >= 0, range.length > 0,
              let start = location(documentRange.location, offsetBy: range.location),
              let end = location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return }
        ensureLayout(for: textRange)
    }

    /// Memastikan layout TextKit 2 telah dikomputasi untuk sekumpulan rentang NSRange.
    func ensureLayout(for ranges: [NSRange]) {
        for range in ranges {
            ensureLayout(for: range)
        }
    }
}
