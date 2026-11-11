//
//  ArabicRangeCalculatorTests.swift
//  MaktabahTests
//

import Foundation
@testable import Maktabah_Debug
import Testing

struct ArabicRangeCalculatorTests {
    let calculator = ArabicRangeCalculator()

    @Test("Mode dengan harakat: menghitung range tanpa harakat dari selection")
    func testCalculateRange_whenShowingHarakat() {
        let textWithHarakat = "بِسْمِ اللَّهِ"
        let selection = (textWithHarakat as NSString).range(of: "اللَّهِ")

        let result = calculator.calculateRanges(
            for: selection,
            in: textWithHarakat,
            selectedText: "اللَّهِ",
            diacriticsText: textWithHarakat,
            showHarakat: true
        )

        #expect(result.withDiacritics == selection)
        let extractedWithoutHarakat = (textWithHarakat.removingHarakat() as NSString).substring(with: result.withoutDiacritics)
        #expect(extractedWithoutHarakat == "الله")
    }

    @Test("Mode tanpa harakat: duplikasi kata yang sama di satu halaman memilih instance yang tepat")
    func testDuplicateWords_selectCorrectOccurrence() {
        let diacriticsText = "هَذَا كِتَابٌ مُفِيدٌ وَذَلِكَ كِتَابٌ آخَرُ"
        let plainText = diacriticsText.removingHarakat()

        // Kemunculan 1
        let firstPlain = (plainText as NSString).range(of: "كتاب")
        let firstDiac = (diacriticsText as NSString).range(of: "كِتَابٌ")

        let result1 = calculator.calculateRanges(
            for: firstPlain,
            in: plainText,
            selectedText: "كتاب",
            diacriticsText: diacriticsText,
            showHarakat: false
        )
        #expect(result1.withoutDiacritics == firstPlain)
        #expect(result1.withDiacritics == firstDiac)

        // Kemunculan 2 (options: .backwards langsung mengambil kemunculan terakhir dari teks)
        let secondPlain = (plainText as NSString).range(of: "كتاب", options: .backwards)
        let secondDiac = (diacriticsText as NSString).range(of: "كِتَابٌ", options: .backwards)

        let result2 = calculator.calculateRanges(
            for: secondPlain,
            in: plainText,
            selectedText: "كتاب",
            diacriticsText: diacriticsText,
            showHarakat: false
        )
        #expect(result2.withoutDiacritics == secondPlain)
        #expect(result2.withDiacritics == secondDiac)
    }

    @Test("Duplikasi kata di awal dan akhir teks tetap akurat")
    func testDuplicateWords_atBoundaries() {
        let diacriticsText = "قَالَ الْعَالِمُ كَلَامًا ثُمَّ قَالَ"
        let plainText = diacriticsText.removingHarakat()

        let firstPlain = (plainText as NSString).range(of: "قال")
        let firstDiac = (diacriticsText as NSString).range(of: "قَالَ")

        let lastPlain = (plainText as NSString).range(of: "قال", options: .backwards)
        let lastDiac = (diacriticsText as NSString).range(of: "قَالَ", options: .backwards)

        let resFirst = calculator.calculateRanges(
            for: firstPlain,
            in: plainText,
            selectedText: "قال",
            diacriticsText: diacriticsText,
            showHarakat: false
        )
        #expect(resFirst.withDiacritics == firstDiac)

        let resLast = calculator.calculateRanges(
            for: lastPlain,
            in: plainText,
            selectedText: "قال",
            diacriticsText: diacriticsText,
            showHarakat: false
        )
        #expect(resLast.withDiacritics == lastDiac)
    }

