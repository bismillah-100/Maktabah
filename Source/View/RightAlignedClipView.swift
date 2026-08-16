//
//  RightAlignedClipView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 16/08/26.
//


import Cocoa

final class RightAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        updateDocumentFrame()
    }

    func updateDocumentFrame() {
        guard let docView = documentView as? NSStackView else { return }
        let fittingWidth = docView.fittingSize.width
        let clipWidth = bounds.width
        guard clipWidth > 0 else { return }
        let targetWidth = max(clipWidth, fittingWidth)
        if docView.frame.width != targetWidth || docView.frame.height != bounds.height {
            docView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: bounds.height)
        }
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let docView = documentView else { return rect }

        let docWidth = docView.frame.width
        let clipWidth = bounds.width

        if docWidth <= clipWidth {
            rect.origin.x = 0
        } else {
            let maxX = docWidth - clipWidth
            rect.origin.x = min(maxX, max(0, rect.origin.x))
        }
        return rect
    }
}
