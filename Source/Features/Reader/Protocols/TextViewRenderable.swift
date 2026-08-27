//
//  TextViewRenderable.swift
//  Maktabah
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

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
