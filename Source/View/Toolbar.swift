//
//  Toolbar.swift
//  maktab
//
//  Created by MacBook on 07/12/25.
//

import Cocoa

/*
 class MyToolbar: NSToolbar, NSToolbarDelegate {
     func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
         [
             .modeSelector,
             .sidebarTrackingSeparator,
             .sidebarLeading,
             .searchSidebarLeadingContent,
             .bookInfo,
             .navSegment,
             .copyDetails,
             .displayNotations, // hanya SEKALI
             .searchField,
             .bookmark,
             .insertBookmark,
             .pageSlider,
             .textViewOptions,
             .trackingSeparator,
             .flexibleSpace,
             .searchContents,
             .sidebarTrailing
         ]
     }

     func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
         [
             .modeSelector,
             .sidebarTrackingSeparator,
             .sidebarLeading,
             .searchSidebarLeadingContent,
             .bookInfo,
             .navSegment,
             .copyDetails,
             .displayNotations, // hanya SEKALI
             .searchField,
             .bookmark,
             .insertBookmark,
             .pageSlider,
             .textViewOptions,
             .trackingSeparator,
             .flexibleSpace,
             .searchContents,
             .sidebarTrailing
         ]
     }

     func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
         guard let window = NSApp.mainWindow as? MainWindow else { return nil }
         return toolbarItem(for: itemIdentifier, in: window)
     }

     func toolbarItem(
         for itemIdentifier: NSToolbarItem.Identifier,
         in window: MainWindow
     ) -> NSToolbarItem? {
         let item = NSToolbarItem(itemIdentifier: itemIdentifier)
         switch itemIdentifier {
         case .sidebarTrackingSeparator:
             return NSToolbarItem()
         case .trackingSeparator:
             // Dapatkan ViewerSplitVC yang benar
             guard let rootSplitVC = window.contentViewController as? RootSplitView,
                   let viewerContainer = rootSplitVC.viewerSplitVC else {
                 return nil
             }

             // ViewerSplitVC punya 2 items (IbarotTextVC dan SidebarVC)
             // Jadi hanya ada 1 divider di index 0
             let trackingSeparator = NSTrackingSeparatorToolbarItem(
                 identifier: itemIdentifier,
                 splitView: viewerContainer.splitView,
                 dividerIndex: 0  // Index 0 untuk divider antara item pertama dan kedua
             )

             return trackingSeparator

         case .modeSelector:
             return customToolbarItem(
                 itemForItemIdentifier: .modeSelector,
                 label: "Switch Mode", paletteLabel: "", toolTip: "",
                 itemContent: window.modeSegmentToolbarItem.view ?? NSView()
             )
         case .sidebarLeading:
             return customToolbarItem(itemForItemIdentifier: .sidebarLeading, label: "Sidebar", paletteLabel: "", toolTip: "", itemContent: window.sidebarLeading.view ?? NSView()
             )
         case .searchField:
             return customToolbarItem(itemForItemIdentifier: .searchField, label: "Search In Book", paletteLabel: "", toolTip: "", itemContent: window.searchBook.view ?? NSView())
         case .searchSidebarLeadingContent:
             return customToolbarItem(itemForItemIdentifier: .searchSidebarLeadingContent, label: "Search Book", paletteLabel: "", toolTip: "", itemContent: window.searchSidebarLeading.view ?? NSView())
         case .bookInfo:
             return customToolbarItem(itemForItemIdentifier: .bookInfo, label: "Book Info", paletteLabel: "", toolTip: "", itemContent: window.bookInfo.view ?? NSView())
         case .navSegment:
             return customToolbarItem(itemForItemIdentifier: .navSegment, label: "Navigation", paletteLabel: "", toolTip: "", itemContent: window.navSegment.view ?? NSView())
         case .copyDetails:
             return customToolbarItem(itemForItemIdentifier: .copyDetails, label: "Copy", paletteLabel: "", toolTip: "", itemContent: window.copyWith.view ?? NSView())
         case .displayNotations:
             return customToolbarItem(itemForItemIdentifier: .displayNotations, label: "All Anotations", paletteLabel: "", toolTip: "", itemContent: window.displayAnnotations.view ?? NSView())
         case .bookmark:
             return customToolbarItem(itemForItemIdentifier: .bookmark, label: "Bookmark", paletteLabel: "", toolTip: "", itemContent: window.displayBookmark.view ?? NSView())
         case .insertBookmark:
             return customToolbarItem(itemForItemIdentifier: .insertBookmark, label: "Save Results", paletteLabel: "", toolTip: "", itemContent: window.insertBookmark.view ?? NSView())
         case .pageSlider:
             return customToolbarItem(itemForItemIdentifier: .pageSlider, label: "Navigation Page", paletteLabel: "", toolTip: "", itemContent: window.navigationPage.view ?? NSView())
         case .textViewOptions:
             return customToolbarItem(itemForItemIdentifier: .textViewOptions, label: "View Options", paletteLabel: "", toolTip: "", itemContent: window.viewOpt.view ?? NSView())
         case .searchContents:
             return customToolbarItem(itemForItemIdentifier: .searchContents, label: "Search Contents", paletteLabel: "", toolTip: "", itemContent: window.searchSidebarTrailing.view ?? NSView())
         case .sidebarTrailing:
             return customToolbarItem(itemForItemIdentifier: .sidebarTrailing, label: "Contents", paletteLabel: "", toolTip: "", itemContent: window.sidebarTrailing.view ?? NSView())
         default:
             return item
         }
     }

     // Fallback item untuk palette / snapshot — harus non-nil dan stabil
     private func fallbackToolbarItem(for id: NSToolbarItem.Identifier) -> NSToolbarItem {
         let item = NSToolbarItem(itemIdentifier: id)

         // Minimal: atur label/paletteLabel supaya snapshot tak mengakses nil string
         item.label = id.rawValue
         item.paletteLabel = id.rawValue
         item.toolTip = ""

         // Berikan menuFormRepresentation supaya config panel punya sesuatu
         let menuItem = NSMenuItem(title: item.label, action: nil, keyEquivalent: "")
         item.menuFormRepresentation = menuItem

         // Jika id adalah fleksible/space/separator kembalikan item standar
         if id == .flexibleSpace { return NSToolbarItem(itemIdentifier: .flexibleSpace) }
         if id == .space { return NSToolbarItem(itemIdentifier: .space) }

         // Untuk item visual yang biasanya view-based, set view placeholder
         let placeholder = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
         item.view = placeholder

         return item
     }

     /// - Tag: CustomToolbarItem
     func customToolbarItem(
         itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
         label: String,
         paletteLabel: String,
         toolTip: String,
         itemContent: AnyObject
     ) -> NSToolbarItem? {
         let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)

         toolbarItem.label = label
         toolbarItem.paletteLabel = paletteLabel
         toolbarItem.toolTip = toolTip
         toolbarItem.target = self

         // Set the right attribute, depending on if we were given an image or a view.
         if itemContent is NSImage {
             if let image = itemContent as? NSImage {
                 toolbarItem.image = image
             }
         } else if itemContent is NSView {
             if let view = itemContent as? NSView {
                 toolbarItem.view = view
             }
         } else {
             assertionFailure("Invalid itemContent: object")
         }

         // We actually need an NSMenuItem here, so we construct one.
         let menuItem = NSMenuItem()
         menuItem.submenu = nil
         menuItem.title = label
         toolbarItem.menuFormRepresentation = menuItem

         return toolbarItem
     }
 }
 */

