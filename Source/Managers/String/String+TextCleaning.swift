//
//  String+TextCleaning.swift
//  Maktabah
//
//  Created by MacBook on 06/12/25.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

typealias CleanedTextAndFootnoteRange = (result: CleanedTextResult, footnoteRanges: [NSRange])

struct CleanedTextWithRangesResult {
    let result: CleanedTextResult
    let footnoteRanges: [NSRange]
    let mappedRanges: [NSRange]?
}

enum KutubMode {
    case normal
    case mulakhos
}

private enum StringExtCache {
    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ar")
        return formatter
    }()

    static let tabaqaRegex: NSRegularExpression? = {
        let pattern = #"(W)|([FGHIJKLMNOP])|([0-9]+)"#
        return try? NSRegularExpression(pattern: pattern)
    }()
}

extension String {
    static let sholawat = "صلى الله عليه وسلم"

    private var replacementL: String {
        if UserDefaults.standard.textViewFontName == ArabicFont.alBayan.rawValue ||
            UserDefaults.standard.textViewFontName == "DecoType Naskh"
        {
            " ﴾"
        } else {
            " ﴿"
        }
    }

    private var replacementR: String {
        if UserDefaults.standard.textViewFontName == ArabicFont.alBayan.rawValue ||
            UserDefaults.standard.textViewFontName == "DecoType Naskh"
        {
            "﴿ "
        } else {
            "﴾ "
        }
    }

    func removingHarakat() -> String {
        String(unicodeScalars.filter { !$0.isArabicHarakat })
    }

    private struct BracketConfig {
        let left: String
        let right: String
        let leftLen: Int
        let rightLen: Int

        init(left: String, right: String) {
            self.left = left
            self.right = right
            leftLen = left.utf16.count
            rightLen = right.utf16.count
        }
    }

    private struct TextCleanDeltaEvent {
        let oldOffset: Int
        let delta: Int
    }

    private static let punctuationSet: Set<Character> = [
        "(", ")", "[", "]", "«", "»", ".", "،", ",", ":", "!", "/", "؟", "?", "\"", ";", "؛", "|",
    ]

    @inline(__always)
    private static func appendCleanedCharacter(
        _ character: Character,
        charLen: Int,
        config: BracketConfig,
        state: inout TextParseState,
        nextDelta: inout Int
    ) {
        if character == "{" {
            let symbolStart = state.finalString.utf16.count
            state.finalString += config.left
            nextDelta += (config.leftLen - charLen)
            state.coloredRanges.append(NSRange(location: symbolStart, length: config.leftLen))
        } else if character == "}" {
            let symbolStart = state.finalString.utf16.count
            state.finalString += config.right
            nextDelta += (config.rightLen - charLen)
            state.coloredRanges.append(NSRange(location: symbolStart, length: config.rightLen))
        } else {
            let symbolStart = state.finalString.utf16.count
            state.finalString.append(character)
            if punctuationSet.contains(character) {
                state.coloredRanges.append(NSRange(location: symbolStart, length: 1))
            }
        }
    }

    private static func mapRangesWithDeltaEvents(_ ranges: [NSRange], events: [TextCleanDeltaEvent]) -> [NSRange] {
        ranges.map { range -> NSRange in
            var locDelta = 0
            for event in events {
                if range.location >= event.oldOffset {
                    locDelta = event.delta
                } else {
                    break
                }
            }
            let newLocation = range.location + locDelta

            var endDelta = 0
            for event in events {
                if range.location + range.length >= event.oldOffset {
                    endDelta = event.delta
                } else {
                    break
                }
            }
            let newEnd = range.location + range.length + endDelta
            let newLength = Swift.max(0, newEnd - newLocation)

            return NSRange(location: newLocation, length: newLength)
        }
    }

    private struct CleanedTextParseOutput {
        var finalString: String
        var coloredRanges: [NSRange]
        var events: [TextCleanDeltaEvent]
    }

