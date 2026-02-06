//
//  Annotations.swift
//  annotations
//
//  Created by MacBook on 13/12/25.
//

import Cocoa

struct Annotation {
    var id: Int64?            // nil sebelum disimpan
    let bkId: Int             // book id
    let contentId: Int        // BookContent.id
    var range: NSRange        // NSRange berbasis UTF-16 (NSString)
    let rangeDiacritics: NSRange
    let colorHex: String      // "#RRGGBB"
    var type: AnnotationMode          // "highlight" atau "underline"
    let note: String?         // catatan opsional
    let createdAt: Int64      // timestamp
    let context: String       // Konteks yang dianotasi
    let page: Int
    let part: Int
    var pageArb: String?
    var partArb: String?
}

class AnnotationNode {
    var title: String
    var children: [AnnotationNode] = []
    var annotation: Annotation? // optional, kalau node ini representasi annotation

    init(title: String, annotation: Annotation? = nil) {
        self.title = title
        self.annotation = annotation
    }
}

struct ContentKey: Hashable {
    let bkId: Int
    let contentId: Int
}

enum AnnotationMode: Int {
    case highlight
    case underline

    static func from(int: Int) -> AnnotationMode {
        return switch int {
        case 0: highlight
        case 1: underline
        default: highlight
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return nil }
        let scanner = Scanner(string: s)
        var hexNum: UInt64 = 0
        guard scanner.scanHexInt64(&hexNum) else { return nil }
        let r = CGFloat((hexNum & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hexNum & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hexNum & 0x0000FF) / 255.0
        self.init(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }
}

extension NSImage {
    static func coloredCircle(color: NSColor, diameter: CGFloat = 14) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size)
        guard let alphaColor = color.highlight(withLevel: 0.5) else {
            return image
        }
        image.lockFocus()
        alphaColor.setFill()
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(ovalIn: rect)
        path.fill()
        image.unlockFocus()
        return image
    }
}
