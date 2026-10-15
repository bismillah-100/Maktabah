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
}
