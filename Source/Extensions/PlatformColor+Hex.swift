//
//  PlatformColor+Hex.swift
//  Maktabah
//

#if canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#endif

#if canImport(AppKit) || canImport(UIKit)
import CoreGraphics

extension PlatformColor {
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

        #if os(macOS)
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
        #else
        self.init(red: r, green: g, blue: b, alpha: 1.0)
        #endif
    }

    func hexString() -> String {
        let defaultColor = "#FF9300"
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        #if os(macOS)
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return defaultColor }
        r = rgb.redComponent
        g = rgb.greenComponent
        b = rgb.blueComponent
        #else
        if !self.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return defaultColor
        }
        #endif

        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}
#endif
