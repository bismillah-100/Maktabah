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

extension NSTextStorage {
    @discardableResult
    func highlightSearchText(
        searchText: String,
        baseColor: PlatformColor
    ) -> NSRange? {
        // Strip FTS syntax (NEAR, AND, OR, quotes, parens) dan ekstrak kata bersih.
        // Mendukung query biasa (koma-separated) maupun raw FTS/NEAR syntax.
        let hasNearSyntax = searchText.uppercased().contains("NEAR")
        let mode: SearchMode = hasNearSyntax ? .near : .contains

        var searchTerms = FtsQueryParser.extractKeywords(query: searchText, mode: mode)
            .map { $0.replacingHonorificPhrasesIfSupported().text }

        // Fallback: jika ekstraksi gagal, coba parsing koma biasa
        if searchTerms.isEmpty {
            searchTerms = searchText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { $0.replacingHonorificPhrasesIfSupported().text }
        }

        guard !searchTerms.isEmpty else { return nil }

        let colors: [PlatformColor] = [
            .highlightText,
            PlatformColor.magenta.withAlphaComponent(0.4),
            PlatformColor.systemPink.withAlphaComponent(0.4),
            PlatformColor.systemPurple.withAlphaComponent(0.4),
            PlatformColor.systemIndigo.withAlphaComponent(0.4),
        ]

        var ranges: [NSRange]
        
        // Hanya highlight keyword yang merupakan bagian dari valid cluster jika mode NEAR
        if mode == .near, searchTerms.count > 1 {
            let nearDistance = FtsQueryParser.extractNearDistance(query: searchText) ?? 10
            let rangesWithIndex = string.findArabicMatchingRangesWithIndex(keywords: searchTerms)
            ranges = string.filterRangesForNearMode(rangesWithIndex: rangesWithIndex, keywordsCount: searchTerms.count, nearDistance: nearDistance)
        } else {
            ranges = string.findArabicMatchingRanges(keywords: searchTerms)
        }
        
        guard !ranges.isEmpty else { return nil }

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

        // Kembalikan range match pertama untuk scroll-to-visible
        return ranges.first
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
