//
//  AnnotationColorMenuView.swift
//  maktab
//

import Cocoa

// MARK: - AnnotationColorMenuView

final class AnnotationColorMenuView: NSView {

    weak var target: AnyObject?
    var colorAction: Selector = #selector(
        IbarotTextViewMenuTarget.menuDidSelectColor(_:)
    )
    var underlineAction: Selector = #selector(
        IbarotTextViewMenuTarget.menuDidSelectUnderline(_:)
    )

    // MARK: Layout constants
    private let circleSize: CGFloat = 22
    private let hPad: CGFloat = 16
    private let vPad: CGFloat = 6
    private let gap: CGFloat = 8
    private let sepWidth: CGFloat = 1
    private let uBtnWidth: CGFloat = 22

    private(set) var colorButtons: [CircleColorButton] = []
    private var separatorView: NSView?
    private var underlineBtn: NSButton?

    // MARK: - Init

    init(target: AnyObject) {
        self.target = target
        // Frame dihitung dari intrinsicContentSize
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        reloadColors()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
        reloadColors()
    }

    // MARK: - Reload

    func reloadColors() {
        // Bersihkan subview lama
        subviews.forEach { $0.removeFromSuperview() }
        colorButtons.removeAll()
        separatorView = nil
        underlineBtn = nil

        let colors = UserDefaults.standard.recentHighlightColors

        for (i, color) in colors.enumerated() {
            let highlight = color.highlight(withLevel: 0.3) ?? color
            let btn = CircleColorButton(color: highlight)
            btn.tag = i
            btn.target = target
            btn.action = colorAction
            btn.toolTip = color.accessibilityName
            colorButtons.append(btn)
            addSubview(btn)
        }

        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        separatorView = sep
        addSubview(sep)

        let uBtn = NSButton()
        uBtn.isBordered = false
        uBtn.wantsLayer = true
        uBtn.layer?.cornerRadius = 4
        uBtn.target = target
        uBtn.action = underlineAction
        uBtn.toolTip = "Underline"
        let conf = NSImage.SymbolConfiguration(
            pointSize: 13,
            weight: .semibold,
            scale: .large
        )
        uBtn.image = NSImage(
            systemSymbolName: "underline",
            accessibilityDescription: nil
        )?
        .withSymbolConfiguration(conf)
        uBtn.imagePosition = .imageOnly
        underlineBtn = uBtn
        addSubview(uBtn)

        // Hitung frame sekarang
        let size = computedSize()
        frame = NSRect(origin: .zero, size: size)
    }

    // MARK: - Layout (frame-based)

    override func layout() {
        super.layout()

        var x = hPad
        let y = vPad / 3

        for btn in colorButtons {
            btn.frame = NSRect(
                x: x,
                y: y,
                width: circleSize,
                height: circleSize
            )
            x += circleSize + gap
        }

        // Separator
        if let sep = separatorView {
            x -= gap / 2
            sep.frame = NSRect(x: x, y: y + 2, width: sepWidth, height: circleSize - 4)
            x += sepWidth + gap / 2
        }

        // Underline button
        if let uBtn = underlineBtn {
            uBtn.frame = NSRect(
                x: x,
                y: y,
                width: uBtnWidth,
                height: circleSize
            )
        }
    }

    // MARK: - Sizing

    private func computedSize() -> NSSize {
        let count = UserDefaults.standard.recentHighlightColors.count
        let w =
            hPad
            + CGFloat(count) * circleSize
            + CGFloat(count) * gap  // gap setelah tiap lingkaran
            + sepWidth
            + uBtnWidth
            + hPad
        return NSSize(width: w, height: circleSize + vPad)
    }

    override var intrinsicContentSize: NSSize { computedSize() }

    // NSMenu menggunakan frame.size untuk menentukan lebar item
    // override ini memastikan item tidak di-resize paksa oleh menu
    override var fittingSize: NSSize { computedSize() }
}

// MARK: - CircleColorButton

final class CircleColorButton: NSButton {
    let color: NSColor
    private var isHovered = false

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [
                    .inVisibleRect, .activeAlways, .mouseEnteredAndExited,
                ],
                owner: self,
                userInfo: nil
            )
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = isHovered ? 1 : 2.5
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset))
        color.setFill()
        path.fill()
        color.shadow(withLevel: isHovered ? 0.2 : 0.1)?.setStroke()
        path.lineWidth = isHovered ? 1.5 : 1
        path.stroke()
    }
}

// MARK: - Dummy protocol

@objc protocol IbarotTextViewMenuTarget {
    func menuDidSelectColor(_ sender: NSButton)
    func menuDidSelectUnderline(_ sender: NSButton)
}
