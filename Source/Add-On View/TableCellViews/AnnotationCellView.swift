//
//  AnnotationCellView.swift
//  maktab
//
//  Created by MacBook on 16/12/25.
//

import Cocoa

class AnnotationCellView: NSTableCellView {
    @IBOutlet weak var note: NSTextField!
    @IBOutlet weak var context: NSTextField!
    @IBOutlet weak var date: NSTextField!
    @IBOutlet weak var pagePart: NSTextField!

    override func awakeFromNib() {
        super.awakeFromNib()
        context.maximumNumberOfLines = 2
        note.maximumNumberOfLines = 4
    }
}
