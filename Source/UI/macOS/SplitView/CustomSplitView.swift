//
//  CustomSplitView.swift
//  maktab
//
//  Created by MacBook on 11/12/25.
//

import Cocoa

class CustomSplitView: NSSplitView {

    private var _customDividerColor: NSColor = .separatorColor

    var customDividerColor: NSColor {
        get { return _customDividerColor }
        set {
            _customDividerColor = newValue
            // Refresh dengan berbagai cara
            setNeedsDisplay(bounds)
            needsLayout = true

            // Paksa immediate update
            DispatchQueue.main.async { [weak self] in
                self?.layoutSubtreeIfNeeded()
                self?.display()
            }
        }
    }

    override var dividerThickness: CGFloat {
        return 1.0
    }

    override func drawDivider(in rect: NSRect) {
        _customDividerColor.setFill()
        rect.fill()
    }

    func updateDividerColor(to bgColor: BackgroundColor) {
        customDividerColor = switch bgColor {
        case .black, .gray, .white: .separatorColor
        case .darkSepia: bgColor.nsColor.shadow(withLevel: 0.2) ?? bgColor.nsColor
        case .sepia: bgColor.nsColor.shadow(withLevel: 0.3) ?? bgColor.nsColor
        }
    }
}
