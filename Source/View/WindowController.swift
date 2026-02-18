//
//  WindowController.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//  Penyesuaian splitView dan restorable state
//

import Cocoa

class WindowController: NSWindowController {

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.toolbar?.delegate = self
    }
    
    @IBAction override func newWindowForTab(_ sender: Any?) {
        // PERBAIKAN: Instance otomatis disimpan di windowDidLoad
        let newWindowController = WindowController(windowNibName: "WindowController")

        // Tambahkan sebagai tab
        if let newWindow = newWindowController.window as? MainWindow {
            window?.addTabbedWindow(newWindow, ordered: .above)
            newWindow.setupContentView(restoreState: false)
            newWindow.setupView()
            newWindow.makeKeyAndOrderFront(nil)
        }
    }

    static func showPopOver(sender: NSButton, viewController: NSViewController) {
        let popover = NSPopover()

        popover.contentViewController = viewController
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        popover.behavior = .transient
    }

    deinit {
        #if DEBUG
        print("WindowController deinit - This should only happen on close")
        #endif
    }
}


extension WindowController: NSToolbarDelegate {
/*
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .modeSelector,
            .sidebarTrackingSeparator,
            .sidebarLeading,
            .searchSidebarLeadingContent,
            .bookInfo,
            .navSegment,
            .copyDetails,
            .displayNotations,
            .searchField,
            .pageSlider,
            .textViewOptions,
            .trackingSeparator,
            .searchContents,
            .sidebarTrailing
        ]
    }
*/

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .sidebarLeading,
            .searchSidebarLeadingContent,
            .sidebarTrackingSeparator,
            .modeSelector,
            .bookInfo,
            .textViewOptions,
            .copyDetails,
            .navSegment,
            .searchField,
            .pageSlider,
            .displayNotations,
            .trackingSeparator,
            .searchContents,
            .sidebarTrailing
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .trackingSeparator:

            guard flag else {
                return NSToolbarItem(itemIdentifier: itemIdentifier)
            }

            guard let mainWindow = window as? MainWindow,
                  let rootSplitVC = mainWindow.contentViewController as? SplitVC else {
                return NSToolbarItem(itemIdentifier: itemIdentifier)
            }

            let viewerContainer = rootSplitVC.viewerSplitVC
            // ViewerSplitVC punya 2 items (IbarotTextVC dan SidebarVC)
            // Jadi hanya ada 1 divider di index 0
            let trackingSeparator = NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: viewerContainer.splitView,
                dividerIndex: 0  // Index 0 untuk divider antara item pertama dan kedua
            )

            return trackingSeparator
        default:
            break
        }

        return item
    }
}
