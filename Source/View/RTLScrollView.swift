//
//  RTLScrollView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 19/08/26.
//

import Cocoa

final class RTLScrollView: NSScrollView {
    /// Offset untuk merapatkan overlay scrollbar ke tepi kiri (menghilangkan padding internal AppKit)
    var leftOffset: CGFloat = 6

    override func tile() {
        super.tile()
        guard !MainWindow.rtl,
              hasVerticalScroller,
              let verticalScroller
        else { return }

        var scrollerFrame = verticalScroller.frame
        scrollerFrame.origin.x = scrollerStyle == .overlay ? -leftOffset : 0
        verticalScroller.frame = scrollerFrame

        if scrollerStyle == .legacy {
            var contentFrame = contentView.frame
            contentFrame.origin.x = scrollerFrame.width
            contentFrame.size.width = bounds.width - scrollerFrame.width
            contentView.frame = contentFrame
        }
    }
}
