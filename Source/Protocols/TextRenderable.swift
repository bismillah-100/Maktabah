//
//  TextRenderable.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 02/07/26.
//

import AppKit

struct IbarotTextOptions {
    var content: BookContent? = nil
    var color: NSColor? = nil
    var isMultiLanguage: Bool? = nil
    var isImported: Bool? = nil
    var keepScrollPosition: Bool? = nil
}

@MainActor
protocol TextViewRenderable: AnyObject {
    func loadIbarotText(
        _ text: String,
        options: IbarotTextOptions
    )

    func highlightAndScrollToAnns(_ ann: Annotation) async
    func highlightAndScrollToText(_ searchText: String, mode: SearchMode?, nearDistance: Int) async
    func scrollTo(_ scrollPos: CGPoint) async
}
