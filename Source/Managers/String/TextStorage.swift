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
        let searchTerms = searchText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.replacingHonorificPhrasesIfSupported().text }

        guard !searchTerms.isEmpty else { return nil }

        let colors: [PlatformColor] = [
            .highlightText,
            PlatformColor.magenta.withAlphaComponent(0.4),
            PlatformColor.systemPink.withAlphaComponent(0.4),
            PlatformColor.systemPurple.withAlphaComponent(0.4),
            PlatformColor.systemIndigo.withAlphaComponent(0.4),
        ]

        let ranges = string.findArabicMatchingRanges(keywords: searchTerms)
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
