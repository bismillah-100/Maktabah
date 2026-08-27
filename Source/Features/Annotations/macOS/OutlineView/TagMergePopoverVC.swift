import AppKit

class TagMergePopoverVC: NSViewController {
    let oldName: String
    let newName: String
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    weak var mergeView: TagMergeConfirmationView?

    init(oldName: String, newName: String) {
        self.oldName = oldName
        self.newName = newName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let mergeView = TagMergeConfirmationView(oldName: oldName, newName: newName)
        mergeView.onConfirm = { [weak self] in
            guard let self else { return }
            self.onConfirm?()
            self.presentingViewController?.dismiss(self)
        }
        mergeView.onCancel = { [weak self] in
            guard let self else { return }
            self.onCancel?()
            self.presentingViewController?.dismiss(self)
        }

        self.mergeView = mergeView
        self.view = mergeView
    }

    deinit {
        print("TagMergePopoverVC deinitialized")
        mergeView = nil
        onConfirm = nil
        onCancel = nil
    }
}

class TagMergeConfirmationView: NSView {

    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    private let messageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = 220
        return label
    }()

    private let infoLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = 220
        return label
    }()

    private lazy var mergeButton: NSButton = {
        let btn = NSButton(
            title: String(localized: "Merge"), target: self, action: #selector(confirmTapped))
        btn.bezelStyle = .push
        btn.keyEquivalent = "\r"
        btn.controlSize = .small
        if #available(macOS 26, *) { btn.borderShape = .capsule }
        return btn
    }()

    private lazy var cancelButton: NSButton = {
        let btn = NSButton(
            title: String(localized: "Cancel"), target: self, action: #selector(cancelTapped))
        btn.bezelStyle = .push
        btn.keyEquivalent = "\u{1b}"
        btn.controlSize = .small
        if #available(macOS 26, *) { btn.borderShape = .capsule }
        return btn
    }()

    init(oldName: String, newName: String) {
        super.init(frame: .zero)
        setupUI(oldName: oldName, newName: newName)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(oldName: String, newName: String) {
        messageLabel.stringValue = String(localized: "Merge Tags?")
        infoLabel.stringValue = String(
            localized:
                "'\(newName)' already exists. All annotations from '\(oldName)' will be merged into '\(newName)'."
        )

        let buttonStack = NSStackView(views: [cancelButton, mergeButton])
        buttonStack.orientation = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8

        let mainStack = NSStackView(views: [messageLabel, infoLabel, buttonStack])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            mainStack.widthAnchor.constraint(equalToConstant: 250),
            buttonStack.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -12),
        ])
    }

    @objc private func confirmTapped() {
        onConfirm?()
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    deinit {
        print("TagMergeConfirmationView deinitialized")
        onConfirm = nil
        onCancel = nil
    }
}