extension NSToolbarItem.Identifier {
    // Mode Selector - SELALU ADA
    static let modeSelector = NSToolbarItem.Identifier("modeSelector")

    // VIEWER MODE
    static let navSegment = NSToolbarItem.Identifier("navSegment")
    static let pageSlider = NSToolbarItem.Identifier("pageSlider")
    
    static let textViewOptions = NSToolbarItem.Identifier("textViewOptions")
    static let bookInfo = NSToolbarItem.Identifier("bookInfo") // Sudah ada action

    // SIDEBAR
    static let sidebarLeading = NSToolbarItem.Identifier("sidebarLeading")
    static let sidebarTrailing = NSToolbarItem.Identifier("sidebarTrailing")
    static let searchSidebarLeadingContent = NSToolbarItem.Identifier("searchSidebarLeadingContent")

    // SEARCH
    // static let searchMode = NSToolbarItem.Identifier("searchSegment")
    static let searchField = NSToolbarItem.Identifier("searchField")

    // static let bookmark = NSToolbarItem.Identifier("bookmark")
    // static let insertBookmark = NSToolbarItem.Identifier("insertBookmark")
    static let copyDetails = NSToolbarItem.Identifier("copyDetails")

    static let displayNotations = NSToolbarItem.Identifier("displayAllNotations")

    // static let startSearch = NSToolbarItem.Identifier("startSearch")
    // static let pauseSearch = NSToolbarItem.Identifier("pauseSearch")
    // static let stopSearch = NSToolbarItem.Identifier("stopSearch")

    // static let settings = NSToolbarItem.Identifier("settings")
    static let trackingSeparator = NSToolbarItem.Identifier("TrackingSeparator")
    static let searchContents = NSToolbarItem.Identifier("searchTableOfContents")
}


extension NSToolbar {
    func item(with identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        items.first { $0.itemIdentifier == identifier }
    }
}

extension NSView {
    func setTargetAction(_ target: AnyObject?, _ action: Selector?) {
        if let button = self as? NSButton {
            button.target = target
            button.action = action
        } else if let segmented = self as? NSSegmentedControl {
            segmented.target = target
            segmented.action = action
        }
    }
}
