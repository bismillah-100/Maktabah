//
//  AnVC+TagFilter.swift
//  Maktabah
//

import Cocoa
import SwiftUI

extension AnnotationsVC {
    private var isAnd: Bool {
        dataSource.viewModel.tagFilterMode == .and
    }

    private var scrollRightEdge: DispatchWorkItem {
        DispatchWorkItem { [weak self] in
            self?.scrollToRightEdge()
        }
    }

    func createTagFilterBar() -> NSStackView {
        let heightConstant: CGFloat = 20
        let leftInset: CGFloat = 8

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.alignment = .centerY
        bar.edgeInsets.right = leftInset
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: heightConstant).isActive = true

        // Filter button
        let filterBtn = NSButton()
        filterBtn.bezelStyle = .toolbar
        filterBtn.image = .init(systemSymbolName: "tag", accessibilityDescription: "Filter Tags")
        filterBtn.isBordered = false
        filterBtn.target = self
        filterBtn.action = #selector(showTagSelectionPopover(_:))
        filterBtn.toolTip = "Filter Tags".localized
        filterBtn.setContentHuggingPriority(.required, for: .horizontal)
        filterBtn.translatesAutoresizingMaskIntoConstraints = false
        filterBtn.widthAnchor.constraint(equalToConstant: 23).isActive = true
        filterButton = filterBtn

        // Mode button (AND/OR toggle)
        let modeBtn = NSButton()
        modeBtn.bezelStyle = .accessoryBar
        modeBtn.setButtonType(.pushOnPushOff)
        modeBtn.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Filter Mode")
        modeBtn.isBordered = false
        modeBtn.target = self
        modeBtn.action = #selector(toggleFilterMode(_:))
        modeBtn.toolTip = .init(localized: isAnd ? .and : .or)
        modeBtn.setContentHuggingPriority(.required, for: .horizontal)
        modeBtn.translatesAutoresizingMaskIntoConstraints = false
        modeBtn.widthAnchor.constraint(equalToConstant: 23).isActive = true
        modeButton = modeBtn

        // Chips scroll view
        let chipsStack = NSStackView(
            frame: NSRect(x: 0, y: 0, width: 100, height: heightConstant)
        )
        chipsStack.userInterfaceLayoutDirection = .rightToLeft
        chipsStack.orientation = .horizontal
        chipsStack.alignment = .centerY
        chipsStack.spacing = 4
        chipsStack.translatesAutoresizingMaskIntoConstraints = true
        chipsStack.autoresizingMask = [.height]
        chipsStackView = chipsStack

        let chipScroll = NSScrollView()
        chipScroll.userInterfaceLayoutDirection = .rightToLeft
        chipScroll.hasHorizontalScroller = false
        chipScroll.hasVerticalScroller = false
        chipScroll.horizontalScrollElasticity = .allowed
        chipScroll.verticalScrollElasticity = .none
        chipScroll.drawsBackground = false
        chipScroll.heightAnchor.constraint(equalToConstant: heightConstant).isActive = true

        let clipView = RightAlignedClipView()
        clipView.userInterfaceLayoutDirection = .rightToLeft
        clipView.drawsBackground = false
        clipView.automaticallyAdjustsContentInsets = false
        clipView.contentInsets.left = leftInset
        clipView.contentInsets.right = leftInset
        chipScroll.contentView = clipView
        chipScroll.documentView = chipsStack
        chipsScrollView = chipScroll

        bar.addArrangedSubview(chipScroll)
        bar.addArrangedSubview(modeBtn)
        bar.addArrangedSubview(filterBtn)

