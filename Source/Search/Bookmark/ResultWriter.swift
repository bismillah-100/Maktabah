//
//  ResultWriter.swift
//  maktab
//
//  Created by MacBook on 05/12/25.
//

import Cocoa

class ResultWriter: NSViewController {
    @IBOutlet weak var textField: NSTextField!
    @IBOutlet weak var okButton: NSButton!
    @IBOutlet weak var xButton: NSButton!
    @IBOutlet weak var outlineView: NSOutlineView!

    let db: ResultsHandler = .shared
    let viewModel: ResultsViewModel = .shared

    var results: [SearchResultItem] = []
    var resultsVM: ResultsViewManager!
    var query: String = ""
    
    var nsBtns: [NSButton] {
        [xButton, okButton]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        textField.focusRingType = .none
        resultsVM = ResultsViewManager(
            outlineView: outlineView
        )
        outlineView.dataSource = resultsVM
        outlineView.delegate = resultsVM
        if #available(macOS 26, *) {
            nsBtns.forEach { button in
                button.borderShape = .capsule
            }
        }
        // Do view setup here.
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        ReusableFunc.showProgressWindow(view)
        textField.stringValue = query
        Task.detached() { [weak self] in
            await self?.viewModel.getFolders()
            await MainActor.run { [weak self] in
                guard let self else { return }
                outlineView.reloadData()
                ReusableFunc.closeProgressWindow(view)
            }
        }
        okButton.action = #selector(saveClicked(_:))
    }

    @IBAction func createFolder(_ sender: Any) {
        let textField = NSTextField(frame: NSRect(x: 0, y: 50, width: 240, height: 22))
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Create New Folder", comment: "")

        alert.addButton(withTitle: NSLocalizedString("Save", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.accessoryView = textField

        let response = alert.runModal()
        textField.becomeFirstResponder()

        let row = outlineView.selectedRow
        if response == .alertFirstButtonReturn {
            let name = textField.stringValue

            guard !name.isEmpty else { return }

            if row >= 0,
               let item = outlineView.item(atRow: row) as? FolderNode {
                addSubFolder(parentNode: item, name: name)
                return
            }
            addRootFolder(name: name)
        } else {
            alert.window.close()
        }
    }

    func addRootFolder(name: String) {
        do {
            try viewModel.addRootFolder(name: name)
            outlineView.reloadData()
        } catch {
            ResultsViewManager.showAlertCreateFolderError()
            print("Add folder error:", error)
        }
    }

    func addSubFolder(parentNode: FolderNode, name: String) {
        do {
            try viewModel.addSubFolder(parentNode: parentNode, name: name)
            outlineView.reloadItem(parentNode, reloadChildren: true)
        } catch {
            ResultsViewManager.showAlertCreateFolderError(subFolder: true)
            print("Add subfolder error:", error)
        }
    }

    @IBAction func saveClicked(_ sender: Any) {
        let query = OptionSearchVC.query
        if query.isEmpty { return }

        let folderId: Int64?

        let row = outlineView.selectedRow
        if let item = outlineView.item(atRow: row) as? FolderNode {
            folderId = item.id
        } else {
            folderId = nil
        }

        let name = textField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !name.isEmpty else {
            print("Nama result kosong")
            return
        }

        do {
            try viewModel.saveSearchResults(
                results: results,
                query: query,
                folderId: folderId,
                name: name
            )
            dismiss(nil)
        } catch {
            ReusableFunc.showAlert(
                title: ResultsViewManager.saveResultErrorTitle,
                message: ResultsViewManager.saveResultErrorDesc,
                style: .critical
            )
            #if DEBUG
            print(error)
            #endif
        }
    }

    override func dismiss(_ sender: Any?) {
        super.dismiss(sender)
        view.window?.close()
    }
}
