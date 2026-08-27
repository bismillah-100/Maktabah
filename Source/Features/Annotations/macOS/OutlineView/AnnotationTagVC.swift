//
//  AnnotationTagVC.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 27/04/26.
//

import AppKit

class AnnotationTagVC: NSViewController {
    enum Mode {
        case add
        case remove

        var title: String {
            switch self {
            case .add: return String(localized: "Add Tags")
            case .remove: return String(localized: "Remove Tags")
            }
        }

        var placeholder: String {
            switch self {
            case .add: return "Add tags".localized + "..."
            case .remove: return "Remove tags".localized + "..."
            }
        }

        var actionTitle: String {
            switch self {
            case .add: return "Add".localized
            case .remove: return "Remove".localized
            }
        }
    }

    var mode: Mode = .add
    var annotationIDs: [Int64] = []
    var availableTags: [String] = [] {
        didSet {
            if isViewLoaded {
                applyFilter(tokenField.stringValue)
            }
        }
    }

    var onSubmit: ((Mode, [String], [Int64]) -> Void)?
    var onCancel: (() -> Void)?

    private var filteredTags: [String] = []
    private var lastTokenSnapshot: [String] = []
    private var lastEditorQuery: String = ""

    // MARK: - Subviews

    private lazy var headerLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .semibold
        )
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        return label
    }()

    private lazy var selectionLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .tertiaryLabelColor
        label.alignment = .right
        return label
    }()

    private lazy var headerRow: NSStackView = {
        let stack = NSStackView(views: [headerLabel, selectionLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        return stack
    }()

    lazy var tokenField: NSTokenField = {
        let v = NSTokenField(frame: .zero)
        v.controlSize = .small
        v.target = self
        v.tokenStyle = .squared
        v.maximumNumberOfLines = 3
        v.lineBreakMode = .byWordWrapping
        v.usesSingleLineMode = false
        v.autoresizingMask = [.height]
        v.action = #selector(applyTapped(_:))
        return v
    }()

    lazy var tableView: NSTableView = {
        let t = NSTableView(frame: .zero)
        t.allowsMultipleSelection = true
        t.headerView = nil
        t.target = self
        t.selectionHighlightStyle = .none
        t.gridStyleMask = [.solidHorizontalGridLineMask]
        t.doubleAction = #selector(tableRowDoubleClicked(_:))
        t.backgroundColor = .clear
        let column = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("TagColumn")
        )
        column.resizingMask = .autoresizingMask
        t.addTableColumn(column)
        return t
    }()

    lazy var scrollView: NSScrollView = {
        let s = NSScrollView(frame: .zero)
        s.autohidesScrollers = true
        s.automaticallyAdjustsContentInsets = true
        s.hasVerticalScroller = true
        s.drawsBackground = false
        s.backgroundColor = .clear
        s.documentView = tableView
        return s
    }()

    private lazy var applyButton: NSButton = {
        let button = NSButton(
            title: "",
            target: self,
            action: #selector(applyTapped(_:))
        )
        button.controlSize = .small
        if #available(macOS 26, *) {
            button.borderShape = .capsule
        }
        button.keyEquivalent = "\r"
        button.bezelStyle = .push
        return button
    }()

    private lazy var stackView: NSStackView = {
        let s = NSStackView(views: [
            headerRow, tokenField, scrollView, applyButton,
        ])
        s.orientation = .vertical
        s.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        s.distribution = .fill
        s.spacing = 6
        return s
    }()

    private var scrollViewHeightConstraint: NSLayoutConstraint?
    private var tokenFieldHeightConstraint: NSLayoutConstraint?

    // MARK: - Lifecycle

    override func loadView() {
        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 260, height: 300)
        )
        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        // Buat dan simpan constraint tinggi
        let heightConstraint = scrollView.heightAnchor.constraint(
            equalToConstant: 150
        )
        scrollViewHeightConstraint = heightConstraint

        let tokenHeightConstraint = tokenField.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 24
        )
        self.tokenFieldHeightConstraint = tokenHeightConstraint

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor
            ),
            stackView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor
            ),
            stackView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor
            ),
            applyButton.widthAnchor.constraint(
                equalTo: stackView.widthAnchor,
                constant: -20
            ),
            tokenHeightConstraint,
            heightConstraint,
        ])
        view = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ReusableFunc.registerNib(
            tableView: tableView,
            nibName: .tagNib,
            cellIdentifier: .tagCell
        )

        tableView.delegate = self
        tableView.dataSource = self
        tokenField.delegate = self
        
        configureForMode()
        applyFilter(nil)
        updateSelectionLabel()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(tokenField)
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear()
        onCancel?()
    }

    deinit {
        onSubmit = nil
        onCancel = nil
        #if DEBUG
            print("deinit AnnotationTagVC")
        #endif
    }

    // MARK: - Dynamic Sizing

    private func updateTokenFieldHeight() {
        guard let constraint = tokenFieldHeightConstraint else { return }

        // Hitung lebar available (lebar stackView dikurangi edgeInsets)
        let availableWidth = stackView.bounds.width
            - stackView.edgeInsets.left
            - stackView.edgeInsets.right

        guard availableWidth > 0 else { return }

        // Minta NSTokenField hitung tinggi ideal untuk lebar tersebut
        let fittingHeight = tokenField.sizeThatFits(
            NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
        ).height

        let minHeight: CGFloat = 24
        let maxHeight: CGFloat = 120
        let clamped = max(minHeight, min(fittingHeight, maxHeight))

        if abs(constraint.constant - clamped) > 0.5 {
            constraint.constant = clamped
        }
    }

    private func updateDynamicHeight() {
        updateTokenFieldHeight()
        view.layoutSubtreeIfNeeded()

        // 1. Hitung tinggi tabel
        let rowHeight: CGFloat = tableView.rowHeight
        let tableContentHeight = CGFloat(filteredTags.count) * rowHeight

        // 2. Tentukan batas tinggi (Clamping)
        let maxTableHeight: CGFloat = 250.0
        let clampedTableHeight = tableView.numberOfRows > 0
            ? min(tableContentHeight, maxTableHeight) + 12
            : 0

        // 3. Update constraint tinggi scrollView
        scrollViewHeightConstraint?.constant = clampedTableHeight

        // 4. Tentukan batas lebar (MinWidth)
        // fittingSize akan mengambil lebar ideal berdasarkan isi (label, button, dll)
        let currentFittingSize = stackView.fittingSize
        let minWidth: CGFloat = 220.0  // Atur lebar minimal yang diinginkan

        let finalWidth = max(minWidth, currentFittingSize.width)
        let finalHeight = currentFittingSize.height

        // 5. Perubahan ukuran Popover
        // Update preferredContentSize dengan lebar minimal
        preferredContentSize = NSSize(width: finalWidth, height: finalHeight)
        view.layoutSubtreeIfNeeded()
    }

    // MARK: - Configuration

    private func configureForMode() {
        headerLabel.stringValue = mode.title.uppercased()
        tokenField.placeholderString = mode.placeholder
        applyButton.title = mode.actionTitle
    }

    private func updateSelectionLabel() {
        guard let tokens = tokenField.objectValue as? [String] else { return }
        let count = tokens.count
        selectionLabel.stringValue = count > 0 ? "\(count) selected" : ""
    }

    private func syncTokenFieldWithSelection() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, filteredTags.indices.contains(selectedRow) else { return }
        
        var tokens = (tokenField.objectValue as? [String]) ?? []
        let selectedTag = filteredTags[selectedRow]
        
        guard !tokens.contains(selectedTag) else { return }
        tokens.append(selectedTag)
        tokenField.objectValue = tokens
    }
    
    // MARK: - Filtering

    private func currentTokens() -> Set<String> {
        if let tokens = tokenField.objectValue as? [String] {
            return Set(tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        return []
    }

    private func tokenSnapshot() -> [String] {
        ((tokenField.objectValue as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func applyFilter(_ query: String?) {
        let activeTokens = currentTokens()
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        var base = availableTags.filter { !activeTokens.contains($0) }
        
        if !trimmed.isEmpty {
            base = base.filter { $0.localizedStandardContains(trimmed) }
        }
        
        filteredTags = base
        lastTokenSnapshot = tokenSnapshot()
        lastEditorQuery = trimmed
        updateSelectionLabel()
        tableView.reloadData()
        updateDynamicHeight()
    }
    
    // MARK: - Tag resolution

    private func normalizedInputTags() -> [String] {
        if let tokens = tokenField.objectValue as? [String] {
            return
                tokens
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let text = tokenField.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else { return [] }
        return
            text
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func tagsToSubmit() -> [String] {
        let enteredTags = normalizedInputTags()
        if !enteredTags.isEmpty { return enteredTags }

        let selectedRows = tableView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return [] }
        return selectedRows.compactMap {
            filteredTags.indices.contains($0) ? filteredTags[$0] : nil
        }
    }

    // MARK: - Actions

    @objc private func applyTapped(_ sender: Any?) {
        let tags = tagsToSubmit()
        guard !tags.isEmpty else { return }
        onSubmit?(mode, tags, annotationIDs)
    }

    @objc private func tableRowDoubleClicked(_ sender: Any?) {
        let clickedRow = tableView.clickedRow
        guard filteredTags.indices.contains(clickedRow) else { return }
        var rows = tableView.selectedRowIndexes
        if !rows.contains(clickedRow) { rows = IndexSet(integer: clickedRow) }
        let tags = rows.compactMap {
            filteredTags.indices.contains($0) ? filteredTags[$0] : nil
        }
        guard !tags.isEmpty else { return }
        onSubmit?(mode, tags, annotationIDs)
    }
}

// MARK: - NSTableViewDataSource

extension AnnotationTagVC: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredTags.count
    }
}

// MARK: - NSTableViewDelegate

extension AnnotationTagVC: NSTableViewDelegate {
    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard
            let cell = tableView.makeView(
                withIdentifier: NSUserInterfaceItemIdentifier(
                    CellIViewIdentifier.tagCell.rawValue
                ),
                owner: self
            ) as? NSTableCellView,
            filteredTags.indices.contains(row),
            let textField = cell.textField
        else {
            return nil
        }

        textField.stringValue = filteredTags[row]
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        syncTokenFieldWithSelection()
        updateSelectionLabel()
        applyFilter(nil)
    }
}

// MARK: - NSTokenFieldDelegate / NSTextFieldDelegate

extension AnnotationTagVC: NSTokenFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let query = ((tokenField.currentEditor() as? NSTextView)?.string ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentSnapshot = tokenSnapshot()

        if currentSnapshot != lastTokenSnapshot {
            applyFilter(nil)
            return
        }

        if query != lastEditorQuery {
            applyFilter(query)
        }
    }

    func tokenField(
        _ tokenField: NSTokenField,
        shouldAdd tokens: [Any],
        at index: Int
    ) -> [Any] {
        DispatchQueue.main.async { [weak self] in
            self?.applyFilter("")
        }
        return tokens
    }
}
