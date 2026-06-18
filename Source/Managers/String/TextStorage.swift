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
        let rawText = string

        var normalizedChars: [Character] = []
        var indexMap: [Int] = []

        let diacritics = CharacterSet(charactersIn: "\u{064B}\u{064C}\u{064D}\u{064E}\u{064F}\u{0650}\u{0651}\u{0652}\u{0670}\u{0653}\u{0654}\u{0655}")

        var utf16Offset = 0
        for char in rawText {
            let scalars = char.unicodeScalars
            let isDiacritic = scalars.count == 1 && diacritics.contains(scalars.first!)
            let isTatweel = scalars.count == 1 && scalars.first!.value == 0x0640

            if isDiacritic || isTatweel {
                utf16Offset += char.utf16.count
                continue
            }

            let alefVariants: Set<Unicode.Scalar> = ["أ", "إ", "آ", "ٱ"]
            let normalizedChar: Character = if scalars.count == 1, let scalar = scalars.first, alefVariants.contains(scalar) {
                "ا"
            } else {
                char
            }

            indexMap.append(utf16Offset)
            normalizedChars.append(normalizedChar)
            utf16Offset += char.utf16.count
        }

        let normalizedText = String(normalizedChars)

        let searchTerms = searchText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.normalizeArabic() }

        guard !searchTerms.isEmpty else { return nil }

        let colors: [PlatformColor] = [
            .highlightText,
            PlatformColor.magenta.withAlphaComponent(0.4),
            PlatformColor.systemPink.withAlphaComponent(0.4),
            PlatformColor.systemPurple.withAlphaComponent(0.4),
            PlatformColor.systemIndigo.withAlphaComponent(0.4),
        ]

        var firstMatchRange: NSRange?

        beginEditing()
        for (index, searchTerm) in searchTerms.enumerated() {
            let color = colors[index % colors.count]
            var searchStart = normalizedText.startIndex

            while searchStart < normalizedText.endIndex,
                  let found = normalizedText.range(
                      of: searchTerm,
                      options: [.diacriticInsensitive],
                      range: searchStart ..< normalizedText.endIndex
                  )
            {
                var normStartIdx = normalizedText.distance(from: normalizedText.startIndex, to: found.lowerBound)
                let normEndIdx = normalizedText.distance(from: normalizedText.startIndex, to: found.upperBound)

                if searchTerm == "لله", normStartIdx > 0 {
                    let prevIndex = normalizedText.index(found.lowerBound, offsetBy: -1)
                    let prevChar = normalizedText[prevIndex]

                    if prevChar == "ا" || prevChar == "أ" || prevChar == "إ" || prevChar == "آ" {
                        normStartIdx -= 1
                    }
                }

                guard normStartIdx < indexMap.count else { break }

                let rawUtf16Start = indexMap[normStartIdx]
                let rawUtf16End: Int = if normEndIdx < indexMap.count {
                    indexMap[normEndIdx]
                } else {
                    rawText.utf16.count
                }

                let nsRange = NSRange(location: rawUtf16Start, length: rawUtf16End - rawUtf16Start)

                if firstMatchRange == nil {
                    firstMatchRange = nsRange
                }

                var hasBackground = false
                enumerateAttribute(.backgroundColor, in: nsRange, options: []) { value, _, stop in
                    if value != nil { hasBackground = true; stop.pointee = true }
                }

                if !hasBackground {
                    addAttribute(.backgroundColor, value: color, range: nsRange)
                }

                searchStart = found.upperBound
            }
        }
        endEditing()

        return firstMatchRange
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
