//
//  BundledArabicButton.swift
//  maktab
//

import Cocoa

final class BundledArabicButton: NSButton {
    override func awakeFromNib() {
        super.awakeFromNib()
        font = ReusableFunc.bundledArabicFont(
            ofSize: font?.pointSize ?? NSFont.systemFontSize
        )
    }
}
