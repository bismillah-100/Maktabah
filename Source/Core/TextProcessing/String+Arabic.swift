//
//  String+Arabic.swift
//  Maktabah
//
//  Created by MacBook on 06/12/25.
//

import Foundation

extension String {
    func normalizeArabic(_ removeDiacritics: Bool = true) -> String {
        var result = ""
        result.reserveCapacity(utf8.count)

        for scalar in unicodeScalars {
            let val = scalar.value
            if (removeDiacritics && scalar.isArabicHarakat) || val == 0x0640 { continue }
            let normalized = (val == 0x0623 || val == 0x0625 || val == 0x0622 || val == 0x0671) ? UnicodeScalar(0x0627)! : scalar
            result.unicodeScalars.append(normalized)
        }

        return result
    }

    func normalizedForMatching() -> String {
        removingHarakat()
    }

    func convertToArabicDigits(isMultilingual: Bool = false) -> String {
        isMultilingual ? convertToArabicDigitsMultilingual() : convertToArabicDigitsDirect()
    }

    private func convertToArabicDigitsDirect() -> String {
        var newScalars = String.UnicodeScalarView()
        newScalars.reserveCapacity(unicodeScalars.count)
        for scalar in unicodeScalars {
            newScalars.append(scalar.toArabicDigit())
        }
        return String(newScalars)
    }

    private func convertToArabicDigitsMultilingual() -> String {
        var newScalars = String.UnicodeScalarView()
        newScalars.reserveCapacity(unicodeScalars.count)

        var currentParagraphScalars = [UnicodeScalar]()
        currentParagraphScalars.reserveCapacity(512)

        var hasSeenLetter = false
        var isArabicParagraph = false

        func flushParagraph() {
            if isArabicParagraph {
                for scalar in currentParagraphScalars {
                    newScalars.append(scalar.toArabicDigit())
                }
            } else {
                newScalars.append(contentsOf: currentParagraphScalars)
            }
            currentParagraphScalars.removeAll(keepingCapacity: true)
            hasSeenLetter = false
            isArabicParagraph = false
        }

        for scalar in unicodeScalars {
            currentParagraphScalars.append(scalar)

            if scalar.value == 0x0A || scalar.value == 0x0D {
                flushParagraph()
            } else if !hasSeenLetter, Character(scalar).isLetter {
                hasSeenLetter = true
                isArabicParagraph = (0x0600 ... 0x06FF).contains(scalar.value) ||
                    (0x0750 ... 0x077F).contains(scalar.value) ||
                    (0x08A0 ... 0x08FF).contains(scalar.value)
            }
        }

        if !currentParagraphScalars.isEmpty {
            flushParagraph()
        }

        return String(newScalars)
    }

    /** Cari range di teks original (dengan harakat).
     `approximateRange` berada dalam koordinat NO-HARAKAT (sourceText yang sudah di-strip).
     `self` adalah teks WITH-HARAKAT (diacText / nash asli).

     Solusi: strip harakat dari self sambil membangun offsetMap ke posisi asli,
     cari selectedText di no-harakat space (koordinat cocok dengan approximateRange),
     lalu gunakan offsetMap untuk menghasilkan range di with-harakat string. */
    func findRangeInOriginal(selectedText: String, approximateRange: NSRange) -> NSRange {
        let cleanSelected = selectedText.normalizedForMatching()
        guard !cleanSelected.isEmpty else { return approximateRange }

        var noHarakatText = ""
        noHarakatText.reserveCapacity(utf16.count)
        var offsetMap = [Int]()
        offsetMap.reserveCapacity(utf16.count + 1)

        var withHarakatIdx = 0
        for scalar in unicodeScalars {
            let len = scalar.utf16.count
            if !scalar.isArabicHarakat {
                for _ in 0 ..< len {
                    offsetMap.append(withHarakatIdx)
                }
                noHarakatText.unicodeScalars.append(scalar)
            }
            withHarakatIdx += len
        }
        offsetMap.append(withHarakatIdx)

        let nsNoHarakat = noHarakatText as NSString
        let totalLen = nsNoHarakat.length
        let cleanLen = (cleanSelected as NSString).length
        let radius = 300
        let searchStart = max(0, approximateRange.location - radius)
        let searchEnd = min(totalLen, approximateRange.location + approximateRange.length + radius + cleanLen)
        let searchLength = searchEnd - searchStart

        var found = NSRange(location: NSNotFound, length: 0)
        if searchLength > 0 {
            found = nsNoHarakat.range(
                of: cleanSelected,
                options: .diacriticInsensitive,
                range: NSRange(location: searchStart, length: searchLength)
            )
        }
        if found.location == NSNotFound {
            found = nsNoHarakat.range(of: cleanSelected, options: .diacriticInsensitive)
        }
        guard found.location != NSNotFound else { return approximateRange }

        let mapStart = min(found.location, offsetMap.count - 1)
        let mapEnd = min(found.location + found.length, offsetMap.count - 1)
        let harakatStart = offsetMap[mapStart]
        let harakatEnd = offsetMap[mapEnd]
        return NSRange(location: harakatStart, length: max(0, harakatEnd - harakatStart))
    }

    func calculateRangeWithoutHarakat(from sourceRange: NSRange, in sourceTextWithHarakat: String) -> NSRange {
        var startOffset = 0
        var selectedLength = 0
        var currentUtf16 = 0

        for scalar in sourceTextWithHarakat.unicodeScalars {
            let len = scalar.utf16.count
            let isHarakat = scalar.isArabicHarakat

            if currentUtf16 < sourceRange.location {
                if !isHarakat {
                    startOffset += len
                }
            } else if currentUtf16 < sourceRange.location + sourceRange.length {
                if !isHarakat {
                    selectedLength += len
                }
            } else {
                break
            }

            currentUtf16 += len
        }

        return NSRange(location: startOffset, length: selectedLength)
    }
}

