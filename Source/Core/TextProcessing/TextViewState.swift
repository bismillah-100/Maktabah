//
//  TextViewState.swift
//  Maktabah
//
//  Created by MacBook on 27/01/26.
//

import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// TextViewState.swift - NEW FILE
#if os(iOS)
@Observable
#endif
class TextViewState {
    static let shared = TextViewState()

    private let defaults = UserDefaults.standard

    // MARK: - Published Properties
    private(set) var showHarakat: Bool {
        didSet {
            defaults.textViewShowHarakat = showHarakat
            NotificationCenter.default.post(name: .didChangeHarakat, object: nil, userInfo: ["on": showHarakat])
        }
    }

    // Tambahkan properti untuk gaya tebal/biru yang konsisten
    var boldAttributes: [NSAttributedString.Key: Any] {
        var attrs = defaultAttributes // Mulai dari defaultAttributes
        attrs[.font] = currentFont
        #if os(macOS)
        attrs[.foregroundColor] = NSColor(named: "HeaderColor") ?? NSColor.textColor
        #else
        attrs[.foregroundColor] = UIColor(named: "HeaderColor") ?? UIColor.label
        #endif
        // paragraphStyle sudah ada di defaultAttributes
        return attrs
    }

    private(set) var lineHeight: Double {
        didSet {
            defaults.lineHeight = lineHeight
            NotificationCenter.default.post(name: .didChangeLineHeight, object: nil)
        }
    }

    private(set) var fontSize: CGFloat {
        didSet {
            defaults.textViewFontSize = Float(fontSize)
            NotificationCenter.default.post(name: .didChangeFont, object: nil, userInfo: ["redraw": false])
        }
    }

    private(set) var fontName: String {
        didSet {
            defaults.textViewFontName = fontName
            let shouldRedraw = needsRedraw(oldFont: oldValue, newFont: fontName)
            NotificationCenter.default.post(name: .didChangeFont, object: nil, userInfo: ["redraw": shouldRedraw])
        }
    }
    
    private(set) var backgroundColorIndex: Int {
        didSet {
            defaults.textViewBackgroundColorLight = backgroundColorIndex
            NotificationCenter.default.post(name: .didChangeBackground, object: nil)
        }
    }
    
    private(set) var clickableAnnotation: Bool {
        didSet {
            defaults.enableAnnotationClick = clickableAnnotation
            NotificationCenter.default.post(name: .didChangeClickableAnnotation, object: nil,
                                            userInfo: ["enable": clickableAnnotation])
        }
    }

    // MARK: - Computed Properties
    var isDarkMode: Bool {
        backgroundColorIndex > 1
    }

    var currentFont: PlatformFont {
        PlatformFont(name: fontName, size: fontSize) ?? PlatformFont.systemFont(ofSize: fontSize)
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 2.0
        style.alignment = .right // Default ke kanan untuk aplikasi Maktabah
        style.baseWritingDirection = .rightToLeft
        style.lineHeightMultiple = lineHeight
        return style
    }

    var defaultAttributes: [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: currentFont,
            .paragraphStyle: paragraphStyle
        ]
        #if os(macOS)
        attrs[.foregroundColor] = NSColor.labelColor
        #else
        attrs[.foregroundColor] = UIColor.label
        #endif
        return attrs
    }

    // Default values
    let defaultFontName = "KFGQPC Uthman Taha Naskh" // Font bagus untuk Arab

    // MARK: - Init
    private init() {
        // Load dari UserDefaults
        self.showHarakat = defaults.textViewShowHarakat
        self.lineHeight = defaults.lineHeight

        let savedSize = defaults.textViewFontSize
        self.fontSize = savedSize > 0 ? CGFloat(savedSize) : 19.0

        self.fontName = defaults.textViewFontName
        self.backgroundColorIndex = defaults.textViewBackgroundColorLight
        self.clickableAnnotation = defaults.enableAnnotationClick
    }

    // MARK: - Public Methods
    func toggleHarakat() {
        showHarakat.toggle()
    }

    func setLineHeight(_ newHeight: Double) {
        lineHeight = newHeight
    }

    func setBackgroundColorIndex(_ index: Int) {
        backgroundColorIndex = index
    }

    func changeFontSize(by delta: CGFloat) {
        let minSize: CGFloat = 14.0
        let maxSize: CGFloat = 48.0
        let newSize = min(max(fontSize + delta, minSize), maxSize)
        fontSize = newSize
    }

    func setFont(_ name: String) {
        fontName = name
    }
    
    func setClickableAnnotation(_ enable: Bool) {
        clickableAnnotation = enable
    }

    /// Masukkan warna baru ke indeks 0. Duplikat dipindah ke depan. Maks 5.
    func pushRecentHighlightColor(_ color: PlatformColor) {
        var list = defaults.recentHighlightColors
        list.removeAll { colorApproxEqual($0, color) }
        list.insert(color, at: 0)
        defaults.recentHighlightColors = Array(list.prefix(UserDefaults.maxRecentColors))
    }

    private func colorApproxEqual(_ a: PlatformColor, _ b: PlatformColor) -> Bool {
        #if os(macOS)
        guard let ar = a.usingColorSpace(.deviceRGB),
            let br = b.usingColorSpace(.deviceRGB)
        else { return false }
        let t: CGFloat = 0.01
        return abs(ar.redComponent - br.redComponent) < t
            && abs(ar.greenComponent - br.greenComponent) < t
            && abs(ar.blueComponent - br.blueComponent) < t
        #else
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return false }
        let t: CGFloat = 0.01
        return abs(r1 - r2) < t && abs(g1 - g2) < t && abs(b1 - b2) < t
        #endif
    }

    func lastUsedColor() -> String {
        let color = defaults.recentHighlightColors.first
        return color?.hexString() ?? "#FF9300"
    }

    // MARK: - Helpers
    private func needsRedraw(oldFont: String, newFont: String) -> Bool {
        let isOldSpecial = oldFont == ArabicFont.alBayan.rawValue
        let isNewSpecial = newFont == ArabicFont.alBayan.rawValue
        return isOldSpecial != isNewSpecial
    }
}
