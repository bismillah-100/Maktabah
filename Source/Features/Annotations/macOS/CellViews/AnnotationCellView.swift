//
//  AnnotationCellView.swift
//  maktab
//
//  Created by MacBook on 16/12/25.
//

import Cocoa

class AnnotationCellView: NSTableCellView {
    static let pagePartLineLimit = 2

    @IBOutlet weak var note: NSTextField!
    @IBOutlet weak var context: NSTextField!
    @IBOutlet weak var date: NSTextField!
    @IBOutlet weak var pagePart: NSTextField!

    override func awakeFromNib() {
        super.awakeFromNib()
        applyLineLimits()
    }

    func applyLineLimits() {
        note.maximumNumberOfLines = UserDefaults.standard.annMaxNumberOfLines
        context.maximumNumberOfLines = UserDefaults.standard.ctxMaxNumberOfLines
        pagePart.maximumNumberOfLines = Self.pagePartLineLimit
    }
}
