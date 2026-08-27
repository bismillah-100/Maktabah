//
//  IbarotTextOptions.swift
//  Maktabah
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct IbarotTextOptions {
    var content: BookContent? = nil
    #if canImport(AppKit)
    var color: NSColor? = nil
    #elseif canImport(UIKit)
    var color: UIColor? = nil
    #endif
    var isMultiLanguage: Bool? = nil
    var isImported: Bool? = nil
    var keepScrollPosition: Bool? = nil
}
