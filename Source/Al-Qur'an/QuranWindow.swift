//
//  QuranWindow.swift
//  maktab
//
//  Created by MacBook on 24/12/25.
//

import Cocoa

class QuranWindow: NSWindow {
    private var toolbarConfigured = false

    private(set) var navSegment: NSToolbarItem!
    private(set) var searchCurrent: NSToolbarItem!
    private(set) var searchQuran: NSToolbarItem!
    private(set) var searchTafseer: NSToolbarItem!

    weak var splitView: NSSplitView! {
        didSet {
            // Panggil setup toolbar di sini setelah splitView tersedia
            setupToolbar()
        }
    }

    var rtl: Bool {
        MainWindow.rtl
    }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        commonInit()
    }

    private func commonInit() {
        titleVisibility = rtl ? .hidden : .visible
    }

    private func setupToolbar() {
        guard !toolbarConfigured else { return }
        let mainToolbar = NSToolbar(identifier: NSToolbar.Identifier("QuranToolbar"))
        mainToolbar.delegate = self
        mainToolbar.displayMode = .iconAndLabel
        mainToolbar.sizeMode = .regular
        mainToolbar.showsBaselineSeparator = false
        mainToolbar.allowsUserCustomization = false
        mainToolbar.autosavesConfiguration = false
        toolbar = mainToolbar
        toolbarConfigured = true
    }
}

extension QuranWindow: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .searchTafseer,
            .searchField,
            .navSegment,
            .searchQuran,
            .flexibleSpace,
            .space,
            .trackingSeparatorQuran,
            .trackingSeparatorTafseer,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        let items: [NSToolbarItem.Identifier] = if rtl {
            [
                .searchQuran,
                .trackingSeparatorQuran,
                .searchTafseer,
                .trackingSeparatorTafseer,
                .navSegment,
                .searchField,
            ]
        } else {
            [
                .searchField,
                .navSegment,
                .trackingSeparatorTafseer,
                .searchTafseer,
                .trackingSeparatorQuran,
                .searchQuran,
            ]
        }
        return [.flexibleSpace] + items
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .trackingSeparatorQuran:
            guard let splitView else { return NSToolbarItem(itemIdentifier: itemIdentifier) }
            let index = rtl ? 0 : 1
            return createTrackingSeparator(splitView, itemIdentifier: itemIdentifier, dividerIndex: index)
        case .trackingSeparatorTafseer:
            guard let splitView else { return NSToolbarItem(itemIdentifier: itemIdentifier) }
            let index = rtl ? 1 : 0
            return createTrackingSeparator(splitView, itemIdentifier: itemIdentifier, dividerIndex: index)
        case .navSegment:
            return makeNavSegmentItem(identifier: itemIdentifier)
        case .searchField, .searchQuran, .searchTafseer:
            return makeSearchToolbarItem(identifier: itemIdentifier)
        case .flexibleSpace:
            return NSToolbarItem(itemIdentifier: .flexibleSpace)
        case .space:
            return NSToolbarItem(itemIdentifier: .space)
        default:
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
    }

    private func makeNavSegmentItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = navSegment ?? NSToolbarItem(itemIdentifier: identifier)
        if navSegment == nil {
            navSegment = item
            let control = NSSegmentedControl.makeNavigationControl()
            item.label = "Navigation"
            item.paletteLabel = "Navigation"
            item.view = control
        }
        return item
    }

    private func makeSearchToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case .searchField:
            return configureButtonToolbarItem(
                existingItem: &searchCurrent,
                identifier: identifier,
                imageName: "doc.text.magnifyingglass",
                label: "Search In Book",
                paletteLabel: "Search In Current Book"
            )

        case .searchQuran:
            return configureButtonToolbarItem(
                existingItem: &searchQuran,
                identifier: identifier,
                imageName: "text.magnifyingglass.rtl",
                label: "Search Quran",
                paletteLabel: "Search Quran"
            )

        case .searchTafseer:
            let item = searchTafseer ?? NSToolbarItem(itemIdentifier: identifier)
            if searchTafseer == nil {
                searchTafseer = item
                let field = makeTafseerSearchField()
                item.label = "Search Tafseer"
                item.paletteLabel = "Search Tafseer"
                item.view = field
            }
            return item

        default:
            return nil
        }
    }

    private func configureButtonToolbarItem(
        existingItem: inout NSToolbarItem!,
        identifier: NSToolbarItem.Identifier,
        imageName: String,
        label: String,
        paletteLabel: String
    ) -> NSToolbarItem {
        let item = existingItem ?? NSToolbarItem(itemIdentifier: identifier)
        if existingItem == nil {
            existingItem = item
            let button = makeToolbarButton(systemImageName: imageName)
            item.label = label
            item.paletteLabel = paletteLabel
            item.view = button
            item.menuFormRepresentation = makeMenuItem(title: label, imageName: imageName)
        }
        return item
    }

    private func createTrackingSeparator(_ splitView: NSSplitView, itemIdentifier: NSToolbarItem.Identifier, dividerIndex: Int) -> NSTrackingSeparatorToolbarItem {
        NSTrackingSeparatorToolbarItem(
            identifier: itemIdentifier,
            splitView: splitView,
            dividerIndex: dividerIndex
        )
    }

    private func makeToolbarButton(systemImageName: String) -> NSButton {
        let image = ReusableFunc.systemImage(named: systemImageName)
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        return button
    }

    private func makeTafseerSearchField() -> NSSearchField {
        let field = NSSearchField()
        field.focusRingType = .none
        field.userInterfaceLayoutDirection = .rightToLeft
        field.usesSingleLineMode = true
        if let cell = field.cell as? NSSearchFieldCell {
            cell.baseWritingDirection = .rightToLeft
            cell.usesSingleLineMode = true
        }
        return field
    }

    private func makeMenuItem(title: String, imageName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = ReusableFunc.systemImage(named: imageName)
        return item
    }
}

extension NSToolbarItem.Identifier {
    static let searchQuran = NSToolbarItem.Identifier("searchQuran")
    static let searchTafseer = NSToolbarItem.Identifier("searchTafseer")
    static let trackingSeparatorQuran = NSToolbarItem.Identifier("trackingSeparatorQuran")
    static let trackingSeparatorTafseer = NSToolbarItem.Identifier("trackingSeparatorTafseer")
}
