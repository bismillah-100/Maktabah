//
//  DSFSearchField.swift
//  maktab
//
//  Created by MacBook on 17/12/25.
//

import Cocoa

//
//  DSFSearchField.swift
//
//  Copyright © 2023 Darren Ford. All rights reserved.
//
//  MIT license
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
//  documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial
//  portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
//  WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
//  OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//  OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import AppKit

/// A custom search field that provides a recent search list.
///
/// Fully definable through Interface Builder (set Autosave in the Attributes Inspector)
@objc public class DSFSearchField: NSSearchField {
    /// The search text convenience
    ///
    /// * Bindable (using addObserver) for search text changes
    /// * Settable to change the name of the search text
    @objc public dynamic var searchTerm: String = "" {
        didSet {
            searchTermChangeCallback?(searchTerm)
        }
    }

    /// An (optional) block-based interface for receiving search field changes
    @objc public var searchTermChangeCallback: ((String) -> Void)?

    /// Called when the user 'submits' the search (eg. presses return in the control)
    @objc public var searchSubmitCallback: ((String) -> Void)?

    public var onBecomeFirstResponder: (() -> Void)?

    /// Create a search field
    /// - Parameters:
    ///   - frameRect: The frame for the field
    ///   - recentsAutosaveName: The autosave name
    @objc public init(frame frameRect: NSRect, recentsAutosaveName: NSSearchField.RecentsAutosaveName?) {
        super.init(frame: frameRect)
        self.recentsAutosaveName = recentsAutosaveName
        setup()
    }

    /// Creates a search field
    @objc public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    var rtl: Bool {
        MainWindow.rtl
    }

    /// Show custom menu on mouse down and make field first responder
    override public func mouseDown(with event: NSEvent) {
        guard let cell = cell as? NSSearchFieldCell else {
            super.mouseDown(with: event)
            return
        }

        // Lokasi klik dalam koordinat view
        let point = convert(event.locationInWindow, from: nil)

        // Jika klik di tombol clear (✕), serahkan ke AppKit
        if cell.cancelButtonRect(forBounds: bounds).contains(point) {
            super.mouseDown(with: event)
            return
        }

        guard cell.searchButtonRect(forBounds: bounds).contains(point) else { return }

        // Jika klik di area text / search icon → tampilkan menu RTL
        let menu = buildRTLSearchMenu()
        menu.minimumWidth = bounds.width
        // Anchor ke kanan-bawah (RTL)
        let x = rtl ? bounds.maxX : bounds.minX
        let anchor = NSPoint(x: x, y: bounds.maxY + 8)
        menu.popUp(positioning: nil, at: anchor, in: self)

        window?.makeFirstResponder(self)
    }

    @discardableResult
    override public func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { onBecomeFirstResponder?() }

        return didBecome
    }

    deinit {
        MainActor.assumeIsolated {
            delegate = nil
            unbind(.value)
        }
    }
}

// MARK: - delegate callbacks

extension DSFSearchField: NSSearchFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let callback = searchSubmitCallback {
                callback(searchTerm)
            }
        }
        return false
    }
}

// MARK: - Private

private extension DSFSearchField {
    /// Setup from init
    func setup() {
        // Do NOT use searchMenuTemplate (AppKit clones template and ignores delegate)
        // We will build and show our own RTL menu when needed.
        bind(.value, to: self, withKeyPath: #keyPath(searchTerm), options: nil)
        delegate = self
    }

    /// Build a fully controlled RTL menu from recentSearches and show it manually
    private func buildRTLSearchMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
        // Title
        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = createRTLAttributedTitle(for: NSLocalizedString("LCSMenuRecentTitle", comment: ""))
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let recents = recentSearches

        if recents.isEmpty {
            let emptyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            emptyItem.attributedTitle = createRTLAttributedTitle(for: NSLocalizedString("LCSMenuNoRecentsTitle", comment: ""))
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for text in recents {
                let item = NSMenuItem(title: "", action: #selector(didSelectRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = text
                item.attributedTitle = rtlTruncatedText(
                    text,
                    maxWidth: bounds.width - 24 // padding aman
                )
                menu.addItem(item)
            }

            menu.addItem(.separator())

            let clearItem = NSMenuItem(title: "", action: #selector(clearRecents), keyEquivalent: "")
            clearItem.target = self
            clearItem.attributedTitle = createRTLAttributedTitle(for: NSLocalizedString("LCSMenuClearRecentsTitle", comment: ""))
            menu.addItem(clearItem)
        }

        return menu
    }

    /// Action when a recent is selected
    @objc private func didSelectRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        stringValue = text
        // Move selected item to front, preserve uniqueness
        var newRecents = [text]
        for r in recentSearches where r != text {
            newRecents.append(r)
        }
        recentSearches = newRecents
        // Trigger search submit callback if present
        searchSubmitCallback?(text)
        // Also send action to target
        sendAction(action, to: target)
    }

    /// Clear all recents
    @objc private func clearRecents() {
        recentSearches = []
    }

    /// Helper RTL attributed string
    private func createRTLAttributedTitle(for text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.alignment = rtl ? .right : .left
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }

    private func rtlTruncatedText(
        _ text: String,
        maxWidth: CGFloat
    ) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let ellipsis = "…"

        func width(_ s: String) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: font]).width
        }

        // Jika sudah muat, pakai apa adanya
        if width(text) <= maxWidth {
            return createRTLAttributedTitle(for: text)
        }

        var truncated = text

        // Potong dari AWAL (RTL)
        while !truncated.isEmpty,
              width(ellipsis + truncated) > maxWidth
        {
            truncated.removeLast()
        }

        return createRTLAttributedTitle(for: truncated + ellipsis)
    }
}

class ClearSearchFieldCell: NSSearchFieldCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        // Gambar background transparan, tapi tetap gambar search icon & text
        super.drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        // Skip background, langsung gambar border rounded saja
        let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cellFrame.height / 2,
                                yRadius: cellFrame.height / 2)
        NSColor.gray.withAlphaComponent(0.15).setFill()
        path.fill()

        drawInterior(withFrame: cellFrame, in: controlView)
    }
}
