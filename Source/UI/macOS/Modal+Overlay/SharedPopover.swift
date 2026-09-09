//
//  SharedPopover.swift
//  maktab
//
//  Created by MacBook on 19/12/25.
//

import Cocoa

@MainActor
final class SharedPopover {
    static weak var annotationsVC: AnnotationsVC?
    static let annotationsPopover: NSPopover = {
        let pop = NSPopover()
        pop.behavior = .transient
        return pop
    }()
}
