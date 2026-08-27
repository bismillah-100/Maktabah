//
//  String+Search.swift
//  Maktabah
//
//  Created by MacBook on 06/12/25.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension String {
    func findArabicMatchingRanges(keywords: [String]) -> [NSRange] {
        findArabicMatchingRangesWithIndex(keywords: keywords).map(\.range)
    }

    private struct ArabicSearchTextWord {
        let text: String
        let core: String
        let normStartIdx: Int
        let normEndIdx: Int
    }

    private struct ArabicSearchQueryWord {
        let norm: String
        let core: String
    }

    private struct NormalizedArabicScalarMap {
        let normalizedText: String
        let indexMap: [Int]
        let totalUtf16Length: Int
    }

    @inline(__always)
    private static func normalizeArabicScalar(_ scalar: UnicodeScalar) -> UnicodeScalar {
        switch scalar.value {
        case 0x0623, 0x0625, 0x0622, 0x0671:
            UnicodeScalar(0x0627)! // ا
        case 0x0629:
            UnicodeScalar(0x0647)! // ه
        case 0x0649:
            UnicodeScalar(0x064A)! // ي
        default:
            scalar
        }
    }

    private func buildNormalizedArabicScalarMap() -> NormalizedArabicScalarMap {
        var normalizedScalars: [UnicodeScalar] = []
        normalizedScalars.reserveCapacity(unicodeScalars.count)
        var indexMap: [Int] = []
        indexMap.reserveCapacity(unicodeScalars.count)

        var utf16Offset = 0
        for scalar in unicodeScalars {
            let scalarLen = scalar.utf16.count
            let val = scalar.value

            if scalar.isArabicHarakat || val == 0x0640 {
                utf16Offset += scalarLen
                continue
            }

            let normalizedScalar = Self.normalizeArabicScalar(scalar)
            indexMap.append(utf16Offset)
            normalizedScalars.append(normalizedScalar)
            utf16Offset += scalarLen
        }

        let normalizedText = String(String.UnicodeScalarView(normalizedScalars))
        return NormalizedArabicScalarMap(normalizedText: normalizedText, indexMap: indexMap, totalUtf16Length: utf16Offset)
    }

    private static func extractArabicSearchWords(from normalizedText: String) -> [ArabicSearchTextWord] {
        var textWords: [ArabicSearchTextWord] = []
        textWords.reserveCapacity(normalizedText.count / 5)

        var wordStartCharIdx: String.Index?
        var wordStartScalarOffset = 0
        var currentScalarOffset = 0

        for idx in normalizedText.indices {
            let ch = normalizedText[idx]
            if ch.isWhitespace || ch.isPunctuation {
                if let start = wordStartCharIdx {
                    let wordStr = String(normalizedText[start ..< idx])
                    let core = wordStr.stemArabicLight10()
                    textWords.append(ArabicSearchTextWord(text: wordStr, core: core, normStartIdx: wordStartScalarOffset, normEndIdx: currentScalarOffset))
                    wordStartCharIdx = nil
                }
            } else {
                if wordStartCharIdx == nil {
                    wordStartCharIdx = idx
                    wordStartScalarOffset = currentScalarOffset
                }
            }
            currentScalarOffset += ch.unicodeScalars.count
        }

        if let start = wordStartCharIdx {
            let wordStr = String(normalizedText[start...])
            let core = wordStr.stemArabicLight10()
            textWords.append(ArabicSearchTextWord(text: wordStr, core: core, normStartIdx: wordStartScalarOffset, normEndIdx: currentScalarOffset))
        }

        return textWords
    }

    private static func normalizeArabicSearchToken(_ token: Substring) -> String {
        var norm = ""
        for scalar in token.unicodeScalars {
            if scalar.isArabicHarakat || scalar.value == 0x0640 { continue }
            let normalized = Self.normalizeArabicScalar(scalar)
            norm.unicodeScalars.append(normalized)
        }
        return norm
    }

    private static func parseArabicQueryWords(from keyword: String) -> [ArabicSearchQueryWord] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let rawTokens = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        return rawTokens.compactMap { token -> ArabicSearchQueryWord? in
            let norm = normalizeArabicSearchToken(token)
            guard !norm.isEmpty else { return nil }
            return ArabicSearchQueryWord(norm: norm, core: norm.stemArabicLight10())
        }
    }

    private static func isWordMatch(tw: ArabicSearchTextWord, qw: ArabicSearchQueryWord) -> Bool {
        tw.text == qw.norm || tw.core == qw.core || tw.text == qw.core || tw.core == qw.norm
    }

    private static func findQueryWordMatches(
        queryWords: [ArabicSearchQueryWord],
        textWords: [ArabicSearchTextWord],
        indexMap: [Int],
        totalUtf16Length: Int,
        keywordIndex: Int
    ) -> [(range: NSRange, keywordIndex: Int)] {
        let m = queryWords.count
        guard m <= textWords.count else { return [] }

        var result: [(range: NSRange, keywordIndex: Int)] = []

        for i in 0 ... (textWords.count - m) {
            let sequenceMatches = (0 ..< m).allSatisfy { j in
                isWordMatch(tw: textWords[i + j], qw: queryWords[j])
            }

            guard sequenceMatches else { continue }
            let firstWord = textWords[i]
            let lastWord = textWords[i + m - 1]
            let normStartIdx = firstWord.normStartIdx
            let normEndIdx = lastWord.normEndIdx

            guard normStartIdx < indexMap.count else { continue }
            let rawUtf16Start = indexMap[normStartIdx]
            let rawUtf16End = normEndIdx < indexMap.count ? indexMap[normEndIdx] : totalUtf16Length
            guard rawUtf16End > rawUtf16Start else { continue }

            let nsRange = NSRange(location: rawUtf16Start, length: rawUtf16End - rawUtf16Start)
            result.append((range: nsRange, keywordIndex: keywordIndex))
        }

        return result
    }

    func findArabicMatchingRangesWithIndex(keywords: [String]) -> [(range: NSRange, keywordIndex: Int)] {
        guard !keywords.isEmpty, !isEmpty else { return [] }

        let scalarMap = buildNormalizedArabicScalarMap()
        let textWords = Self.extractArabicSearchWords(from: scalarMap.normalizedText)
        guard !textWords.isEmpty else { return [] }

        var ranges: [(range: NSRange, keywordIndex: Int)] = []

        for (keywordIndex, keyword) in keywords.enumerated() {
            let queryWords = Self.parseArabicQueryWords(from: keyword)
            guard !queryWords.isEmpty else { continue }
            let matchRanges = Self.findQueryWordMatches(
                queryWords: queryWords,
                textWords: textWords,
                indexMap: scalarMap.indexMap,
                totalUtf16Length: scalarMap.totalUtf16Length,
                keywordIndex: keywordIndex
            )
            for item in matchRanges where !ranges.contains(where: { $0.range == item.range && $0.keywordIndex == item.keywordIndex }) {
                ranges.append(item)
            }
        }

        ranges.sort { $0.range.location < $1.range.location }
        return ranges
    }

    func snippetAround(keywords: [String], contextLength: Int = 60) -> String {
        let ranges = findArabicMatchingRanges(keywords: keywords)
        guard let firstRange = ranges.first,
              let targetRange = Range(firstRange, in: self)
        else {
            let limit = min(count, contextLength * 2)
            return String(prefix(limit)).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }

        return buildSnippetString(targetStart: targetRange.lowerBound, targetEnd: targetRange.upperBound, contextLength: contextLength)
    }

    private func countWordsBetweenBounds(startBound: String.Index, endBound: String.Index) -> Int {
        let textBetween = self[startBound ..< endBound]
        return textBetween.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    private func findNearClusterBounds(
        sortedRanges: [(range: NSRange, keywordIndex: Int)],
        uniqueKeywordsCount: Int,
        nearDistance: Int
    ) -> (start: String.Index, end: String.Index)? {
        guard uniqueKeywordsCount > 1 else { return nil }

        var minWordDistance = Int.max
        let maxAllowedDistance = nearDistance * (uniqueKeywordsCount - 1) + 5
        var bestStartIdx: String.Index?
        var bestEndIdx: String.Index?

        for i in 0 ..< sortedRanges.count {
            var currentSet = Set<Int>()
            for j in i ..< sortedRanges.count {
                currentSet.insert(sortedRanges[j].keywordIndex)
                guard currentSet.count == uniqueKeywordsCount else { continue }

                let startRange = sortedRanges[i].range
                let endRange = sortedRanges[j].range

                guard let startBound = Range(startRange, in: self)?.upperBound,
                      let endBound = Range(endRange, in: self)?.lowerBound,
                      startBound <= endBound else { continue }

                let wordsBetween = countWordsBetweenBounds(startBound: startBound, endBound: endBound)
                if wordsBetween <= maxAllowedDistance, wordsBetween < minWordDistance {
                    minWordDistance = wordsBetween
                    bestStartIdx = Range(startRange, in: self)?.lowerBound
                    bestEndIdx = Range(endRange, in: self)?.upperBound
                }
                break
            }
        }

        if let bestStartIdx, let bestEndIdx {
            return (bestStartIdx, bestEndIdx)
        }
        return nil
    }

    private func buildSnippetString(targetStart: String.Index, targetEnd: String.Index, contextLength: Int) -> String {
        var startIdx = index(targetStart, offsetBy: -contextLength, limitedBy: startIndex) ?? startIndex
        var endIdx = index(targetEnd, offsetBy: contextLength, limitedBy: endIndex) ?? endIndex

        if startIdx > startIndex, let spaceIdx = range(of: " ", options: .backwards, range: startIndex ..< startIdx)?.upperBound {
            startIdx = spaceIdx
        }

        if endIdx < endIndex, let spaceIdx = range(of: " ", range: endIdx ..< endIndex)?.lowerBound {
            endIdx = spaceIdx
        }

        let rawSnippet = self[startIdx ..< endIdx]
        var cleanSnippet = rawSnippet
            .replacing("\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if startIdx > startIndex { cleanSnippet = "..." + cleanSnippet }
        if endIdx < endIndex { cleanSnippet = cleanSnippet + "..." }

        return cleanSnippet
    }

    func snippetNear(keywords: [String], nearDistance: Int, contextLength: Int = 60) -> String {
        let rangesWithIndex = findArabicMatchingRangesWithIndex(keywords: keywords)
        guard !rangesWithIndex.isEmpty else {
            let limit = min(count, contextLength * 2)
            return String(prefix(limit)).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }

        let sortedRanges = rangesWithIndex.sorted(by: { $0.range.location < $1.range.location })
        let uniqueKeywordsCount = Set(sortedRanges.map(\.keywordIndex)).count

        let bounds = findNearClusterBounds(
            sortedRanges: sortedRanges,
            uniqueKeywordsCount: uniqueKeywordsCount,
            nearDistance: nearDistance
        )

        let targetStart = bounds?.start ?? (Range(sortedRanges[0].range, in: self)?.lowerBound)
        let targetEnd = bounds?.end ?? (Range(sortedRanges[0].range, in: self)?.upperBound)

        guard let targetStart, let targetEnd else {
            let limit = min(count, contextLength * 2)
            return String(prefix(limit)).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }

        return buildSnippetString(targetStart: targetStart, targetEnd: targetEnd, contextLength: contextLength)
    }

    private func shrinkWindowLeft(
        sortedRanges: [(range: NSRange, keywordIndex: Int)],
        left: inout Int,
        countMap: inout [Int: Int],
        uniqueKeywordsCount: Int,
        satisfiedTypes: Int
    ) {
        while satisfiedTypes == uniqueKeywordsCount {
            let leftKw = sortedRanges[left].keywordIndex
            guard let c = countMap[leftKw], c > 1 else { break }
            countMap[leftKw] = c - 1
            left += 1
        }
    }

    private func evaluateNearWindow(
        left: Int,
        right: Int,
        sortedRanges: [(range: NSRange, keywordIndex: Int)],
        maxAllowedDistance: Int,
        validRanges: inout Set<NSRange>
    ) {
        let startRange = sortedRanges[left].range
        let endRange = sortedRanges[right].range

        if startRange == endRange {
            validRanges.insert(startRange)
            return
        }

        guard let startBound = Range(startRange, in: self)?.upperBound,
              let endBound = Range(endRange, in: self)?.lowerBound,
              startBound <= endBound else { return }

        let wordsBetween = countWordsBetweenBounds(startBound: startBound, endBound: endBound)
        if wordsBetween <= maxAllowedDistance {
            for k in left ... right {
                validRanges.insert(sortedRanges[k].range)
            }
        }
    }

    func filterRangesForNearMode(rangesWithIndex: [(range: NSRange, keywordIndex: Int)], keywordsCount: Int, nearDistance: Int) -> [NSRange] {
        guard rangesWithIndex.count >= 2, keywordsCount > 1 else { return rangesWithIndex.map(\.range) }

        let sortedRanges = rangesWithIndex.sorted(by: { $0.range.location < $1.range.location })
        let uniqueKeywordsCount = Set(sortedRanges.map(\.keywordIndex)).count
        guard uniqueKeywordsCount > 1 else { return [] }

        let maxAllowedDistance = nearDistance * (uniqueKeywordsCount - 1) + 5
        var validRanges = Set<NSRange>()

        var left = 0
        var countMap: [Int: Int] = [:]
        var satisfiedTypes = 0

        for right in 0 ..< sortedRanges.count {
            let rightKw = sortedRanges[right].keywordIndex
            countMap[rightKw, default: 0] += 1
            if countMap[rightKw] == 1 { satisfiedTypes += 1 }

            shrinkWindowLeft(
                sortedRanges: sortedRanges,
                left: &left,
                countMap: &countMap,
                uniqueKeywordsCount: uniqueKeywordsCount,
                satisfiedTypes: satisfiedTypes
            )

            guard satisfiedTypes == uniqueKeywordsCount else { continue }

            evaluateNearWindow(
                left: left,
                right: right,
                sortedRanges: sortedRanges,
                maxAllowedDistance: maxAllowedDistance,
                validRanges: &validRanges
            )
        }

        return sortedRanges.map(\.range).filter { validRanges.contains($0) }
    }

    func highlightedAttributedText(keywords: [String], nearDistance: Int? = nil) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: self)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = .right

        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributed.length))

        var ranges: [NSRange]

        if let nearDistance, keywords.count > 1 {
            let rangesWithIndex = findArabicMatchingRangesWithIndex(keywords: keywords)
            ranges = filterRangesForNearMode(rangesWithIndex: rangesWithIndex, keywordsCount: keywords.count, nearDistance: nearDistance)
        } else {
            ranges = findArabicMatchingRanges(keywords: keywords)
        }

        for range in ranges where range.location + range.length <= attributed.length {
            attributed.addAttribute(.backgroundColor, value: PlatformColor.systemYellow.withAlphaComponent(0.4), range: range)
        }

        return attributed
    }
}