    private struct TextParseState {
        var finalString = ""
        var coloredRanges: [NSRange] = []
        var events: [TextCleanDeltaEvent] = []
        var oldUtf16Offset = 0
        var currentDelta = 0
    }

    func cleanedTextWithRanges(mapping ranges: [NSRange]? = nil) -> CleanedTextWithRangesResult {
        let output = parseCleanedTextAndEvents()
        let structural = output.finalString.structuralHighlightRanges()
        let coloredRanges = output.coloredRanges + structural.colored
        let mapped = ranges.map { Self.mapRangesWithDeltaEvents($0, events: output.events) }

        return CleanedTextWithRangesResult(
            result: CleanedTextResult(text: output.finalString, coloredRanges: coloredRanges),
            footnoteRanges: structural.footnote,
            mappedRanges: mapped
        )
    }

    private func parseCleanedTextAndEvents() -> CleanedTextParseOutput {
        var state = TextParseState()
        state.finalString.reserveCapacity(count)
        state.coloredRanges.reserveCapacity(8)

        let removableCharacters: Set<Character> = ["¬", "§"]
        let bracketConfig = BracketConfig(left: replacementL, right: replacementR)

        var index = startIndex

        while index < endIndex {
            let character = self[index]
            let charLen = String(character).utf16.count
            var nextDelta = state.currentDelta

            if removableCharacters.contains(character) {
                nextDelta -= charLen
                index = self.index(after: index)
            } else if let advanced = processEscapedNewline(from: index, state: &state, nextDelta: &nextDelta) {
                index = advanced
                continue
            } else {
                Self.appendCleanedCharacter(
                    character,
                    charLen: charLen,
                    config: bracketConfig,
                    state: &state,
                    nextDelta: &nextDelta
                )
                index = self.index(after: index)
            }

            if nextDelta != state.currentDelta {
                state.events.append(TextCleanDeltaEvent(oldOffset: state.oldUtf16Offset + charLen, delta: nextDelta))
                state.currentDelta = nextDelta
            }
            state.oldUtf16Offset += charLen
        }

        return CleanedTextParseOutput(finalString: state.finalString, coloredRanges: state.coloredRanges, events: state.events)
    }

    private func processEscapedNewline(
        from index: String.Index,
        state: inout TextParseState,
        nextDelta: inout Int
    ) -> String.Index? {
        guard self[index] == "\\",
              let nextIndex = self.index(index, offsetBy: 1, limitedBy: endIndex),
              nextIndex < endIndex,
              self[nextIndex] == "n"
        else { return nil }

        let charLen = 1
        let nextCharLen = 1
        state.finalString.append("\n")
        nextDelta -= 1

        if nextDelta != state.currentDelta {
            state.events.append(TextCleanDeltaEvent(oldOffset: state.oldUtf16Offset + charLen + nextCharLen, delta: nextDelta))
            state.currentDelta = nextDelta
        }
        state.oldUtf16Offset += charLen + nextCharLen
        return self.index(after: nextIndex)
    }

    private enum Cached {
        static let spanTag = try? NSRegularExpression(
            pattern: #"<span[^>]*data-type=(?:[\'\"]?)title(?:[\'\"]?)[^>]*>(.*?)</span>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let anchorTag = try? NSRegularExpression(
            pattern: #"<a\s[^>]*href="inr://[^"]*"[^>]*>(.*?)</a>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let hadeethTag = try? NSRegularExpression(
            pattern: #"<hadeeth[^>]*>"#,
            options: []
        )
        static let manTag = try? NSRegularExpression(
            pattern: #"<man[^>]*>(.*?)</man>"#,
            options: [.dotMatchesLineSeparators]
        )
    }

    func stripSpanTags() -> String {
        guard !isEmpty else { return self }
        if !contains("<") {
            return self
        }

        var result = ""
        result.reserveCapacity(utf8.count)

        var isInsideTag = false

        for scalar in unicodeScalars {
            if scalar == "<" {
                isInsideTag = true
            } else if scalar == ">" {
                if isInsideTag {
                    isInsideTag = false
                } else {
                    result.unicodeScalars.append(scalar)
                }
            } else if !isInsideTag {
                result.unicodeScalars.append(scalar)
            }
        }

        return result
    }

