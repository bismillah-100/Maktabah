//
//  BundledArabicTextField.swift
//  maktab
//

import Cocoa

final class BundledArabicTextField: NSTextField {
    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            font = ReusableFunc.bundledArabicFont(ofSize: font?.pointSize ?? 16)
        }
    }
}
