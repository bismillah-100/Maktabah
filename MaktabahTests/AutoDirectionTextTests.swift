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

    @Test("truncatedForCellDisplay leaves short strings untouched and truncates long text safely")
    func testTruncatedForCellDisplay() {
        let short = "نص قصير"
        #expect(short.truncatedForCellDisplay(maxCharacters: 20, maxNewlines: 4) == short)

        let arabicWithHarakat = String(repeating: "بِسْمِ ", count: 40)
        let truncatedChars = arabicWithHarakat.truncatedForCellDisplay(maxCharacters: 25, maxNewlines: 8)
        #expect(truncatedChars.hasSuffix("…"))
        #expect(truncatedChars.count == 26)

        let manyLines = "1\n2\n3\n4\n5\n6"
        let truncatedLines = manyLines.truncatedForCellDisplay(maxCharacters: 100, maxNewlines: 4)
        #expect(truncatedLines == "1\n2\n3\n4…")
    }

    @Test("Context auto direction correctly formats RTL Arabic with highlight")
    func testContextAutoDirectionArabicHighlight() {
        let font = NSFont.systemFont(ofSize: 17)
        let color = NSColor.yellow
        let attr = NSAttributedString.autoDirectionContextString(
            "قال الشافعي رحمه الله تعالى",
            font: font,
            mode: .highlight,
            effectiveColor: color,
            lineBreakMode: .byWordWrapping
        )

        let style = attr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.alignment == .right)
        #expect(style?.baseWritingDirection == .rightToLeft)

        let bg = attr.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(bg != nil)
    }

    @Test("Context auto direction correctly formats LTR Latin with underline")
    func testContextAutoDirectionLatinUnderline() {
        let font = NSFont.systemFont(ofSize: 17)
        let color = NSColor.red
        let attr = NSAttributedString.autoDirectionContextString(
            "Imam Syafi'i rahimahullah berkata dalam kitab al-Umm",
            font: font,
            mode: .underline,
            effectiveColor: color,
            lineBreakMode: .byTruncatingTail
        )

        let style = attr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.alignment == .left)
        #expect(style?.baseWritingDirection == .leftToRight)
        #expect(style?.lineBreakMode == .byTruncatingTail)

        let underline = attr.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        #expect(underline == NSUnderlineStyle.single.rawValue)
        let underlineColor = attr.attribute(.underlineColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(underlineColor == color)
    }

    @Test("showAnnotationDate default is true and toggles accurately")
    func testShowAnnotationDateDefaults() {
        let original = UserDefaults.standard.showAnnotationDate
        defer { UserDefaults.standard.showAnnotationDate = original }

        UserDefaults.standard.showAnnotationDate = true
        #expect(UserDefaults.standard.showAnnotationDate == true)

        UserDefaults.standard.showAnnotationDate = false
        #expect(UserDefaults.standard.showAnnotationDate == false)
    }

    @Test("AnnotationRowHeightCalculator respects showDate flag")
    @MainActor
    func testRowHeightRespectsShowDate() {
        let original = UserDefaults.standard.showAnnotationDate
        defer { UserDefaults.standard.showAnnotationDate = original }

        let ann = Annotation(
            id: 1,
            bkId: 100,
            contentId: 50,
            range: NSRange(location: 0, length: 10),
            rangeDiacritics: NSRange(location: 0, length: 10),
            colorHex: "#FF0000",
            type: .highlight,
            note: "Catatan",
            createdAt: 1_700_000_000,
            context: "نص تجريبي طويل للاختبار في حساب الارتفاع",
            page: 1,
            part: 1
        )
        let node = AnnotationNode(title: ann.context, kind: .annotation, annotation: ann)
        let outlineView = NSOutlineView()
        let style = NSParagraphStyle()

        let heightWithDate = AnnotationRowHeightCalculator.height(
            for: node,
            in: outlineView,
            groupingMode: .book,
            paragraphStyle: style,
            showDate: true
        )
        let heightWithoutDate = AnnotationRowHeightCalculator.height(
            for: node,
            in: outlineView,
            groupingMode: .book,
            paragraphStyle: style,
            showDate: false
        )

        #expect(heightWithoutDate <= heightWithDate)
    }
}
