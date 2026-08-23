//
//  RightAlignedClipView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 16/08/26.
//

import Cocoa

final class RightAlignedClipView: NSClipView {
    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        updateDocumentFrame()
    }

    func updateDocumentFrame() {
        guard let docView = documentView as? NSStackView else { return }
        docView.invalidateIntrinsicContentSize()
        docView.layoutSubtreeIfNeeded()
        let fittingWidth = docView.fittingSize.width
        let clipWidth = bounds.width
        guard clipWidth > 0 else { return }
        let insets = contentInsets
        let availableWidth = max(0, clipWidth - insets.left - insets.right)
        let targetWidth = max(availableWidth, fittingWidth)
        if docView.frame.width != targetWidth || docView.frame.height != bounds.height {
            docView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: bounds.height)
        }
        docView.layoutSubtreeIfNeeded()
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let docView = documentView else { return rect }

        let insets = contentInsets
        let docWidth = docView.frame.width
        let clipWidth = bounds.width
        let minX = -insets.left
        let maxX = max(minX, docWidth - clipWidth + insets.right)

        rect.origin.x = min(maxX, max(minX, rect.origin.x))
        return rect
    }
}