extension Character {
    var isArabicLetter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x0600 ... 0x06FF).contains(scalar.value) ||
            (0x0750 ... 0x077F).contains(scalar.value) ||
            (0x08A0 ... 0x08FF).contains(scalar.value)
    }

    func isArabicHarakat() -> Bool {
        unicodeScalars.allSatisfy(\.isArabicHarakat)
    }
}

extension UnicodeScalar {
    private static let arabicDigits: [UnicodeScalar] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]

    var isArabicHarakat: Bool {
        (0x064B ... 0x0652).contains(value) ||
            value == 0x0670 ||
            (0x0653 ... 0x0655).contains(value) ||
            value == 0x0656 ||
            (0x06D6 ... 0x06DC).contains(value) ||
            (0x06DF ... 0x06E4).contains(value) ||
            (0x06E7 ... 0x06E8).contains(value) ||
            (0x06EA ... 0x06ED).contains(value)
    }

    func toArabicDigit() -> UnicodeScalar {
        if value >= 48, value <= 57 {
            return Self.arabicDigits[Int(value - 48)]
        }
        return self
    }
}

// MARK: - Lucene Arabic Light10 Stemmer

public enum ArabicLightStemmer {
    private static let prefixScalars: [[UnicodeScalar]] = [
        "والله", "وبالله", "فالله", "فبالله",
        "والل", "فالل", "بالل", "كالل", "وللم", "فللم",
        "وال", "فال", "بال", "كال", "لل", "ال",
    ].map { Array($0.removingHarakat().unicodeScalars) }

    private static let suffixScalars: [[UnicodeScalar]] = [
        "هما", "تاني", "تَيْن", "كُمَا", "هُمَا",
        "ان", "ات", "ون", "ين", "يه", "ية", "هم", "هن", "كم", "نا", "ها", "وا", "يا", "ك",
    ].map { Array($0.removingHarakat().unicodeScalars) }

    public static func stemWord(_ input: String) -> String {
        guard !input.isEmpty else { return input }

        var buffer = ContiguousArray<UnicodeScalar>()
        buffer.reserveCapacity(input.unicodeScalars.count)

        stemWordToBuffer(input.unicodeScalars, into: &buffer)

        return String(String.UnicodeScalarView(buffer))
    }

    private static func normalizeScalarsForStemming(_ scalars: some Sequence<UnicodeScalar>) -> ContiguousArray<UnicodeScalar> {
        var clean = ContiguousArray<UnicodeScalar>()
        clean.reserveCapacity(32)

        for scalar in scalars {
            let val = scalar.value
            if scalar.isArabicHarakat || val == 0x0640 { continue }

            let mapped: UnicodeScalar = switch val {
            case 0x0623, 0x0625, 0x0622, 0x0671: UnicodeScalar(0x0627)!
            case 0x0629: UnicodeScalar(0x0647)!
            case 0x0649: UnicodeScalar(0x064A)!
            default: scalar
            }
            clean.append(mapped)
        }
        return clean
    }

    private static func trimPrefix(from clean: ContiguousArray<UnicodeScalar>, start: inout Int, count: inout Int) {
        for prefix in prefixScalars where count - prefix.count >= 3 {
            let pLen = prefix.count
            if (0 ..< pLen).allSatisfy({ clean[start + $0] == prefix[$0] }) {
                start += pLen
                count -= pLen
                break
            }
        }
    }

    private static func trimSuffix(from clean: ContiguousArray<UnicodeScalar>, start: Int, count: inout Int) {
        for suffix in suffixScalars where count - suffix.count >= 3 {
            let sLen = suffix.count
            if (0 ..< sLen).allSatisfy({ clean[start + count - sLen + $0] == suffix[$0] }) {
                count -= sLen
                break
            }
        }
    }

    public static func stemWordToBuffer(_ scalars: some Sequence<UnicodeScalar>, into output: inout ContiguousArray<UnicodeScalar>) {
        let clean = normalizeScalarsForStemming(scalars)
        var start = 0
        var count = clean.count

        trimPrefix(from: clean, start: &start, count: &count)
        trimSuffix(from: clean, start: start, count: &count)

        if count > 0 {
            output.append(contentsOf: clean[start ..< (start + count)])
        }
    }

    public static func stemText(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var outputScalars = ContiguousArray<UnicodeScalar>()
        outputScalars.reserveCapacity(text.unicodeScalars.count)

        var currentToken = ContiguousArray<UnicodeScalar>()
        currentToken.reserveCapacity(32)

        for scalar in text.unicodeScalars {
            let val = scalar.value
            let isArabic = (0x0600 ... 0x06FF).contains(val) ||
                (0x0750 ... 0x077F).contains(val) ||
                (0x08A0 ... 0x08FF).contains(val)

            if isArabic {
                currentToken.append(scalar)
            } else {
                if !currentToken.isEmpty {
                    stemWordToBuffer(currentToken, into: &outputScalars)
                    currentToken.removeAll(keepingCapacity: true)
                }
                outputScalars.append(scalar)
            }
        }

        if !currentToken.isEmpty {
            stemWordToBuffer(currentToken, into: &outputScalars)
        }

        return String(String.UnicodeScalarView(outputScalars))
    }
}

public extension String {
    func stemArabicLight10() -> String {
        ArabicLightStemmer.stemText(self)
    }
}