        tagFilterBar = bar
        return bar
    }

    func makeChipButton(for tag: String) -> NSButton {
        let btn = NSButton()
        btn.title = tag
        btn.setButtonType(.pushOnPushOff)
        btn.bezelStyle = .push
        btn.isBordered = true
        btn.font = .systemFont(ofSize: 12)
        btn.target = self
        btn.action = #selector(chipToggled(_:))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setContentHuggingPriority(.required, for: .vertical)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .vertical)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        btn.heightAnchor.constraint(equalToConstant: 20).isActive = true
        if #available(macOS 26, *) { btn.borderShape = .capsule }
        return btn
    }

    /// Incrementally update chips: add new, remove stale, preserve existing
    func updateChips(allTags: [String]) {
        guard let chipsStack = chipsStackView else { return }
        let isFirstLoad = !hasPerformedInitialChipScroll && !allTags.isEmpty

        NSAnimationContext.runAnimationGroup { [weak self] ctx in
            guard let self else { return }
            ctx.allowsImplicitAnimation = true
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)

            let existingChips = chipsStack.arrangedSubviews.compactMap { $0 as? NSButton }
            let existingTitles = Set(existingChips.map(\.title))
            let newTagsSet = Set(allTags)

            // Remove chips whose tags no longer exist
            for chip in existingChips where !newTagsSet.contains(chip.title) {
                chipsStack.removeArrangedSubview(chip)
                chip.removeFromSuperview()
            }

            // Add new chips (insert in sorted order)
            for tag in allTags where !existingTitles.contains(tag) {
                let chip = makeChipButton(for: tag)
                chip.state = dataSource.viewModel.selectedTags.contains(tag) ? .on : .off
                let insertIdx = chipsStack
                    .arrangedSubviews.compactMap { $0 as? NSButton }.enumerated()
                    .first { tag.localizedCaseInsensitiveCompare($0.element.title) == .orderedAscending }?
                    .offset ?? chipsStack.arrangedSubviews.count
                chipsStack.insertArrangedSubview(chip, at: insertIdx)
            }

            // Sync selection state of existing chips
            for chip in chipsStack.arrangedSubviews.compactMap({ $0 as? NSButton }) {
                chip.state = dataSource.viewModel.selectedTags.contains(chip.title) ? .on : .off
            }

            tagFilterBar?.isHidden = allTags.isEmpty
            chipsStack.invalidateIntrinsicContentSize()
            chipsStack.layoutSubtreeIfNeeded()
            (chipsScrollView?.contentView as? RightAlignedClipView)?.updateDocumentFrame()
        } completionHandler: { [weak self] in
            guard let self else { return }
            if isFirstLoad {
                hasPerformedInitialChipScroll = true
                DispatchQueue.main.async(execute: scrollRightEdge)
            }
        }
    }

    func scrollToRightEdge() {
        guard let chipScroll = chipsScrollView, let docView = chipScroll.documentView else { return }
        let clipView = chipScroll.contentView
        (clipView as? RightAlignedClipView)?.updateDocumentFrame()
        let insets = clipView.contentInsets
        let docWidth = docView.frame.width
        let clipWidth = clipView.bounds.width
        let minX = -insets.left
        let maxX = max(minX, docWidth - clipWidth + insets.right)
        clipView.scroll(to: NSPoint(x: maxX, y: 0))
        chipScroll.reflectScrolledClipView(clipView)
    }

    @objc func chipToggled(_ sender: NSButton) {
        dataSource.viewModel.toggleTagSelection(sender.title)
        if isAnd {
            DispatchQueue.main.async(execute: scrollRightEdge)
        }
    }

    @objc func toggleFilterMode(_ sender: NSButton) {
        dataSource.viewModel.toggleTagFilterMode()
        sender.toolTip = .init(localized: isAnd ? .and : .or)
        let color: NSColor = isAnd ? .controlAccentColor : .controlTextColor
        let config = NSImage.SymbolConfiguration(hierarchicalColor: color)
        sender.image = NSImage(
            systemSymbolName: "line.3.horizontal.decrease",
            accessibilityDescription: "Filter Mode"
        )?.withSymbolConfiguration(config)

        DispatchQueue.main.async(execute: scrollRightEdge)
    }

    @objc func showTagSelectionPopover(_ sender: NSButton) {
        tagSelectionPopover?.performClose(nil)

        let allTags = dataSource.viewModel.allTags
        guard !allTags.isEmpty else { return }

        let isAndMode = dataSource.viewModel.tagFilterMode == .and
        let selectedTags = dataSource.viewModel.selectedTags
        let hostingVC = NSHostingController(
            rootView: TagFilterSelectionView(
                allTags: allTags,
                selectedTags: selectedTags,
                isAndMode: isAndMode,
                availableTagsProvider: { [weak self] tags in
                    self?.dataSource.viewModel.availableTags(for: tags) ?? []
                },
                onToggle: { [weak self] tag in
                    self?.dataSource.viewModel.toggleTagSelection(tag)
                    self?.updateChips(allTags: self?.dataSource.viewModel.availableTags ?? [])
                },
                onSelectAll: { [weak self] in
                    guard let self else { return }
                    dataSource.viewModel.selectedTags = Set(dataSource.viewModel.availableTags)
                    updateChips(allTags: dataSource.viewModel.availableTags)
                },
                onDeselectAll: { [weak self] in
                    guard let self else { return }
                    dataSource.viewModel.selectedTags = []
                    updateChips(allTags: dataSource.viewModel.availableTags)
                }
            )
        )
        hostingVC.preferredContentSize = NSSize(width: 250, height: 300)

        let popover = NSPopover()
        popover.contentViewController = hostingVC
        popover.behavior = .transient
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        tagSelectionPopover = popover
    }
}
