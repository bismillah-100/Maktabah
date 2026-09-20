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
        MainActor.assumeIsolated {
            imageView?.image = .init(systemSymbolName: "text.document.fill", accessibilityDescription: nil)
        }
    }

}
