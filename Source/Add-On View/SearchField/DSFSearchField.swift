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
            self.searchTermChangeCallback?(self.searchTerm)
        }
    }

    /// An (optional) block-based interface for receiving search field changes
    @objc public var searchTermChangeCallback: ((String) -> Void)? = nil

    /// Called when the user 'submits' the search (eg. presses return in the control)
    @objc public var searchSubmitCallback: ((String) -> Void)? = nil

    /// Create a search field
    /// - Parameters:
    ///   - frameRect: The frame for the field
    ///   - recentsAutosaveName: The autosave name
    @objc public init(frame frameRect: NSRect, recentsAutosaveName: NSSearchField.RecentsAutosaveName?) {
        super.init(frame: frameRect)
        self.recentsAutosaveName = recentsAutosaveName
        self.setup()
    }

    /// Creates a search field
    @objc public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }

    var rtl: Bool {
        MainWindow.rtl
    }

    // Show custom menu on mouse down and make field first responder
    public override func mouseDown(with event: NSEvent) {
        guard let cell = cell as? NSSearchFieldCell else {
            super.mouseDown(with: event)
            return
        }

        // Lokasi klik dalam koordinat view
        let point = convert(event.locationInWindow, from: nil)

        // Jika klik di tombol clear (✕), serahkan ke AppKit
        if cell.cancelButtonRect(forBounds: self.bounds).contains(point) {
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

    deinit {
        self.delegate = nil
        self.unbind(.value)
    }
}

// MARK: - delegate callbacks

extension DSFSearchField: NSSearchFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let callback = self.searchSubmitCallback {
                callback(self.searchTerm)
            }
        }
        return false
    }
}

// MARK: - Private

private extension DSFSearchField {

    // Setup from init
    func setup() {
        // Do NOT use searchMenuTemplate (AppKit clones template and ignores delegate)
        // We will build and show our own RTL menu when needed.
        self.bind(.value, to: self, withKeyPath: #keyPath(searchTerm), options: nil)
        self.delegate = self
    }

    // Build a fully controlled RTL menu from recentSearches and show it manually
    private func buildRTLSearchMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
        // Title
        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = createRTLAttributedTitle(for: NSLocalizedString("LCSMenuRecentTitle", comment: ""))
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let recents = self.recentSearches

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

    // Action when a recent is selected
    @objc private func didSelectRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        self.stringValue = text
        // Move selected item to front, preserve uniqueness
        var newRecents = [text]
        for r in self.recentSearches where r != text {
            newRecents.append(r)
        }
        self.recentSearches = newRecents
        // Trigger search submit callback if present
        self.searchSubmitCallback?(text)
        // Also send action to target
        self.sendAction(self.action, to: self.target)
    }

    // Clear all recents
    @objc private func clearRecents() {
        self.recentSearches = []
    }

    // Helper RTL attributed string
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
        while !truncated.isEmpty &&
              width(ellipsis + truncated) > maxWidth {
            truncated.removeLast()
        }

        return createRTLAttributedTitle(for: truncated + ellipsis)
    }
}
