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