    @Test("Span tag aya-<number> dihapus dan jika ada teks diberi warna saat render")
    func testAyaSpanTags_strippedAndColored() {
        let rawText = "نعت منصوب.<span id=\"aya-٢٠٥٣\"></span><span data-type=\"title\">{وَاِخْفِضْ لَهُما}</span> الإعراب"
        let (cleanedText, headerRanges) = rawText.stripSpanTagsWithRanges()
        #expect(!cleanedText.contains("aya-٢٠٥٣"))
        #expect(!cleanedText.contains("<span"))
        #expect(cleanedText.contains("{وَاِخْفِضْ لَهُما}"))
        #expect(headerRanges.count == 1)

        let renderer = ArabicTextRenderer()
        let result = renderer.render(
            text: rawText,
            showHarakat: true,
            isImported: true
        )
        #expect(!result.attributedString.string.contains("aya-٢٠٥٣"))
        #expect(!result.attributedString.string.contains("<span"))

        let rawTextWithInner = "<span id=\"aya-٢٠٥٣\">بِسْمِ اللَّهِ</span>"
        let (cleanedInner, innerRanges) = rawTextWithInner.stripSpanTagsWithRanges()
        #expect(cleanedInner == "بِسْمِ اللَّهِ")
        #expect(innerRanges.count == 1)
        #expect(innerRanges.first == NSRange(location: 0, length: (cleanedInner as NSString).length))

        let selfClosingWithNextSpan = "نعت منصوب.<span id=\"aya-٢٠٥٣\"/> <span data-type=\"title\">{وَاِخْفِضْ لَهُما}</span> الإعراب"
        let (cleanedSC, rangesSC) = selfClosingWithNextSpan.stripSpanTagsWithRanges()
        #expect(cleanedSC == "نعت منصوب. {وَاِخْفِضْ لَهُما} الإعراب")
        #expect(rangesSC.count == 1)

        let selfClosingWithSpace = "نعت منصوب.<span id=\"aya-٢٠٥٣\" / > <span data-type=\"title\">{وَاِخْفِضْ لَهُما}</span> الإعراب"
        let (cleanedSCS, rangesSCS) = selfClosingWithSpace.stripSpanTagsWithRanges()
        #expect(cleanedSCS == "نعت منصوب. {وَاِخْفِضْ لَهُما} الإعراب")
        #expect(rangesSCS.count == 1)
    }

    @Test("Nested title spans di-strip bersih dan header range dihitung tepat")
    func testNestedTitleSpans() {
        let rawIdentical = "<span data-type='title' id=toc-55><span data-type='title' id=toc-56>الْعَمَلُ فِي اخْتِلَافِ الرِّوَايَاتِ</span></span>"
        let (cleanedIdentical, rangesIdentical) = rawIdentical.stripSpanTagsWithRanges()
        #expect(cleanedIdentical == "الْعَمَلُ فِي اخْتِلَافِ الرِّوَايَاتِ")
        #expect(!cleanedIdentical.contains("<span"))
        #expect(!cleanedIdentical.contains("</span>"))
        #expect(rangesIdentical.count == 1)
        #expect(rangesIdentical.first == NSRange(location: 0, length: (cleanedIdentical as NSString).length))

        let rawPartial = "<span data-type='title' id=toc-147>ثالثاً: متكلمة الصفاتية <span data-type='title' id=toc-148>(الكلابية </span>-الأشاعرة -الماتريدي</span>"
        let (cleanedPartial, rangesPartial) = rawPartial.stripSpanTagsWithRanges()
        #expect(cleanedPartial == "ثالثاً: متكلمة الصفاتية (الكلابية -الأشاعرة -الماتريدي")
        #expect(!cleanedPartial.contains("<span"))
        #expect(!cleanedPartial.contains("</span>"))
        #expect(rangesPartial.count == 1)
        #expect(rangesPartial.first == NSRange(location: 0, length: (cleanedPartial as NSString).length))
    }

    @Test("Span id=b-* penanda hadits/bookmark di-strip total tanpa meninggalkan spasi ganda")
    func testSpanIdB_stripped() {
        let rawStart = "<span id=\"b-١\"> </span>بسم الله الرحمن الرحيم"
        let (cleanedStart, rangesStart) = rawStart.stripSpanTagsWithRanges()
        #expect(cleanedStart == "بسم الله الرحمن الرحيم")
        #expect(rangesStart.isEmpty)

        let rawHadith = "١٣ - <span id=\"b-١٥\"> </span>قال رَضِيَ اللهُ عَنْهُ"
        let (cleanedHadith, rangesHadith) = rawHadith.stripSpanTagsWithRanges()
        #expect(cleanedHadith == "١٣ - قال رَضِيَ اللهُ عَنْهُ")
        #expect(rangesHadith.isEmpty)
    }

    @Test("Anchor dan tag lain di dalam title span di-strip namun teks dalamnya tetap masuk header")
    func testAnchorInsideTitleSpan() {
        let raw = "<span data-type=\"title\">Surah <a href=\"inr://123\">Al-Baqarah</a></span>"
        let (cleaned, ranges) = raw.stripSpanTagsWithRanges()
        #expect(cleaned == "Surah Al-Baqarah")
        #expect(!cleaned.contains("<a"))
        #expect(ranges.count == 1)
        #expect(ranges.first == NSRange(location: 0, length: (cleaned as NSString).length))
    }
}
