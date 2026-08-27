//
//  ListContentView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 10/06/26.
//

import UIKit

/// Tri-state checkbox untuk selection mode.
enum CheckboxState: Equatable {
    case unchecked
    case checked
    case partial
}

/// Leading accessory type untuk list items.
enum LeadingAccessoryType: Equatable {
    case none
    case icon(String) // SF Symbol name
    case checkbox(CheckboxState)

    var isCheckboxMode: Bool {
        if case .checkbox = self { return true }
        return false
    }
}

/// Callback untuk checkbox tap.
typealias CheckboxTapHandler = () -> Void

class ListContentView: UIView, UIContentView {
    private var appliedConfiguration: ListContentConfiguration?

    var configuration: UIContentConfiguration {
        get { appliedConfiguration ?? ListContentConfiguration(root: false) }
        set {
            guard let safeConfig = newValue as? ListContentConfiguration else { return }
            let oldConfig = appliedConfiguration // Simpan state sebelumnya
            appliedConfiguration = safeConfig
            apply(safeConfig, oldConfig: oldConfig) // Lempar ke apply
        }
    }

    private let label = UILabel()
    private let leadingIcon = UIImageView()
    private let checkboxButton = UIButton(type: .system)
    let chevronIcon = UIImageView()
    private var trailingConstraint: NSLayoutConstraint?

    /// Callback ketika checkbox diklik.
    var onCheckboxTap: CheckboxTapHandler?

    override var effectiveUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection {
        .leftToRight
    }

    init(_ configuration: ListContentConfiguration) {
        appliedConfiguration = configuration
        super.init(frame: .zero)
        semanticContentAttribute = .forceLeftToRight
        setupViews()
        apply(configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupViews() {
        let leadingStack = UIStackView(arrangedSubviews: [checkboxButton, leadingIcon])
        leadingStack.axis = .horizontal
        leadingStack.alignment = .center
        leadingStack.spacing = ListLayoutMetrics.imageGap
        leadingStack.translatesAutoresizingMaskIntoConstraints = false
        leadingStack.semanticContentAttribute = .forceLeftToRight

        let mainStack = UIStackView(arrangedSubviews: [label, leadingStack, chevronIcon])
        mainStack.axis = .horizontal
        mainStack.alignment = .center
        mainStack.spacing = ListLayoutMetrics.imageGap
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.semanticContentAttribute = .forceLeftToRight

        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.textAlignment = .right

        leadingIcon.setContentHuggingPriority(.required, for: .horizontal)
        leadingIcon.contentMode = .scaleAspectFit
        checkboxButton.setContentHuggingPriority(.required, for: .horizontal)
        checkboxButton.contentMode = .scaleAspectFit
        chevronIcon.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(mainStack)
        setupStackConstraints(mainStack: mainStack)

        checkboxButton.addTarget(self, action: #selector(checkboxTapped), for: .touchUpInside)
    }

    private func setupStackConstraints(mainStack: UIStackView) {
        let trailing = mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ListLayoutMetrics.defaultPadding)
        trailingConstraint = trailing

        let topConstraint = mainStack.topAnchor.constraint(equalTo: topAnchor)
        let bottomConstraint = mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        let leadingConstraint = mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ListLayoutMetrics.defaultPadding)
        let heightConstraint = heightAnchor.constraint(greaterThanOrEqualToConstant: 50)

        [topConstraint, bottomConstraint, leadingConstraint, trailing, heightConstraint].forEach { $0.priority = .init(999) }

        NSLayoutConstraint.activate([
            topConstraint, bottomConstraint, leadingConstraint, trailing, heightConstraint,
            leadingIcon.widthAnchor.constraint(equalToConstant: ListLayoutMetrics.imageWidth),
            leadingIcon.heightAnchor.constraint(equalToConstant: ListLayoutMetrics.imageWidth),
            checkboxButton.widthAnchor.constraint(equalToConstant: ListLayoutMetrics.imageWidth),
            checkboxButton.heightAnchor.constraint(equalToConstant: ListLayoutMetrics.imageWidth),
            chevronIcon.widthAnchor.constraint(equalToConstant: ListLayoutMetrics.chevronWidth),
            chevronIcon.heightAnchor.constraint(equalToConstant: ListLayoutMetrics.chevronWidth),
        ])
    }

    @objc private func checkboxTapped() {
        onCheckboxTap?()
    }

    private func apply(_ config: ListContentConfiguration, oldConfig: ListContentConfiguration? = nil) {
        let isModeSwitching = window != nil &&
            oldConfig != nil &&
            oldConfig?.leadingAccessory.isCheckboxMode != config.leadingAccessory.isCheckboxMode

        let updateUI = { [weak self] in
            guard let self else { return }
            trailingConstraint?.constant = ListLayoutMetrics.contentTrailingOffset(
                isRoot: config.root,
                indentationLevel: config.indentationLevel
            )

            chevronIcon.isHidden = !config.root
            label.text = config.text
            label.font = config.font
            label.textColor = config.isDownloaded ? .secondaryLabel : .label
            label.numberOfLines = 1

            applyAccessoryConfiguration(config)

            chevronIcon.image = UIImage(systemName: "chevron.left")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
            chevronIcon.tintColor = .tintColor
            chevronIcon.contentMode = .scaleAspectFit

            let angle: CGFloat = config.isExpanded ? -.pi / 2 : 0
            chevronIcon.transform = CGAffineTransform(rotationAngle: angle)

            layoutIfNeeded()
        }

        if isModeSwitching {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) { updateUI() }
        } else if let old = oldConfig, old.leadingAccessory != config.leadingAccessory, window != nil {
            UIView.transition(with: checkboxButton, duration: 0.15, options: [.transitionCrossDissolve, .allowUserInteraction]) { updateUI() }
        } else {
            updateUI()
        }
    }

    private func applyAccessoryConfiguration(_ config: ListContentConfiguration) {
        switch config.leadingAccessory {
        case .none:
            leadingIcon.isHidden = true
            leadingIcon.alpha = 0
            checkboxButton.isHidden = true
            checkboxButton.alpha = 0

        case let .icon(symbolName):
            leadingIcon.isHidden = false
            leadingIcon.alpha = 1
            checkboxButton.isHidden = true
            checkboxButton.alpha = 0
            leadingIcon.image = UIImage(systemName: symbolName)
            leadingIcon.tintColor = .tintColor

        case let .checkbox(state):
            leadingIcon.isHidden = true
            leadingIcon.alpha = 0
            checkboxButton.isHidden = false
            checkboxButton.alpha = 1

            let imageName: String
            let tintColor: UIColor
            switch state {
            case .unchecked:
                imageName = "circle"
                tintColor = .secondaryLabel
            case .checked:
                imageName = config.isDownloaded ? "xmark.circle.fill" : "checkmark.circle.fill"
                tintColor = .tintColor
            case .partial:
                imageName = "minus.circle.fill"
                tintColor = .tintColor
            }
            checkboxButton.setImage(UIImage(systemName: imageName), for: .normal)
            checkboxButton.tintColor = tintColor
        }
    }
}

struct ListContentConfiguration: UIContentConfiguration, Equatable {
    var text: String = ""
    var font: UIFont = .arabicFont(size: 20)
    var isDownloaded: Bool = false
    var leadingAccessory: LeadingAccessoryType = .none
    var isExpanded: Bool = false
    let root: Bool
    var indentationLevel: Int = 0

    func makeContentView() -> UIView & UIContentView {
        ListContentView(self)
    }

    func updated(for state: UIConfigurationState) -> ListContentConfiguration {
        self
    }
}
