//
//  DataModel.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

#if canImport(AppKit)
import AppKit
#endif
import Foundation

// MARK: - TOC dengan Children (untuk NSOutlineView)

class TOCNode: Identifiable {
    let bab: String
    let level: Int
    let sub: Int
    let id: Int
    var children: [TOCNode] = []

    var endID: Int = .max

    init(from toc: TOC) {
        bab = toc.bab.convertToArabicDigits()
        level = toc.level
        sub = toc.sub
        id = toc.id
    }
}

struct TOC {
    let bab: String // Memetakan ke kolom 'tit'
    let level: Int // Memetakan ke kolom 'lvl'
    let sub: Int
    let id: Int
}

struct CleanedTextKey: Hashable {
    let showHarakat: Bool
    let isMultiLanguage: Bool
    let isImported: Bool
}

final class ProcessedArabicContent {
    let sourceText: String
    let displayText: String
    let coloredRanges: [NSRange]
    let footnoteRanges: [NSRange]
    let replacementEvents: [HonorificReplacementEvent]
    let importedHeaderRanges: [NSRange]
    let ligatureRanges: [NSRange]

    init(
        sourceText: String,
        displayText: String,
        coloredRanges: [NSRange],
        footnoteRanges: [NSRange],
        replacementEvents: [HonorificReplacementEvent],
        importedHeaderRanges: [NSRange],
        ligatureRanges: [NSRange]
    ) {
        self.sourceText = sourceText
        self.displayText = displayText
        self.coloredRanges = coloredRanges
        self.footnoteRanges = footnoteRanges
        self.replacementEvents = replacementEvents
        self.importedHeaderRanges = importedHeaderRanges
        self.ligatureRanges = ligatureRanges
    }
}

class BookContent {
    let id: Int
    let nash: String
    let page: Int
    let part: Int

    var surah: Int?
    var aya: Int?

    init(id: Int, nash: String, page: Int = 1, part: Int = 1) {
        self.id = id
        self.nash = nash
        self.page = page
        self.part = part
    }
}


