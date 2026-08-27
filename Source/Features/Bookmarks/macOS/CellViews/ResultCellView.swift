//
//  ResultCellView.swift
//  Maktabah
//
//  Created by MacBook on 23/04/26.
//

import Cocoa

class ResultCellView: NSTableCellView {

    override func awakeFromNib() {
        super.awakeFromNib()
        if #available(macOS 15, *) {
            imageView?.image = .init(systemSymbolName: "text.document.fill", accessibilityDescription: nil)
        } else {
            imageView?.image = .init(systemSymbolName: "doc.text.fill", accessibilityDescription: nil)
        }
    }

}
