//
//  SavedResults.swift
//  maktab
//
//  Created by MacBook on 05/12/25.
//

import Cocoa

class SavedResults: NSViewController {
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var searchField: NSSearchField!
    @IBOutlet weak var xButton: NSButton!

    var resultsVM: ResultsViewManager!

    weak var delegate: ResultsDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        resultsVM = ResultsViewManager(
            outlineView: outlineView,
            delegate: delegate,
            writer: false
        )

        if #available(macOS 26.0, *) {
            xButton.borderShape = .capsule
        }

        setupOutlineView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        ReusableFunc.showProgressWindow(view)
        Task.detached { [weak self] in
            await self?.resultsVM.vm.getFolders()
            await self?.dbLoadResults()
            await MainActor.run { [weak self] in
                guard let self else { return }
                ReusableFunc.closeProgressWindow(self.view)
            }
        }
    }

    func setupOutlineView() {
        outlineView.delegate = resultsVM
        outlineView.dataSource = resultsVM

        if let titleCol = outlineView.tableColumn(
            withIdentifier: NSUserInterfaceItemIdentifier(
                rawValue: "AutomaticTableColumnIdentifier.0"
            )
        ) {
            titleCol.title = "Title".localized
        }

        let queryCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("query"))
        queryCol.title = "Query".localized
        outlineView.addTableColumn(queryCol)

        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modifiedDate"))
        dateCol.title = "Date Modified".localized
        outlineView.addTableColumn(dateCol)

        outlineView.autosaveTableColumns = true
        outlineView.autosaveExpandedItems = true
        outlineView.autosaveName = "searchResultsOutlineView"

        let headerMenu = NSMenu()
        headerMenu.delegate = resultsVM
        outlineView.headerView?.menu = headerMenu
    }

    @IBAction func search(_ sender: NSSearchField) {
        resultsVM.searchResults(for: sender.stringValue)
    }

    @IBAction func addFolder(_ sender: Any) {
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let alert = NSAlert()
        alert.messageText = "Create New Folder".localized
        alert.addButton(withTitle: "Save".localized)
        alert.addButton(withTitle: "Cancel".localized)
        alert.accessoryView = textField

        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else { return }

        let name = textField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !name.isEmpty else { return }

        let row = outlineView.selectedRow

        do {
            if row >= 0,
               let item = outlineView.item(atRow: row) as? FolderNode {
                try resultsVM.vm.addSubFolder(parentNode: item, name: name)
            } else {
                try resultsVM.vm.addRootFolder(name: name)
            }
        } catch {
            ResultsViewManager.showAlertCreateFolderError(subFolder: row >= 0)
        }
    }

    @IBAction func deleteFolder(_ sender: Any) {
        let row = outlineView.selectedRow
        if let item = outlineView.item(atRow: row) as? FolderNode {
            resultsVM.vm.deleteFolder(node: item)
            return
        }

        if let item = outlineView.item(atRow: row) as? ResultNode {
            let parent = outlineView.parent(forItem: item) as? FolderNode
            resultsVM.vm.deleteResult(parent?.id, name: item.name)
        }
    }
    
    override func dismiss(_ sender: Any?) {
        if let window = view.window {
            window.contentViewController = nil
            window.close()
        }
        super.dismiss(sender)
    }

    deinit {
        #if DEBUG
        print("deinit savedResults")
        #endif
        delegate = nil
        resultsVM = nil
    }
}

extension SavedResults {
    func dbLoadResults() async {
        await resultsVM.vm.dbLoadAllResults()
        // UI reload ditangani oleh onDataChanged callback di ResultsViewManager
    }
}
