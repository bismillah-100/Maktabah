//
//  ResultWriter.swift
//  maktab
//
//  Created by MacBook on 05/12/25.
//

import Cocoa
import SQLite

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
                button.borderShape = .circle
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
        let query = SearchSplitView.query
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

        // Kamus untuk mengelompokkan data. Kunci = (archive, bkId)
        var groupedResults: [String: GroupedResult] = [:]

        for item in results {
            let origTable = item.tableName.first == "b" ? String(item.tableName.dropFirst()) : item.tableName
            // 1. Validasi dan Konversi
            guard let arc = Int(item.archive),
                  let table = Int(origTable)
            else {
                #if DEBUG
                print("error converting table to Int:", item.tableName)
                #endif
                continue
            }

            let bookId = String(item.bookId)

            // 2. Buat Kunci Pengelompokan
            // Menggunakan string key untuk kemudahan karena tuple (arc, table) sulit dijadikan key dictionary
            let key = "\(arc)_\(table)"

            // 3. Kelompokkan bookId
            if var existingGroup = groupedResults[key] {
                // Jika grup sudah ada, tambahkan bookId ke array yang sudah ada
                if !existingGroup.contentIds.contains(bookId) {
                    existingGroup.contentIds.append(bookId)
                }
                groupedResults[key] = existingGroup
            } else {
                // Jika grup belum ada, buat grup baru
                var newGroup = GroupedResult(archive: arc, bkId: table)
                newGroup.contentIds.append(bookId)
                groupedResults[key] = newGroup
            }
        }

        var errorInsert: Bool = false
        // Iterasi hasil yang sudah dikelompokkan dan masukkan ke database
        for (_, group) in groupedResults {
            guard !errorInsert else { break }
            // Menggabungkan array contentIds menjadi string yang dipisahkan koma
            let commaSeparatedContentIds = group.contentIds.joined(separator: ",")

            // Memanggil fungsi insertResult yang dimodifikasi
            do {
                try db.insertResult(
                    group.archive,
                    bkId: group.bkId,
                    contentId: commaSeparatedContentIds, // contentId sekarang adalah string yang dipisahkan koma
                    folderId: folderId,
                    query: query,
                    name: name
                )
            } catch {
                errorInsert = true
                #if DEBUG
                print(error)
                #endif
            }
        }

        if errorInsert {
            ReusableFunc.showAlert(
                title: ResultsViewManager.saveResultErrorTitle,
                message: ResultsViewManager.saveResultErrorDesc,
                style: .critical
            )
            return
        }

        dismiss(nil)
    }

    override func dismiss(_ sender: Any?) {
        super.dismiss(sender)
        view.window?.close()
    }
}
