//
//  TimelineOutlineViews.swift
//  Maktabah
//
//  Created by Antigravity on 12/09/26.
//

import Cocoa

enum TimelineMetrics {
    static let railLineWidth: CGFloat = 1
    static let nodeSize: CGFloat = 14
    static let dotSize: CGFloat = 7
}

final class TimelineNodeView: NSView {
    var strokeColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    var fillColor: NSColor = .controlBackgroundColor {
        didSet { needsDisplay = true }
    }

    var lineWidth: CGFloat = 2 {
        didSet { needsDisplay = true }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let inset = lineWidth / 2
        let circleRect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(ovalIn: circleRect)
        path.lineWidth = lineWidth

        fillColor.setFill()
        path.fill()

        if lineWidth > 0, strokeColor != .clear {
            strokeColor.setStroke()
            path.stroke()
        }
    }
}

final class TimelineGroupCellView: NSTableCellView {
    private let topTimelineRail: NSBox = {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .separator
        return box
    }()

    private let bottomTimelineRail: NSBox = {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .separator
        return box
    }()

    private let nodeView: TimelineNodeView = {
        let view = TimelineNodeView()
        view.fillColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleTextField: NSTextField = {
        let titleTextField = NSTextField()
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.isBezeled = false
        titleTextField.isEditable = false
        titleTextField.isSelectable = false
        titleTextField.drawsBackground = false
        titleTextField.textColor = .labelColor
        titleTextField.lineBreakMode = .byTruncatingTail
        titleTextField.maximumNumberOfLines = 1
        titleTextField.alignment = .right
        titleTextField.baseWritingDirection = .rightToLeft
        return titleTextField
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        autoresizingMask = [.width]

        textField = titleTextField

        addSubview(topTimelineRail)
        addSubview(bottomTimelineRail)
        addSubview(nodeView)
        addSubview(titleTextField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),

            nodeView.centerXAnchor.constraint(equalTo: topTimelineRail.centerXAnchor),
            nodeView.centerYAnchor.constraint(equalTo: centerYAnchor),
            nodeView.widthAnchor.constraint(equalToConstant: TimelineMetrics.nodeSize),
            nodeView.heightAnchor.constraint(equalToConstant: TimelineMetrics.nodeSize),

            topTimelineRail.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            topTimelineRail.widthAnchor.constraint(equalToConstant: TimelineMetrics.railLineWidth),
            topTimelineRail.topAnchor.constraint(equalTo: topAnchor),
            topTimelineRail.bottomAnchor.constraint(equalTo: nodeView.topAnchor),

            bottomTimelineRail.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            bottomTimelineRail.widthAnchor.constraint(equalToConstant: TimelineMetrics.railLineWidth),
            bottomTimelineRail.topAnchor.constraint(equalTo: nodeView.bottomAnchor),
            bottomTimelineRail.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleTextField.trailingAnchor.constraint(equalTo: nodeView.leadingAnchor, constant: -8),
            titleTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
        ])
    }

    func configure(title: String) {
        titleTextField.stringValue = title
    }
}
