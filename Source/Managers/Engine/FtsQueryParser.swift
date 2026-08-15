//
//  FtsQueryParser.swift
//  Maktabah
//
//  Created by Antigravity on 07/08/26.
//

import Foundation

struct FtsQueryParser {
    /// Builds a safe, normalized, and stemmed FTS5 MATCH query string.
    static func buildFtsQuery(query: String, mode: SearchMode, nearDistance: Int = 10) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Check if user manually typed explicit NEAR syntax regardless of mode
        if hasExplicitNearSyntax(trimmed) {
            if let nearQuery = parseExplicitNearSyntax(trimmed, fallbackDistance: nearDistance) {
                return nearQuery
            }
        }

        let distance = max(1, nearDistance)

        switch mode {
        case .phrase:
            let terms = extractCleanTerms(trimmed)
            guard !terms.isEmpty else { return "" }
            return "\"" + terms.joined(separator: " ") + "\""

        case .contains:
            let terms = extractCleanTerms(trimmed)
            guard !terms.isEmpty else { return "" }
            return terms.map { "\"\($0)\"" }.joined(separator: " AND ")

        case .or:
            let terms = extractCleanTerms(trimmed)
            guard !terms.isEmpty else { return "" }
            return terms.map { "\"\($0)\"" }.joined(separator: " OR ")

        case .near:
            let terms = extractCleanTerms(trimmed)
            guard !terms.isEmpty else { return "" }
            if terms.count == 1 {
                return "\"\((terms.first!))\""
            }
            let joinedTerms = terms.map { "\"\($0)\"" }.joined(separator: " ")
            return "NEAR(\(joinedTerms), \(distance))"
        }
    }

    /// Extracts clean, normalized, and stemmed keywords for snippet highlighting.
    static func extractKeywords(query: String, mode: SearchMode) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Strip explicit NEAR tokens to leave actual search words
        let cleanedQuery = trimmed
            .replacingOccurrences(of: #"NEAR(/\d+)?|\bNEAR\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"[(),'"]"#, with: " ", options: .regularExpression)

        let rawTerms = cleanedQuery.components(separatedBy: CharacterSet(charactersIn: ",\n\t "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizeArabic() }
            .filter { !$0.isEmpty }

        switch mode {
        case .phrase:
            if !rawTerms.isEmpty {
                return [rawTerms.joined(separator: " ")]
            }
            return []
        case .contains, .or, .near:
            return rawTerms
        }
    }

    /// Extracts the NEAR distance from the query if it contains explicit NEAR syntax.
    static func extractNearDistance(query: String) -> Int? {
        let pattern = #"(?i)(?:NEAR\s*\(\s*[^,\)]+(?:,\s*(\d+))?\s*\)|[^\s]+\s+NEAR(?:/(\d+))?\s+[^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        
        let nsText = query as NSString
        if let match = regex.firstMatch(in: query, options: [], range: NSRange(location: 0, length: nsText.length)) {
            if match.range(at: 1).location != NSNotFound, let k = Int(nsText.substring(with: match.range(at: 1))) {
                return k
            } else if match.range(at: 2).location != NSNotFound, let k = Int(nsText.substring(with: match.range(at: 2))) {
                return k
            }
        }
        return nil
    }

    // MARK: - Private Helpers

    private static func hasExplicitNearSyntax(_ text: String) -> Bool {
        let upper = text.uppercased()
        return upper.contains("NEAR/") || upper.contains("NEAR")
    }

    private static func parseExplicitNearSyntax(_ text: String, fallbackDistance: Int) -> String? {
        let pattern = #"(?i)(?:NEAR\s*\(\s*([^,\)]+)(?:,\s*(\d+))?\s*\)|([^\s]+(?:\s+[^\s]+)*?)\s+NEAR(?:/(\d+))?\s+([^\s]+(?:\s+[^\s]+)*))"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        if let match = matches.first {
            var distance = fallbackDistance
            var words: [String] = []

            if match.range(at: 1).location != NSNotFound {
                // Format: NEAR(term1 term2 ..., k)
                let termStr = nsText.substring(with: match.range(at: 1))
                if match.range(at: 2).location != NSNotFound,
                   let k = Int(nsText.substring(with: match.range(at: 2))) {
                    distance = k
                }
                words = extractCleanTerms(termStr)
            } else if match.range(at: 3).location != NSNotFound && match.range(at: 5).location != NSNotFound {
                // Format: wordA NEAR/k wordB
                let leftStr = nsText.substring(with: match.range(at: 3))
                let rightStr = nsText.substring(with: match.range(at: 5))
                if match.range(at: 4).location != NSNotFound,
                   let k = Int(nsText.substring(with: match.range(at: 4))) {
                    distance = k
                }
                let leftTerms = extractCleanTerms(leftStr)
                let rightTerms = extractCleanTerms(rightStr)
                words = leftTerms + rightTerms
            }

            distance = max(1, distance)

            guard !words.isEmpty else { return nil }
            if words.count == 1 {
                return "\"\((words.first!))\""
            }

            let joined = words.map { "\"\($0)\"" }.joined(separator: " ")
            return "NEAR(\(joined), \(distance))"
        }

        // Fallback: If syntax couldn't be parsed strictly (e.g. malformed NEAR), extract clean words and format safely
        let cleanTerms = extractCleanTerms(text)
        guard !cleanTerms.isEmpty else { return nil }
        if cleanTerms.count >= 2 {
            let joined = cleanTerms.map { "\"\($0)\"" }.joined(separator: " ")
            return "NEAR(\(joined), \(max(1, fallbackDistance)))"
        } else {
            return "\"\((cleanTerms.first!))\""
        }
    }

    private static func extractCleanTerms(_ text: String) -> [String] {
        // Remove NEAR keywords, punctuation, and FTS operators
        let sanitized = text
            .replacingOccurrences(of: #"NEAR(/\d+)?|\bNEAR\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"[^\w\s\u0600-\u06FF]"#, with: " ", options: .regularExpression)

        return sanitized.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).normalizeArabic().stemArabicLight10() }
            .filter { !$0.isEmpty }
    }
}
