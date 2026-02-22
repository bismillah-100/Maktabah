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
            .trackingSeparatorTafseer
        ]
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        let items: [NSToolbarItem.Identifier]
        if rtl {
            items = [
                .searchQuran,
                .trackingSeparatorQuran,
                .searchTafseer,
                .trackingSeparatorTafseer,
                .navSegment,
                .searchField
            ]
        } else {
            items = [
                .searchField,
                .navSegment,
                .trackingSeparatorTafseer,
                .searchTafseer,
                .trackingSeparatorQuran,
                .searchQuran
            ]
        }
        return [.flexibleSpace] + items
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .trackingSeparatorQuran:
            guard let splitView else {
                return NSToolbarItem(itemIdentifier: itemIdentifier)
            }
            let index = rtl ? 0 : 1
            return createTrackingSeparator(
                splitView,
                itemIdentifier: itemIdentifier,
                dividerIndex: index
            )
            
        case .trackingSeparatorTafseer:
            guard let splitView else {
                return NSToolbarItem(itemIdentifier: itemIdentifier)
            }
            let index = rtl ? 1 : 0
            return createTrackingSeparator(
                splitView,
                itemIdentifier: itemIdentifier,
                dividerIndex: index
            )
            
        case .navSegment:
            let item = navSegment ?? NSToolbarItem(itemIdentifier: itemIdentifier)
            if navSegment == nil {
                navSegment = item
                let control = makeNavSegment()
                item.label = "Navigation"
                item.paletteLabel = "Navigation"
                item.view = control
            }
            return item
            
        case .searchField:
            let item = searchCurrent ?? NSToolbarItem(itemIdentifier: itemIdentifier)
            if searchCurrent == nil {
                searchCurrent = item
                let button = makeToolbarButton(systemImageName: "doc.text.magnifyingglass")
                item.label = "Search In Book"
                item.paletteLabel = "Search In Current Book"
                item.view = button
                item.menuFormRepresentation = makeMenuItem(
                    title: item.label,
                    imageName: "doc.text.magnifyingglass"
                )
            }
            return item
            
        case .searchQuran:
            let item = searchQuran ?? NSToolbarItem(itemIdentifier: itemIdentifier)
            if searchQuran == nil {
                searchQuran = item
                let button = makeToolbarButton(systemImageName: "text.magnifyingglass.rtl")
                item.label = "Search Quran"
                item.paletteLabel = "Search Quran"
                item.view = button
                item.menuFormRepresentation = makeMenuItem(
                    title: item.label,
                    imageName: "text.magnifyingglass.rtl"
                )
            }
            return item
            
        case .searchTafseer:
            let item = searchTafseer ?? NSToolbarItem(itemIdentifier: itemIdentifier)
            if searchTafseer == nil {
                searchTafseer = item
                let field = makeTafseerSearchField()
                item.label = "Search Tafseer"
                item.paletteLabel = "Search Tafseer"
                item.view = field
            }
            return item
            
        case .flexibleSpace:
            return NSToolbarItem(itemIdentifier: .flexibleSpace)
        case .space:
            return NSToolbarItem(itemIdentifier: .space)
        default:
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
    }
    
    private func createTrackingSeparator(_ splitView: NSSplitView, itemIdentifier: NSToolbarItem.Identifier, dividerIndex: Int) -> NSTrackingSeparatorToolbarItem {
        // ViewerSplitVC punya 2 items (IbarotTextVC dan SidebarVC)
        // Jadi hanya ada 1 divider di index 0
        let trackingSeparator = NSTrackingSeparatorToolbarItem(
            identifier: itemIdentifier,
            splitView: splitView,
            dividerIndex: dividerIndex // Index 0 untuk divider antara item pertama dan kedua
        )
        
        return trackingSeparator
    }
    
    private func makeNavSegment() -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = 2
        control.segmentStyle = .texturedRounded
        control.trackingMode = .momentary
        control.userInterfaceLayoutDirection = .leftToRight
        control.setImage(ReusableFunc.systemImage(named: "arrow.left"), forSegment: 0)
        control.setImage(ReusableFunc.systemImage(named: "arrow.right"), forSegment: 1)
        control.setWidth(23, forSegment: 0)
        control.setWidth(23, forSegment: 1)
        return control
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
