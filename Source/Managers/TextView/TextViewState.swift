//
//  TextViewState.swift
//  Maktabah
//
//  Created by MacBook on 27/01/26.
//

import Foundation
import Cocoa

// TextViewState.swift - NEW FILE
class TextViewState: ObservableObject {
    static let shared = TextViewState()

    private let defaults = UserDefaults.standard

    // MARK: - Published Properties
    @Published private(set) var showHarakat: Bool {
        didSet {
            defaults.textViewShowHarakat = showHarakat
            NotificationCenter.default.post(name: .didChangeHarakat, object: nil, userInfo: ["on": showHarakat])
        }
    }

    // Tambahkan properti untuk gaya tebal/biru yang konsisten
    var boldAttributes: [NSAttributedString.Key: Any] {
        var attrs = defaultAttributes // Mulai dari defaultAttributes
        attrs[.font] = currentFont
        attrs[.foregroundColor] = NSColor.header
        // paragraphStyle sudah ada di defaultAttributes
        return attrs
    }

    @Published private(set) var lineHeight: Double {
        didSet {
            defaults.lineHeight = lineHeight
            NotificationCenter.default.post(name: .didChangeLineHeight, object: nil)
        }
    }

    @Published private(set) var fontSize: CGFloat {
        didSet {
            defaults.set(Float(fontSize), forKey: UserDefaults.TextViewKeys.fontSize)
            NotificationCenter.default.post(name: .didChangeFont, object: nil, userInfo: ["redraw": false])
        }
    }

    @Published private(set) var fontName: String {
        didSet {
            defaults.set(fontName, forKey: UserDefaults.TextViewKeys.fontName)
            let shouldRedraw = needsRedraw(oldFont: oldValue, newFont: fontName)
            NotificationCenter.default.post(name: .didChangeFont, object: nil, userInfo: ["redraw": shouldRedraw])
        }
    }
    
    @Published private(set) var clickableAnnotation: Bool {
        didSet {
            defaults.set(clickableAnnotation, forKey: UserDefaults.TextViewKeys.annotationClick)
            NotificationCenter.default.post(name: .didChangeClickableAnnotation, object: nil,
                                            userInfo: ["enable": clickableAnnotation])
        }
    }

    // MARK: - Computed Properties
    var currentFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 2.0
        style.baseWritingDirection = .rightToLeft
        style.lineHeightMultiple = lineHeight
        return style
    }

    var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: currentFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    // Default values
    let defaultFontName = "KFGQPC Uthman Taha Naskh" // Font bagus untuk Arab

    // MARK: - Init
    private init() {
        // Load dari UserDefaults
        self.showHarakat = defaults.textViewShowHarakat
        self.lineHeight = defaults.lineHeight

        let savedSize = defaults.float(forKey: UserDefaults.TextViewKeys.fontSize)
        self.fontSize = savedSize > 0 ? CGFloat(savedSize) : 19.0

        self.fontName = defaults.string(forKey: UserDefaults.TextViewKeys.fontName) ?? "KFGQPC Uthman Taha Naskh"
        self.clickableAnnotation = defaults.enableAnnotationClick
    }

    // MARK: - Public Methods
    func toggleHarakat() {
        showHarakat.toggle()
    }

    func setLineHeight(_ newHeight: Double) {
        lineHeight = newHeight
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

    // MARK: - Helpers
    private func needsRedraw(oldFont: String, newFont: String) -> Bool {
        let isOldSpecial = oldFont == ArabicFont.alBayan.rawValue
        let isNewSpecial = newFont == ArabicFont.alBayan.rawValue
        return isOldSpecial != isNewSpecial
    }
}
