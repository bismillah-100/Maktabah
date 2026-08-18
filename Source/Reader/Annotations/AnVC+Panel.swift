//
//  AnVC+Panel.swift
//  Maktabah
//

import Cocoa

extension AnnotationsVC {
    @IBAction func floatPanel(_ sender: NSMenuItem) {
        let currentState = floatMenuItem.state
        floatMenuItem.state = currentState == .on ? .off : .on
        let on = floatMenuItem.state == .on
        Self.panel?.isFloatingPanel = on
        UserDefaults.standard.annotationFloatWindow = on
    }

    @IBAction func hideOnPanel(_ sender: NSMenuItem) {
        let currentState = hideOnMenuItem.state
        hideOnMenuItem.state = currentState == .on ? .off : .on
        let on = sender.state == .on
        Self.panel?.hidesOnDeactivate = on
        UserDefaults.standard.annotationHideWindow = on
    }

    @IBAction func revealInFinder(_ sender: Any?) {
        if let annotationsFolder = AppConfig.folder(for: AppConfig.annotationsAndResultsFolder) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: annotationsFolder.path)
        }
    }

    @IBAction func openInNewWindow(_ sender: Any) {
        view.window?.makeFirstResponder(nil)
        SharedPopover.annotationsPopover.performClose(sender)
        DispatchQueue.main.async { [weak self] in self?.openAsPanel() }
    }
}

extension AnnotationsVC: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        tagPopover?.performClose(nil)
        SharedPopover.annotationsVC = nil
        SharedPopover.annotationsPopover.contentViewController = nil
        Self.panel?.delegate = nil
        Self.panel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        outlineView.deselectAll(nil)
        removeScopePanelFromWindow()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if !searchField.stringValue.isEmpty { updateAndShowScopePanel() }
    }
}
