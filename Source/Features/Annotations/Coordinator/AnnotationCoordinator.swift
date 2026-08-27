//
//  AnnotationCoordinator.swift
//  Maktabah
//
//  Created by MacBook on 27/01/26.
//

import Foundation

struct SaveHighlightParams {
    let text: String
    let range: NSRange
    let color: PlatformColor
    let bkId: Int
    let contentId: Int
    let page: Int
    let part: Int
    var diacriticsText: String? = nil
    var showHarakat: Bool = false
    var mode: AnnotationMode = .highlight
}

class AnnotationCoordinator {
    private let manager = AnnotationManager.shared

    /// Cari anotasi yang range-nya MATCH EXACTLY atau CONTAIN selection
    /// Prioritas: range yang paling kecil dulu (paling spesifik)
    func findAnnotation(
        at charIndex: Int,
        bkId: Int,
        contentId: Int,
        showHarakat: Bool
    ) -> Annotation? {
        let anns = manager.loadAnnotations(bkId: bkId, contentId: contentId)

        for ann in anns.reversed() {
            let range = showHarakat ? ann.rangeDiacritics : ann.range
            if NSLocationInRange(charIndex, range) {
                return ann
            }
        }

        return nil
    }

    func findBestAnnotation(
        overlapping selectionRange: NSRange,
        bkId: Int,
        contentId: Int,
        showHarakat: Bool
    ) -> Annotation? {
        let anns = manager.loadAnnotations(bkId: bkId, contentId: contentId)

        // Cari yang fully contain selection (paling spesifik)
        var candidates: [Annotation] = []

        for ann in anns {
            let range = showHarakat ? ann.rangeDiacritics : ann.range
            if range.contains(selectionRange) {
                candidates.append(ann)
            }
        }

        if !candidates.isEmpty {
            return candidates.min { ann1, ann2 in
                let r1 = showHarakat ? ann1.rangeDiacritics : ann1.range
                let r2 = showHarakat ? ann2.rangeDiacritics : ann2.range
                return r1.length < r2.length
            }
        }

        // Fallback: cari yang punya overlap terbesar
        return findLargestOverlap(in: anns, with: selectionRange, showHarakat: showHarakat)
    }

    @discardableResult
    func saveHighlight(_ params: SaveHighlightParams) throws -> Annotation {
        let calculator = ArabicRangeCalculator()
        let ranges = calculator.calculateRanges(
            for: params.range,
            in: params.text,
            selectedText: (params.text as NSString).substring(with: params.range),
            diacriticsText: params.diacriticsText,
            showHarakat: params.showHarakat
        )

        let hex = params.color.hexString()

        let ann = Annotation(
            id: nil,
            bkId: params.bkId,
            contentId: params.contentId,
            range: ranges.withoutDiacritics,
            rangeDiacritics: ranges.withDiacritics,
            colorHex: hex,
            type: params.mode,
            note: nil,
            createdAt: Int64(Date().timeIntervalSince1970),
            context: (params.text as NSString).substring(with: params.range),
            page: params.page,
            part: params.part,
            pageArb: String(params.page).convertToArabicDigits(),
            partArb: String(params.part).convertToArabicDigits()
        )

        try manager.addAnnotation(ann)
        return ann
    }

    // Similar methods for underline, note, delete...

    private func findLargestOverlap(
        in annotations: [Annotation],
        with range: NSRange,
        showHarakat: Bool
    ) -> Annotation? {
        var bestAnnotation: Annotation? = nil
        var bestOverlapLength = 0

        for ann in annotations {
            let annRange = showHarakat ? ann.rangeDiacritics : ann.range
            let intersection = NSIntersectionRange(annRange, range)

            guard intersection.length > 0 else { continue }

            if intersection.length > bestOverlapLength ||
               (intersection.length == bestOverlapLength && annRange.length < (bestAnnotation.flatMap { showHarakat ? $0.rangeDiacritics.length : $0.range.length } ?? Int.max)) {
                bestOverlapLength = intersection.length
                bestAnnotation = ann
            }
        }

        return bestAnnotation
    }
}

// ArabicRangeCalculator.swift - NEW FILE
struct ArabicRangeCalculator {
    func calculateRanges(
        for selection: NSRange,
        in text: String,
        selectedText: String,
        diacriticsText: String?,
        showHarakat: Bool
    ) -> (withDiacritics: NSRange, withoutDiacritics: NSRange) {

        if showHarakat {
            // Saat ini tampil dengan harakat
            let rangeWithDiacritics = selection
            let textNoDiac = text.normalizedForMatching()
            let rangeWithoutDiacritics = textNoDiac.calculateRangeWithoutHarakat(from: selection, in: text)

            return (rangeWithDiacritics, rangeWithoutDiacritics)
        } else {
            // Saat ini tampil tanpa harakat
            let rangeWithoutDiacritics = selection

            if let diacText = diacriticsText?.cleanedText() {
                let rangeWithDiacritics = diacText.findRangeInOriginal(
                    selectedText: selectedText,
                    approximateRange: selection
                )
                return (rangeWithDiacritics, rangeWithoutDiacritics)
            } else {
                return (selection, selection)
            }
        }
    }
}

// Helper extension
extension NSRange {
    func contains(_ other: NSRange) -> Bool {
        return self.location <= other.location &&
               self.location + self.length >= other.location + other.length
    }
}
