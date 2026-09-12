//
//  TimelineOutlineViews.swift
//  Maktabah
//
//  Created by Antigravity on 12/09/26.
//

import Cocoa

final class TimelineGroupCellView: NSTableCellView {
    private let symbolImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()

    private let titleTextField: NSTextField = {
        let titleTextField = NSTextField()
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.isBezeled = false
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

        updateSymbolImage()

        textField = titleTextField

        addSubview(symbolImageView)
        addSubview(titleTextField)

        NSLayoutConstraint.activate([
            symbolImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            symbolImageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            symbolImageView.widthAnchor.constraint(equalToConstant: 15),
            symbolImageView.heightAnchor.constraint(equalToConstant: 15),

            titleTextField.trailingAnchor.constraint(equalTo: symbolImageView.leadingAnchor, constant: -8),
            titleTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
        ])
    }

    override func updateLayer() {
        super.updateLayer()
        updateSymbolImage()
    }

    private func updateSymbolImage() {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            .applying(.init(paletteColors: [.controlBackgroundColor, .controlAccentColor]))
        symbolImageView.image = NSImage(
            systemSymbolName: "circle.circle", accessibilityDescription: nil,
        )?.withSymbolConfiguration(config)
    }

    func configure(title: String) {
        titleTextField.stringValue = title
    }
}
