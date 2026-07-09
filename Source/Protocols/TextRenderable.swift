//
//  TextRenderable.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 02/07/26.
//

import AppKit

@MainActor
protocol TextViewRenderable: AnyObject {
    func loadIbarotText(
        _ text: String,
        color: NSColor?,
        isMultiLanguage: Bool?,
        isImported: Bool?,
        keepScrollPosition: Bool?
    )

    func highlightAndScrollToAnns(_ ann: Annotation) async
    func highlightAndScrollToText(_ searchText: String) async
    func scrollTo(_ scrollPos: CGPoint) async
}
