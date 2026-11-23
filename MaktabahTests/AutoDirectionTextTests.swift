//
//  AutoDirectionTextTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 21/11/26.
//

import AppKit
import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("Auto Direction Paragraph Tests")
struct AutoDirectionTextTests {
    @Test("Single RTL and LTR paragraphs receive matching alignment and writing direction")
    func testSingleParagraphDirections() {
        let font = NSFont.systemFont(ofSize: 15)
        let rtlAttr = NSAttributedString.autoDirectionString("بسم الله الرحمن الرحيم", font: font, color: .labelColor)
        let rtlStyle = rtlAttr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(rtlStyle?.alignment == .right)
        #expect(rtlStyle?.baseWritingDirection == .rightToLeft)

        let ltrAttr = NSAttributedString.autoDirectionString("Catatan penting bahasa Indonesia", font: font, color: .labelColor)
        let ltrStyle = ltrAttr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(ltrStyle?.alignment == .left)
        #expect(ltrStyle?.baseWritingDirection == .leftToRight)
    }

    @Test("Mixed multi-paragraph text applies direction per paragraph")
    func testMixedMultiParagraphDirections() {
        let text = "الفقرة الأولى عربية\nCatatan kedua bahasa Indonesia\n123 - الفقرة الثالثة"
        let mutable = NSMutableAttributedString(string: text)
        mutable.applyAutoDirectionAlignments(font: NSFont.systemFont(ofSize: 15), color: .labelColor)

        let nsText = text as NSString
        let firstLoc = 0
        let secondLoc = nsText.range(of: "Catatan").location
        let thirdLoc = nsText.range(of: "123").location

        let firstStyle = mutable.attribute(.paragraphStyle, at: firstLoc, effectiveRange: nil) as? NSParagraphStyle
        let secondStyle = mutable.attribute(.paragraphStyle, at: secondLoc, effectiveRange: nil) as? NSParagraphStyle
        let thirdStyle = mutable.attribute(.paragraphStyle, at: thirdLoc, effectiveRange: nil) as? NSParagraphStyle

        #expect(firstStyle?.alignment == .right)
        #expect(firstStyle?.baseWritingDirection == .rightToLeft)

        #expect(secondStyle?.alignment == .left)
        #expect(secondStyle?.baseWritingDirection == .leftToRight)

        #expect(thirdStyle?.alignment == .right)
        #expect(thirdStyle?.baseWritingDirection == .rightToLeft)
    }

    @Test("Trailing empty newline inherits previous paragraph direction for typing attributes")
    func testTypingAttributesTrailingNewline() {
        let rtlTrailing = "نص عربي\n"
        let rtlStyle = NSParagraphStyle.autoDirection(for: rtlTrailing, at: (rtlTrailing as NSString).length)
        #expect(rtlStyle.alignment == .right)
        #expect(rtlStyle.baseWritingDirection == .rightToLeft)

        let ltrTrailing = "Catatan Latin\n"
        let ltrStyle = NSParagraphStyle.autoDirection(for: ltrTrailing, at: (ltrTrailing as NSString).length)
        #expect(ltrStyle.alignment == .left)
        #expect(ltrStyle.baseWritingDirection == .leftToRight)

        let emptyStyle = NSParagraphStyle.autoDirection(for: "", at: 0)
        #expect(emptyStyle.alignment == .right)
        #expect(emptyStyle.baseWritingDirection == .rightToLeft)
    }

    @Test("Existing RTL paragraph style updates to LTR when first strong letter becomes Latin")
    func testOverwritesExistingParagraphDirection() {
        let rtlStyle = NSMutableParagraphStyle()
        rtlStyle.alignment = .right
        rtlStyle.baseWritingDirection = .rightToLeft

        let mutable = NSMutableAttributedString(string: "hello", attributes: [.paragraphStyle: rtlStyle])
        mutable.applyAutoDirectionAlignments(font: NSFont.systemFont(ofSize: 15))

        let updated = mutable.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(updated?.alignment == .left)
        #expect(updated?.baseWritingDirection == .leftToRight)
    }
}
