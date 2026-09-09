//
//  BundledArabicButton.swift
//  maktab
//

import Cocoa

final class BundledArabicButton: NSButton {
    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            font = ReusableFunc.bundledArabicFont(
                ofSize: font?.pointSize ?? NSFont.systemFontSize
            )
        }
    }
}
