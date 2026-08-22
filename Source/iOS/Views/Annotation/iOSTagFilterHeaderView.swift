//
//  iOSTagFilterHeaderView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 22/08/26.
//

import UIKit

final class iOSTagFilterHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "iOSTagFilterHeaderView"

    private let containerStack = UIStackView()
    private let filterButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let chipsScrollView = UIScrollView()
    private let chipsStackView = UIStackView()

    private var onFilterTap: (() -> Void)?
    private var onModeTap: (() -> Void)?
    private var onTagToggle: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        semanticContentAttribute = .forceRightToLeft

        containerStack.axis = .horizontal
        containerStack.spacing = 8
        containerStack.alignment = .center
        containerStack.distribution = .fill
        containerStack.translatesAutoresizingMaskIntoConstraints = false

        // Filter Button
        var filterConfig = UIButton.Configuration.plain()
        filterConfig.image = UIImage(systemName: "tag")
        filterConfig.contentInsets = .init(top: 6, leading: 6, bottom: 6, trailing: 6)
        filterButton.configuration = filterConfig
        filterButton.addTarget(self, action: #selector(filterButtonAction), for: .touchUpInside)
        filterButton.setContentHuggingPriority(.required, for: .horizontal)
        filterButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Mode Button (AND / OR)
        modeButton.addTarget(self, action: #selector(modeButtonAction), for: .touchUpInside)
        modeButton.setContentHuggingPriority(.required, for: .horizontal)
        modeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Chips Scroll View
        chipsScrollView.showsHorizontalScrollIndicator = false
        chipsScrollView.showsVerticalScrollIndicator = false
        chipsScrollView.alwaysBounceHorizontal = false
        chipsScrollView.translatesAutoresizingMaskIntoConstraints = false
        chipsScrollView.transform = CGAffineTransform(scaleX: -1, y: 1)

        chipsStackView.axis = .horizontal
        chipsStackView.spacing = 6
        chipsStackView.alignment = .center
        chipsStackView.translatesAutoresizingMaskIntoConstraints = false
        chipsStackView.semanticContentAttribute = .forceRightToLeft
        chipsStackView.transform = CGAffineTransform(scaleX: -1, y: 1)

        chipsScrollView.addSubview(chipsStackView)
        NSLayoutConstraint.activate([
            chipsStackView.topAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.topAnchor),
            chipsStackView.bottomAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.bottomAnchor),
            chipsStackView.leadingAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.leadingAnchor),
            chipsStackView.trailingAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.trailingAnchor),
            chipsStackView.heightAnchor.constraint(equalTo: chipsScrollView.frameLayoutGuide.heightAnchor),
        ])

        containerStack.addArrangedSubview(chipsScrollView)
        containerStack.addArrangedSubview(modeButton)
        containerStack.addArrangedSubview(filterButton)

        addSubview(containerStack)
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ListLayoutMetrics.defaultPadding),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ListLayoutMetrics.defaultPadding),
            containerStack.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    func configure(
        allTags: [String],
        selectedTags: Set<String>,
        isAndMode: Bool,
        onFilterTap: @escaping () -> Void,
        onModeTap: @escaping () -> Void,
        onTagToggle: @escaping (String) -> Void
    ) {
        self.onFilterTap = onFilterTap
        self.onModeTap = onModeTap
        self.onTagToggle = onTagToggle

        isHidden = allTags.isEmpty
        if allTags.isEmpty { return }

        // Update mode button appearance
        modeButton.configurationUpdateHandler = { button in
            var modeConfig: UIButton.Configuration = isAndMode ? .filled() : .plain()
            modeConfig.image = UIImage(systemName: "line.3.horizontal.decrease")
            modeConfig.contentInsets = .init(top: 6, leading: 6, bottom: 6, trailing: 6)
            modeConfig.cornerStyle = .capsule
            button.configuration = modeConfig
        }

        // Incrementally update chips in stack view
        let existingButtons = chipsStackView.arrangedSubviews.compactMap { $0 as? UIButton }
        let existingTitles = Set(existingButtons.compactMap { $0.configuration?.title })
        let newTagsSet = Set(allTags)

        // Remove stale chips
        for btn in existingButtons {
            if let title = btn.configuration?.title, !newTagsSet.contains(title) {
                chipsStackView.removeArrangedSubview(btn)
                btn.removeFromSuperview()
            }
        }

        // Add new chips
        for tag in allTags where !existingTitles.contains(tag) {
            let isSelected = selectedTags.contains(tag)
            let chip = makeChipButton(tag: tag, isSelected: isSelected)
            let insertIdx = chipsStackView
                .arrangedSubviews.compactMap { ($0 as? UIButton)?.configuration?.title }.enumerated()
                .first { tag.localizedCaseInsensitiveCompare($0.element) == .orderedAscending }?
                .offset ?? chipsStackView.arrangedSubviews.count
            chipsStackView.insertArrangedSubview(chip, at: insertIdx)
        }

        // Sync selection state of all chips
        for view in chipsStackView.arrangedSubviews {
            guard let btn = view as? UIButton, let title = btn.configuration?.title else { continue }
            let isSelected = selectedTags.contains(title)
            if btn.isSelected != isSelected {
                btn.isSelected = isSelected
            }
            btn.setNeedsUpdateConfiguration()
        }

        modeButton.setNeedsUpdateConfiguration()
    }

    private func makeChipButton(tag: String, isSelected: Bool) -> UIButton {
        let btn = UIButton(type: .system)
        btn.isSelected = isSelected
        btn.configurationUpdateHandler = { [weak self] button in
            guard let self else { return }
            button.configuration = updateChipAppearance(
                tag: tag, isSelected: button.isSelected
            )
        }
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        btn.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onTagToggle?(tag)
        }, for: .touchUpInside)

        return btn
    }

    private func updateChipAppearance(
        tag: String,
        isSelected: Bool
    ) -> UIButton.Configuration {
        var config: UIButton.Configuration = .bordered()
        config.cornerStyle = .capsule
        config.title = tag
        config.buttonSize = .medium
        config.image = isSelected ? .init(systemName: "circle.fill") : nil
        config.imagePlacement = .leading
        config.imagePadding = 4
        config.preferredSymbolConfigurationForImage = .init(pointSize: 6, weight: .semibold)
        return config
    }

    @objc private func filterButtonAction() {
        onFilterTap?()
    }

    @objc private func modeButtonAction() {
        onModeTap?()
    }
}
