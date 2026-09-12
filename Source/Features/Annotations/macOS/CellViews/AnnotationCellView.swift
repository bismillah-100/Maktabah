//
//  AnnotationCellView.swift
//  maktab
//
//  Created by MacBook on 16/12/25.
//

import Cocoa

final class AnnotationCellView: NSTableCellView {
    static let pagePartLineLimit = 2

    let date: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .left
        field.baseWritingDirection = .leftToRight
        field.font = .preferredFont(forTextStyle: .footnote)
        field.textColor = .secondaryLabelColor
        field.cell?.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        return field
    }()

    let context: BundledArabicTextField = makeWrappingArabicLabel(fontSize: 17, textColor: .labelColor)
    let note: BundledArabicTextField = makeWrappingArabicLabel(fontSize: 15, textColor: .labelColor)
    let pagePart: BundledArabicTextField = makeWrappingArabicLabel(fontSize: 15, textColor: .secondaryLabelColor)

    private let topRowView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentStackView: NSStackView = {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.alignment = .trailing
        stack.spacing = 8
        stack.detachesHiddenViews = true
        stack.userInterfaceLayoutDirection = .leftToRight
        return stack
    }()

    private let rightBorder = makeBorderBox()
    private let bottomBorder = makeBorderBox()

    private static func makeBorderBox() -> NSBox {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.borderColor = .tertiaryLabelColor
        box.borderWidth = 1
        return box
    }

    private var contentStackLeadingConstraint: NSLayoutConstraint?
    private var contentStackTrailingConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            applyLineLimits()
        }
    }

    private static func makeWrappingArabicLabel(
        fontSize: CGFloat, textColor: NSColor
    ) -> BundledArabicTextField {
        let field = BundledArabicTextField(wrappingLabelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.alignment = .right
        field.baseWritingDirection = .rightToLeft
        field.userInterfaceLayoutDirection = .rightToLeft
        field.font = ReusableFunc.bundledArabicFont(ofSize: fontSize)
        field.textColor = textColor
        field.cell?.truncatesLastVisibleLine = true
        field.allowsExpansionToolTips = true
        field.cell?.allowsUndo = false
        return field
    }

    private func setupViews() {
        autoresizingMask = [.width, .height]

        topRowView.addSubview(date)
        topRowView.addSubview(context)

        contentStackView.addArrangedSubview(topRowView)
        contentStackView.addArrangedSubview(note)
        contentStackView.addArrangedSubview(pagePart)

        addSubview(contentStackView)
        addSubview(rightBorder)
        addSubview(bottomBorder)

        let stackLeading = contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        contentStackLeadingConstraint = stackLeading

        let stackTrailing = contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9)
        contentStackTrailingConstraint = stackTrailing

        let contextLowLeading = context.leadingAnchor.constraint(equalTo: date.trailingAnchor, constant: 8)
        contextLowLeading.priority = .defaultLow

        NSLayoutConstraint.activate([
            date.leadingAnchor.constraint(equalTo: topRowView.leadingAnchor, constant: 4),
            date.topAnchor.constraint(equalTo: topRowView.topAnchor, constant: 8),
            date.heightAnchor.constraint(equalToConstant: 14),

            context.trailingAnchor.constraint(equalTo: topRowView.trailingAnchor),
            context.topAnchor.constraint(equalTo: topRowView.topAnchor),
            context.bottomAnchor.constraint(equalTo: topRowView.bottomAnchor),
            context.leadingAnchor.constraint(greaterThanOrEqualTo: date.trailingAnchor, constant: 8),
            contextLowLeading,

            topRowView.bottomAnchor.constraint(greaterThanOrEqualTo: date.bottomAnchor, constant: 4),
            topRowView.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            topRowView.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),

            note.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),

            pagePart.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            pagePart.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),

            rightBorder.widthAnchor.constraint(equalToConstant: 1),
            rightBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightBorder.topAnchor.constraint(equalTo: topAnchor),
            rightBorder.bottomAnchor.constraint(equalTo: bottomAnchor),

            bottomBorder.heightAnchor.constraint(equalToConstant: 1),
            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackLeading,
            stackTrailing,
            contentStackView.bottomAnchor.constraint(equalTo: bottomBorder.topAnchor, constant: -10),
        ])

        applyLineLimits()
    }

    func applyLineLimits() {
        note.maximumNumberOfLines = UserDefaults.standard.annMaxNumberOfLines
        context.maximumNumberOfLines = UserDefaults.standard.ctxMaxNumberOfLines
        pagePart.maximumNumberOfLines = Self.pagePartLineLimit
    }

    func setTimelineInset(_ isTimeline: Bool) {
        contentStackLeadingConstraint?.constant = isTimeline ? 0 : 4
        contentStackTrailingConstraint?.constant = isTimeline ? 0 : -9
        rightBorder.isHidden = isTimeline
    }
}
