//
//  AnnotationContentView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 10/06/26.
//

import UIKit

// MARK: - Annotation Content View

class AnnotationContentView: UIView, UIContentView {
    var configuration: UIContentConfiguration {
        didSet { apply(configuration) }
    }

    private let contextLabel = UILabel()
    private let noteLabel = UILabel()
    private let secondaryLabel = UILabel()
    private let pageLabel = UILabel()
    private let bottomStack = UIStackView()
    private let mainStack = UIStackView()

    init(_ configuration: UIContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupViews()
        apply(configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupViews() {
        setupLabels()

        bottomStack.axis = .horizontal
        bottomStack.alignment = .center
        bottomStack.spacing = 6
        bottomStack.semanticContentAttribute = .forceLeftToRight
        bottomStack.addArrangedSubview(pageLabel)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomStack.addArrangedSubview(spacer)
        bottomStack.addArrangedSubview(secondaryLabel)

        mainStack.axis = .vertical
        mainStack.spacing = 8
        mainStack.alignment = .fill
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(contextLabel)
        mainStack.addArrangedSubview(noteLabel)
        mainStack.setCustomSpacing(12, after: noteLabel)
        mainStack.addArrangedSubview(bottomStack)

        addSubview(mainStack)
        let topC = mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        let bottomC = mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        let heightC = heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        [topC, bottomC, heightC].forEach { $0.priority = .init(999) }

        NSLayoutConstraint.activate([
            topC, bottomC, heightC,
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
        ])
    }

    private func setupLabels() {
        contextLabel.numberOfLines = 2
        contextLabel.textAlignment = .right
        contextLabel.lineBreakMode = .byTruncatingTail

        noteLabel.numberOfLines = 4
        noteLabel.textColor = .secondaryLabel
        noteLabel.font = .preferredFont(forTextStyle: .caption1)
        noteLabel.textAlignment = .right

        secondaryLabel.font = .preferredFont(forTextStyle: .caption2)
        secondaryLabel.textColor = .secondaryLabel
        secondaryLabel.lineBreakMode = .byTruncatingMiddle

        pageLabel.font = .preferredFont(forTextStyle: .caption2)
        pageLabel.textColor = .secondaryLabel
    }

    private func apply(_ contentConfig: UIContentConfiguration) {
        guard let config = contentConfig as? AnnotationContentConfiguration,
              let ann = config.annotation
        else { return }

        let arabicFont = UIFont(name: ArabicFont.kfgqpcUthmanTahaNaskh.rawValue, size: 18)
            ?? .preferredFont(forTextStyle: .body)

        contextLabel.attributedText = buildAttributedContext(for: ann, font: arabicFont)

        if let note = ann.note, !note.isEmpty {
            noteLabel.text = note
            noteLabel.isHidden = false
        } else {
            noteLabel.isHidden = true
        }

        let (secondaryText, secondaryColor, isHidden) = resolveSecondaryInfo(for: ann, groupingMode: config.groupingMode)
        secondaryLabel.text = secondaryText
        secondaryLabel.textColor = secondaryColor
        secondaryLabel.isHidden = isHidden

        if let pgArb = ann.pageArb {
            pageLabel.text = "ج \(ann.partArb ?? "") ∙ ص \(pgArb)"
            pageLabel.isHidden = false
        } else {
            pageLabel.isHidden = true
        }
    }

    private func buildAttributedContext(for ann: Annotation, font: UIFont) -> NSAttributedString {
        let attrContext = NSMutableAttributedString(
            string: ann.context,
            attributes: [.font: font, .foregroundColor: UIColor.label]
        )
        let fullRg = NSRange(location: 0, length: attrContext.length)
        let color = UIColor(hex: ann.colorHex) ?? .systemYellow

        if ann.type == .highlight {
            attrContext.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.3), range: fullRg)
        } else if ann.type == .underline {
            attrContext.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRg)
            attrContext.addAttribute(.underlineColor, value: color, range: fullRg)
        }
        return attrContext
    }

    private func resolveSecondaryInfo(
        for ann: Annotation,
        groupingMode: AnnotationGroupingMode
    ) -> (text: String?, color: UIColor, isHidden: Bool) {
        if groupingMode == .tag {
            if let book = LibraryDataManager.shared.getBook([ann.bkId]).first {
                (book.book, .secondaryLabel, false)
            } else {
                ("Book #\(ann.bkId) not found", .systemRed, false)
            }
        } else {
            if !ann.tags.isEmpty {
                (ann.tags.map { " -- \($0)" }.joined(separator: " "), .secondaryLabel, false)
            } else {
                (nil, .secondaryLabel, true)
            }
        }
    }
}

struct AnnotationContentConfiguration: UIContentConfiguration {
    var annotation: Annotation?
    var groupingMode: AnnotationGroupingMode = .book

    func makeContentView() -> UIView & UIContentView {
        AnnotationContentView(self)
    }

    func updated(for state: UIConfigurationState) -> AnnotationContentConfiguration {
        self
    }
}

// MARK: - Item Types

enum AnnotationItem: Hashable, @unchecked Sendable {
    case group(SwiftUIAnnotationNode)
    case annotation(SwiftUIAnnotationNode)

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .group(node):
            hasher.combine("group")
            hasher.combine(node.id)
            hasher.combine(node.title)
        case let .annotation(node):
            hasher.combine("ann")
            hasher.combine(node.id)
            hasher.combine(node.title)
            if let ann = node.annotation {
                hasher.combine(ann.colorHex)
                hasher.combine(ann.note)
                hasher.combine(ann.tags)
                hasher.combine(ann.type)
            }
        }
    }

    static func == (lhs: AnnotationItem, rhs: AnnotationItem) -> Bool {
        switch (lhs, rhs) {
        case let (.group(a), .group(b)):
            a.id == b.id && a.title == b.title
        case let (.annotation(a), .annotation(b)):
            a.id == b.id &&
                a.title == b.title &&
                a.annotation?.type == b.annotation?.type &&
                a.annotation?.colorHex == b.annotation?.colorHex &&
                a.annotation?.note == b.annotation?.note &&
                a.annotation?.tags == b.annotation?.tags
        default: false
        }
    }
}

extension AnnotationItem {
    /// Mengambil data `SwiftUIAnnotationNode` secara langsung tanpa perlu switch-case manual lagi.
    var node: SwiftUIAnnotationNode {
        switch self {
        case let .group(node), let .annotation(node):
            node
        }
    }

    /// Opsional: Untuk ngecek instan apakah item ini bertindak sebagai Section/Grup
    var isGroup: Bool {
        if case .group = self { return true }
        return false
    }
}
