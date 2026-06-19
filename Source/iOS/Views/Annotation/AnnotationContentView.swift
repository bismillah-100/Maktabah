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
        didSet { apply(configuration as! AnnotationContentConfiguration) }
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
        apply(configuration as! AnnotationContentConfiguration)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        // Context (Arabic text)
        contextLabel.numberOfLines = 2
        contextLabel.textAlignment = .right
        contextLabel.lineBreakMode = .byTruncatingTail

        // Note
        noteLabel.numberOfLines = 4
        noteLabel.textColor = .secondaryLabel
        noteLabel.font = .preferredFont(forTextStyle: .caption1)
        noteLabel.textAlignment = .right

        // Secondary (tag or book title)
        secondaryLabel.font = .preferredFont(forTextStyle: .caption2)
        secondaryLabel.textColor = .secondaryLabel
        secondaryLabel.lineBreakMode = .byTruncatingMiddle

        // Page label
        pageLabel.font = .preferredFont(forTextStyle: .caption2)
        pageLabel.textColor = .secondaryLabel

        // Bottom row: pageLabel + spacer + secondaryLabel
        bottomStack.axis = .horizontal
        bottomStack.alignment = .center
        bottomStack.spacing = 6
        bottomStack.semanticContentAttribute = .forceLeftToRight
        bottomStack.addArrangedSubview(pageLabel)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomStack.addArrangedSubview(spacer)
        bottomStack.addArrangedSubview(secondaryLabel)

        // Main vertical stack
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
        topC.priority = .init(999)
        let bottomC = mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        bottomC.priority = .init(999)
        
        NSLayoutConstraint.activate([
            topC,
            bottomC,
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
        ])
        let heightC = heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        heightC.priority = .init(999)
        heightC.isActive = true
    }

    private func apply(_ config: AnnotationContentConfiguration) {
        guard let ann = config.annotation else { return }

        // Arabic font dari ReaderViewModel
        let arabicFont = UIFont(name: ArabicFont.kfgqpcUthmanTahaNaskh.rawValue, size: 18)
            ?? .preferredFont(forTextStyle: .body)

        let contextText = ann.context
        let attrContext = NSMutableAttributedString(
            string: contextText,
            attributes: [
                .font: arabicFont,
                .foregroundColor: UIColor.label
            ]
        )

        let fullRg = NSRange(location: 0, length: attrContext.length)
        let color = UIColor(hex: ann.colorHex) ?? .systemYellow

        if ann.type == .highlight {
            attrContext.addAttribute(
                .backgroundColor,
                value: color.withAlphaComponent(0.3),
                range: fullRg
            )
        } else if ann.type == .underline {
            attrContext.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: fullRg
            )
            attrContext.addAttribute(
                .underlineColor,
                value: color,
                range: fullRg
            )
        }

        contextLabel.attributedText = attrContext

        if let note = ann.note, !note.isEmpty {
            noteLabel.text = note
            noteLabel.isHidden = false
        } else {
            noteLabel.isHidden = true
        }

        // Secondary info: book title (jika group by tag) atau tags (jika group by book)
        if config.groupingMode == .tag {
            if let book = LibraryDataManager.shared.getBook([ann.bkId]).first {
                secondaryLabel.text = book.book
                secondaryLabel.textColor = .secondaryLabel
            } else {
                secondaryLabel.text = "Book #\(ann.bkId) not found"
                secondaryLabel.textColor = .systemRed
            }
            secondaryLabel.isHidden = false
        } else {
            if !ann.tags.isEmpty {
                secondaryLabel.text = ann.tags.map { " -- \($0)" }.joined(separator: " ")
                secondaryLabel.textColor = .secondaryLabel
                secondaryLabel.isHidden = false
            } else {
                secondaryLabel.isHidden = true
            }
        }

        // Page info
        if let pgArb = ann.pageArb {
            pageLabel.text = "ج \(ann.partArb ?? "") ∙ ص \(pgArb)"
            pageLabel.isHidden = false
        } else {
            pageLabel.isHidden = true
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
        case .group(let node):
            hasher.combine("group")
            hasher.combine(node.id)
            hasher.combine(node.title)
        case .annotation(let node):
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
        case (.group(let a), .group(let b)):
            return a.id == b.id && a.title == b.title
        case (.annotation(let a), .annotation(let b)):
            return a.id == b.id &&
                a.title == b.title &&
                a.annotation?.type == b.annotation?.type &&
                a.annotation?.colorHex == b.annotation?.colorHex &&
                a.annotation?.note == b.annotation?.note &&
                a.annotation?.tags == b.annotation?.tags
        default: return false
        }
    }
}

extension AnnotationItem {
    /// Mengambil data `SwiftUIAnnotationNode` secara langsung tanpa perlu switch-case manual lagi.
    var node: SwiftUIAnnotationNode {
        switch self {
        case .group(let node), .annotation(let node):
            return node
        }
    }

    /// Opsional: Untuk ngecek instan apakah item ini bertindak sebagai Section/Grup
    var isGroup: Bool {
        if case .group = self { return true }
        return false
    }
}
