//
//  TOCFuzzyMatchTests.swift
//  MaktabahTests
//

import Foundation
@testable import Maktabah_Debug
import Testing

struct TOCFuzzyMatchTests {
    @Test("Direct match at paragraph start")
    func testDirectMatchAtParagraphStart() {
        let text = """
        هذا كلام تمهيدي في أول الصفحة.
        باب الوضوء
        اعلم أن الوضوء شرط لصحة الصلاة.
        """
        let range = text.findTOCMatchingRange(title: "باب الوضوء")
        #expect(range != nil)
        if let range {
            let matched = (text as NSString).substring(with: range)
            #expect(matched == "باب الوضوء")
        }
    }

    @Test("Match prefers paragraph start over middle of sentence")
    func testPrefersParagraphStartOverMiddle() {
        let text = """
        قال المصنف وذكرنا باب الوضوء في موضع آخر.
        
        باب الوضوء
        هو استعمال الماء في أعضاء مخصوصة.
        """
        let range = text.findTOCMatchingRange(title: "باب الوضوء")
        #expect(range != nil)
        if let range {
            // Should match the second one (at paragraph start), which is after the newline
            let prefix = (text as NSString).substring(with: NSRange(location: 0, length: range.location))
            #expect(prefix.contains("قال المصنف"))
            #expect(prefix.hasSuffix("\n\n"))
        }
    }

    @Test("Fallback to match anywhere when no paragraph start match exists")
    func testFallbackToAnywhere() {
        let text = "وفي أثناء المسألة قال باب الوضوء ثم استطرد."
        let range = text.findTOCMatchingRange(title: "باب الوضوء")
        #expect(range != nil)
        if let range {
            let matched = (text as NSString).substring(with: range)
            #expect(matched == "باب الوضوء")
        }
    }

    @Test("Fallback to prefix words when title is longer than text heading")
    func testPrefixFallback() {
        let text = """
        فصل في أحكام المياه
        الماء قسمان طاهر ونجس.
        """
        // Title in TOC is longer
        let range = text.findTOCMatchingRange(title: "فصل في أحكام المياه وتفصيل أقسامها وأعيانها")
        #expect(range != nil)
        if let range {
            let matched = (text as NSString).substring(with: range)
            #expect(matched == "فصل في أحكام")
        }
    }

    @Test("Diacritics tolerance in matching")
    func testDiacriticsTolerance() {
        let text = "بَابُ الوُضُوءِ\nتَفْصِيلُ الْأَحْكَامِ"
        let range = text.findTOCMatchingRange(title: "باب الوضوء")
        #expect(range != nil)
    }

    @Test("Returns nil when no match found")
    func testNoMatchReturnsNil() {
        let text = "كتاب الصلاة وأوقاتها"
        let range = text.findTOCMatchingRange(title: "باب الزكاة")
        #expect(range == nil)
    }
}
