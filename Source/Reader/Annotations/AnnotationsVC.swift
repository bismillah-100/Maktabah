//
//  AnnotationsVC.swift
//  maktab
//
//  Created by MacBook on 15/12/25.
//

import Cocoa

class AnnotationsVC: NSViewController {
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var shareBtn: NSButton!
    @IBOutlet weak var windowBtn: NSButton!
    @IBOutlet weak var setting: NSPopUpButton!
    @IBOutlet weak var floatMenuItem: NSMenuItem!
    @IBOutlet weak var hideOnMenuItem: NSMenuItem!
    @IBOutlet weak var searchField: DSFSearchField!
    @IBOutlet weak var xBtn: NSButton!

    @objc dynamic var isRowUnselected: Bool = true

    var floatPanel: Bool {
        UserDefaults.standard.annotationFloatWindow
    }

    var hideOnPanel: Bool {
        UserDefaults.standard.annotationHideWindow
    }

    static var panel: NSPanel?

    let dataSource: AnnotationOutlineDataSource = .init()
    var workItem: DispatchWorkItem?

    var popover: Bool = true
    var isDataLoaded = false

    override func viewDidLoad() {
        super.viewDidLoad()
        floatMenuItem.state = .on
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if isDataLoaded { return }
        ReusableFunc.showProgressWindow(view)
        xBtn.isHidden = popover
        dataSource.onSelectItem = { [weak self] row in
            self?.isRowUnselected = row == -1
        }
        outlineView.deselectAll(nil)
        dataSource.outlineView = outlineView

        Task { [weak self] in
            guard let self else { return }
            reloadAnnotations(nil)
            await MainActor.run { [weak self] in
                guard let self else { return }
                ReusableFunc.closeProgressWindow(view)
                ReusableFunc.setupSearchField(searchField)
                isDataLoaded = true
            }
        }
    }

    @IBAction func reloadAnnotations(_ sender: Any?) {
        if sender != nil {
            AnnotationManager.shared.connect()
        }
        dataSource.reload()
        outlineView.dataSource = dataSource
        outlineView.delegate = dataSource
        outlineView.usesAutomaticRowHeights = true
        // outlineView.reloadData()
    }

    @IBAction func searchFieldDidChange(_ sender: NSSearchField) {
        workItem?.cancel()
        let query = sender.stringValue
        workItem = DispatchWorkItem { [weak self, query] in
            guard let self else { return }
            dataSource.applySearchFilter(text: query)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                outlineView.reloadData()
                if !sender.stringValue.isEmpty {
                    outlineView.expandItem(nil, expandChildren: true)
                }
                ReusableFunc.updateBuiltInRecents(with: sender.stringValue, in: searchField)
            }
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: workItem!)
    }

    @IBAction func saveRTFToFile(_ sender: Any?) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.rtf]
        savePanel.nameFieldStringValue = "Exported_Annotations.rtf"

        savePanel.begin { [weak self] response in
            if let self, response == .OK, let url = savePanel.url {
                // Ambil data dari semua root nodes
                if let data = dataSource.exportToRTF() {
                    do {
                        try data.write(to: url)
                        #if DEBUG
                        print("Berhasil ekspor ke: \(url.path)")
                        #endif
                    } catch {
                        ReusableFunc.showAlert(title: "Error", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    @IBAction func floatPanel(_ sender: NSMenuItem) {
        let currentState = floatMenuItem.state
        floatMenuItem.state = currentState == .on ? .off : .on

        let on = floatMenuItem.state == .on ? true : false
        Self.panel?.isFloatingPanel = on
        UserDefaults.standard.annotationFloatWindow = on
    }

    @IBAction func hideOnPanel(_ sender: NSMenuItem) {
        let currentState = hideOnMenuItem.state
        hideOnMenuItem.state = currentState == .on ? .off : .on

        let on = sender.state == .on ? true : false
        Self.panel?.hidesOnDeactivate = on
        UserDefaults.standard.annotationHideWindow = on
    }

    @IBAction func revealInFinder(_ sender: Any?) {
        let fm = FileManager.default
        if let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                         in: .userDomainMask,
                                         appropriateFor: nil,
                                         create: false) {
            let appDir = appSupport.appendingPathComponent("Maktabah", isDirectory: true)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDir.path)
        }
    }

    @IBAction func openInNewWindow(_ sender: Any) {
        let panel = NSPanel()
        panel.styleMask.insert([.utilityWindow, .resizable, .closable])
        panel.title = "Annotations".localized
        panel.delegate = self
        shareBtn.isHidden = false
        windowBtn.isHidden = true
        setting.isHidden = false
        floatMenuItem.isHidden = false
        hideOnMenuItem.isHidden = false
        floatMenuItem.state = floatPanel ? .on : .off
        hideOnMenuItem.state = hideOnPanel ? .on : .off
        panel.contentViewController = self
        panel.isFloatingPanel = floatPanel
        panel.hidesOnDeactivate = hideOnPanel
        panel.makeKeyAndOrderFront(sender)
        panel.setFrameAutosaveName("AnnotationsPanel")
        Self.panel = panel
    }

    deinit {
        #if DEBUG
        print("annotationsVC deinit")
        #endif
    }
}

extension AnnotationsVC: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        SharedPopover.annotationsVC = nil
        Self.panel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        outlineView.deselectAll(nil)
    }
}