    private enum TagMatchType {
        case header(innerText: String)
        case anchor(innerText: String)
        case hadeeth
        case man(innerText: String)

        var replacementText: String {
            switch self {
            case let .header(inner), let .anchor(inner), let .man(inner):
                inner
            case .hadeeth:
                ""
            }
        }
    }

    private struct TagMatchItem {
        let range: NSRange
        let type: TagMatchType
    }

    private static func collectTagMatches(in nsSelf: NSString, text: String, fullRange: NSRange) -> [TagMatchItem] {
        var allMatches: [TagMatchItem] = []

        Cached.spanTag?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let inner = nsSelf.substring(with: match.range(at: 1))
            allMatches.append(TagMatchItem(range: match.range, type: .header(innerText: inner)))
        }

        Cached.anchorTag?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let inner = nsSelf.substring(with: match.range(at: 1))
            allMatches.append(TagMatchItem(range: match.range, type: .anchor(innerText: inner)))
        }

        Cached.hadeethTag?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            allMatches.append(TagMatchItem(range: match.range, type: .hadeeth))
        }

        Cached.manTag?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let inner = nsSelf.substring(with: match.range(at: 1))
            allMatches.append(TagMatchItem(range: match.range, type: .man(innerText: inner)))
        }

        allMatches.sort { $0.range.location < $1.range.location }
        return allMatches
    }

    private static func applyTagReplacements(to nsSelf: NSString, matches: [TagMatchItem]) -> String {
        guard let mutableString =
            nsSelf.mutableCopy() as? NSMutableString
        else { return nsSelf as String }

        for m in matches.reversed() {
            mutableString.replaceCharacters(in: m.range, with: m.type.replacementText)
        }
        return mutableString as String
    }

    private static func calculateAdjustedHeaderRanges(matches: [TagMatchItem]) -> [NSRange] {
        var headerRanges: [NSRange] = []
        var deltaOffset = 0

        for m in matches {
            let oldLength = m.range.length
            let replacement = m.type.replacementText
            let newLength = (replacement as NSString).length

            if case .header = m.type {
                let newLocation = m.range.location + deltaOffset
                headerRanges.append(NSRange(location: newLocation, length: newLength))
            }

            deltaOffset += (newLength - oldLength)
        }

        return headerRanges
    }

    func stripSpanTagsWithRanges() -> (text: String, headerRanges: [NSRange]) {
        guard !isEmpty else { return (self, []) }

        let nsSelf = self as NSString
        let fullRange = NSRange(location: 0, length: nsSelf.length)
        let matches = Self.collectTagMatches(in: nsSelf, text: self, fullRange: fullRange)

        guard !matches.isEmpty else { return (self, []) }

        let finalString = Self.applyTagReplacements(to: nsSelf, matches: matches)
        let headerRanges = Self.calculateAdjustedHeaderRanges(matches: matches)

        return (finalString, headerRanges)
    }

    private func structuralHighlightRanges() -> (colored: [NSRange], footnote: [NSRange]) {
        guard !isEmpty else { return ([], []) }

        enum Cached {
            static let label = try? NSRegularExpression(
                pattern: #"^\s*\([^)]+\)"#,
                options: .anchorsMatchLines
            )
            static let closer = try? NSRegularExpression(
                pattern: #"^\s*\S+\s*-"#,
                options: .anchorsMatchLines
            )
            static let separator = try? NSRegularExpression(
                pattern: #"^_{3,}$"#,
                options: .anchorsMatchLines
            )
        }

        var colored: [NSRange] = []
        var footnote: [NSRange] = []
        let ns = self as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        Cached.label?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match else { return }
            colored.append(match.range)
        }

        Cached.closer?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match else { return }
            colored.append(match.range)
        }

        Cached.separator?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match else { return }
            colored.append(match.range)
            let afterSep = match.range.location + match.range.length
            if afterSep < ns.length {
                footnote.append(NSRange(location: afterSep, length: ns.length - afterSep))
            }
        }

        return (colored, footnote)
    }

    func cleanedText() -> String {
        let replL = replacementL
        let replR = replacementR
        let removable: Set<Character> = ["¬", "§"]

        var result = ""
        result.reserveCapacity(count)

        var index = startIndex
        while index < endIndex {
            let ch = self[index]
            if removable.contains(ch) {
                index = self.index(after: index)
            } else if ch == "\\",
                      let next = self.index(index, offsetBy: 1, limitedBy: endIndex),
                      next < endIndex,
                      self[next] == "n"
            {
                result.append("\n")
                index = self.index(after: next)
            } else {
                switch ch {
                case "{": result += replL
                case "}": result += replR
                default: result.append(ch)
                }
                index = self.index(after: index)
            }
        }
        return result
    }

    func replaceKutubCodes(with mapping: [String: String], mode: KutubMode = .normal) -> String {
        switch mode {
        case .normal:
            let pattern = #/\((.*?)\)/#
            return replacing(pattern) { match in
                let originalInside = String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)

                let codes = originalInside.split(separator: " ").map { String($0) }
                let mapped = codes.map { mapping[$0] ?? $0 }.joined(separator: ", ")

                return "(\(originalInside)) - (\(mapped))"
            }
        case .mulakhos:
            let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
            let codes = cleaned.split(separator: " ").map { String($0) }
            let mapped = codes.map { mapping[$0] ?? $0 }.joined(separator: ", ")

            return "\(cleaned) - (\(mapped))"
        }
    }

    private func replaceSingleAbbreviations(with mapping: [String: String]) -> String {
        guard !mapping.isEmpty else { return self }

        var result = ""
        var currentIndex = startIndex

        while currentIndex < endIndex {
            var matchFound = false
            for (key, value) in mapping where self[currentIndex...].hasPrefix(key) {
                result += value
                currentIndex = index(currentIndex, offsetBy: key.count)
                matchFound = true
                break
            }
            if !matchFound {
                result.append(self[currentIndex])
                currentIndex = index(after: currentIndex)
            }
        }

        return result
    }

    func replaceAllRowiMappings() -> String {
        let step1 = replaceKutubCodes(with: TabaqaGroup.mappingRowiKutub)
        let step2 = step1.replaceSingleAbbreviations(with: TabaqaGroup.replacementRowiMapping)
        return step2.convertToArabicDigits()
    }

    func convertedTabaqa() -> String {
        let formatter = StringExtCache.numberFormatter
        guard let regex = StringExtCache.tabaqaRegex else { return self }

        let ns = self as NSString
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: ns.length))

        var output = ""
        var lastIndex = 0

        for m in matches {
            let rangeBefore = NSRange(location: lastIndex, length: m.range.location - lastIndex)
            if rangeBefore.length > 0 {
                output += ns.substring(with: rangeBefore)
            }

            if m.range(at: 1).location != NSNotFound {
                output += "ﷺ"
            } else if m.range(at: 2).location != NSNotFound {
                let code = ns.substring(with: m.range(at: 2))
                output += TabaqaGroup.tabaqaMapping[code] ?? code
            } else if m.range(at: 3).location != NSNotFound {
                let numberStr = ns.substring(with: m.range(at: 3))
                let arabic = Int(numberStr).flatMap { formatter.string(from: NSNumber(value: $0)) }
                output += arabic ?? numberStr
            }

            lastIndex = m.range.location + m.range.length
        }

        if lastIndex < ns.length {
            output += ns.substring(from: lastIndex)
        }

        return output
    }

    func replaceSheok() -> String {
        let step1 = replaceSingleAbbreviations(with: TabaqaGroup.replacementSheokMapping)
        return step1.convertToArabicDigits()
    }
}
