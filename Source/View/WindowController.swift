//
//  WindowController.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//  Penyesuaian splitView dan restorable state
//

import Cocoa

class WindowController: NSWindowController {

    init() {
        super.init(window: nil)
        loadWindow()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func loadWindow() {
        let rect = NSRect(x: 335, y: 390, width: 1000, height: 600)
        let style: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        let window = MainWindow(
            contentRect: rect,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = "المكتبة"
        window.subtitle = ""
        window.setFrameAutosaveName("MainWindow")
        window.animationBehavior = .default
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }
        self.window = window
    }
    
    @IBAction override func newWindowForTab(_ sender: Any?) {
        // PERBAIKAN: Instance otomatis disimpan di windowDidLoad
        let newWindowController = WindowController()

        // Tambahkan sebagai tab
        if let newWindow = newWindowController.window as? MainWindow {
            window?.addTabbedWindow(newWindow, ordered: .above)
            newWindow.setupContentView(restoreState: false)
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
