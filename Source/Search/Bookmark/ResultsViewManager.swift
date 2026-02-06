//
//  ResultsViewManager.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

import Cocoa

class ResultsViewManager: NSObject {
    weak var outlineView: NSOutlineView!

    let vm: ResultsViewModel = .shared

    private var searchWorkItem: DispatchWorkItem?

    var folderRoots: [FolderNode] {
        vm.folderRoots
    }

    private let folderCellIdentifier = NSUserInterfaceItemIdentifier(
        CellIViewIdentifier.bookmarkParent.rawValue
    )
    private let resultCellIdentifier = NSUserInterfaceItemIdentifier(
        CellIViewIdentifier.bookmarkChild.rawValue
    )

    var folderResults: [Int64?: [ResultNode]] {
        vm.folderResults
    }

    private var isSearching = false
    private var searchResultsByFolder: [Int64?: [ResultNode]] = [:]

    var writer: Bool = true

    weak var delegate: ResultsDelegate?

    static let folderCreateErrorTitle = NSLocalizedString("errorCreateFolderTitle", comment: "")
    static let folderCreateErrorDesc = NSLocalizedString("errorCreateFolderDesc", comment: "")
    static let inFolderCreateErrorDesc = NSLocalizedString("errorCreateInFolderDesc", comment: "")

    static let saveResultErrorTitle = NSLocalizedString("errorSaveResultTitle", comment: "")
    static let saveResultErrorDesc = NSLocalizedString("errorSaveResultDesc", comment: "")

    static let renameFolderErrorTitle = NSLocalizedString("errorUpdateFolderTitle", comment: "")
    static let renameResultErrorTitle = NSLocalizedString("errorUpdateResultTitle", comment: "")
    static let renameFolderOrResultErrorDesc = NSLocalizedString("errorUpdateFolderOrResultDesc", comment: "")

    static let errorMovingFolderTitle = NSLocalizedString("errorMovingFolderTitle", comment: "")
    static let errorMovingFolderDesc = NSLocalizedString("errorMovingFolderDesc", comment: "")
    static let errorMovingResultTitle = NSLocalizedString("errorMovingResultTitle", comment: "")
    static let errorMovingResultDesc = NSLocalizedString("errorMovingResultDesc", comment: "")

    init(outlineView: NSOutlineView!,
         delegate: ResultsDelegate? = nil,
         writer: Bool = true
    ) {

        self.writer = writer

        ReusableFunc.registerNib(
            tableView: outlineView,
            nibName: .bookmarkChildNib,
            cellIdentifier: .bookmarkChild
        )

        ReusableFunc.registerNib(
            tableView: outlineView, 
            nibName: .bookmarkParentNib,
            cellIdentifier: .bookmarkParent
        )

        outlineView.registerForDraggedTypes([
            .folderNode,
            .resultNode
        ])

        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        
        self.outlineView = outlineView
        self.delegate = delegate
    }

    func findNode(by id: Int64, in roots: [FolderNode]) -> FolderNode? {
        for r in roots {
            if r.id == id { return r }
            if let found = findNode(by: id, in: r.children) { return found }
        }
        return nil
    }

    private func results(for folderId: Int64?) -> [ResultNode] {
        return isSearching ? (searchResultsByFolder[folderId] ?? []) : (folderResults[folderId] ?? [])
    }

    func searchResults(for text: String) {
        if text.isEmpty {
            // kosong -> keluar dari mode search
            isSearching = false
            searchResultsByFolder.removeAll()
            outlineView.reloadData()
            return
        }

        searchWorkItem?.cancel()

        searchWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // ambil hasil dari view model (asumsi return [(result, folderId, folderPath)])
            let items = vm.searchResultsWithFolderPath(text)

            // group per folderId
            searchResultsByFolder.removeAll()
            for entry in items {
                searchResultsByFolder[entry.folderId, default: []].append(entry.result)
            }
            // optional: sort tiap grup
            for key in searchResultsByFolder.keys {
                searchResultsByFolder[key]?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }

            isSearching = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                outlineView.reloadData()

                // expand semua folder yang berisi hasil
                for (folderId, _) in searchResultsByFolder {
                    if let id = folderId, let node = vm.findFolder(id) {
                        outlineView.expandItem(node)
                    } else {
                        // folderId == nil -> hasil di root, tidak perlu expand
                    }
                }

                // pilih hasil pertama (jika ada)
                if let first = items.first {
                    let row = outlineView.row(forItem: first.result)
                    if row >= 0 {
                        outlineView.scrollRowToVisible(row)
                    }
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: searchWorkItem!)
    }


    static func showAlertCreateFolderError(subFolder: Bool = false) {
        let message = subFolder ? Self.inFolderCreateErrorDesc : Self.folderCreateErrorDesc
        ReusableFunc.showAlert(title: Self.folderCreateErrorTitle, message: message, style: .critical)
    }
}

extension ResultsViewManager: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let folder = item as? FolderNode {
            let childFolders = folder.children.count
            let resultsCount = writer ? 0 : results(for: folder.id).count
            return childFolders + resultsCount
        }

        let rootFoldersCount = folderRoots.count
        let rootResultsCount = writer ? 0 : results(for: nil).count
        return rootFoldersCount + rootResultsCount
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if item is ResultNode { return false }
        if let folder = item as? FolderNode {
            let hasChildren = !folder.children.isEmpty
            let hasResults = !writer && !results(for: folder.id).isEmpty
            return hasChildren || hasResults
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let folder = item as? FolderNode {
            let childFolders = folder.children
            if index < childFolders.count { return childFolders[index] }
            if !writer {
                let list = results(for: folder.id)
                return list[index - childFolders.count]
            }
        } else {
            if index < folderRoots.count { return folderRoots[index] }
            if !writer {
                let rootList = results(for: nil)
                let resultIndex = index - folderRoots.count
                if resultIndex < rootList.count { return rootList[resultIndex] }
            }
        }
        return folderRoots[index] // fallback
    }
}

extension ResultsViewManager: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {

        if let result = item as? ResultNode,
           let cell = outlineView.makeView(withIdentifier: resultCellIdentifier, owner: self) as? NSTableCellView,
           let textField = cell.textField
        {
            textField.stringValue = "\(result.name)"
            textField.delegate = self
            textField.isEditable = true
            return cell
        }

        if let folder = item as? FolderNode,
           let cell = outlineView.makeView(withIdentifier: folderCellIdentifier, owner: self) as? NSTableCellView,
           let textField = cell.textField
        {
            textField.stringValue = "\(folder.name)"
            textField.delegate = self
            textField.isEditable = true
            return cell
        }
        return nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0,
              let result = outlineView.item(atRow: row) as? ResultNode
        else { return }

        // Tampilkan hasil pencarian
        delegate?.didSelect(savedResults: result.items)
    }
}

extension ResultsViewManager {
    func outlineView(_ outlineView: NSOutlineView,
                     pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {

        let pbItem = NSPasteboardItem()

        if let folder = item as? FolderNode {
            pbItem.setString(String(folder.id), forType: .folderNode)
            return pbItem
        }

        if let result = item as? ResultNode {
            pbItem.setString(String(result.id), forType: .resultNode)
            return pbItem
        }

        return nil
    }
}

extension ResultsViewManager {
    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {

        // Hanya izinkan drop ON item
        guard index == NSOutlineViewDropOnItemIndex else {
            return []
        }

        return .move
    }
}

extension ResultsViewManager {
    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {

        guard let pbItem = info.draggingPasteboard.pasteboardItems?.first else {
            return false
        }

        let newParent = item as? FolderNode

        // --- FOLDER NODE -----------------------------------------------------
        if let idStr = pbItem.string(forType: .folderNode),
           let draggedId = Int64(idStr),
           let draggedNode = findNode(by: draggedId, in: vm.folderRoots) {

            let oldParent = findParent(of: draggedNode, in: vm.folderRoots)

            do {
                try vm.moveNode(draggedNode: draggedNode, newParent: newParent)
                
                // reload UI
                outlineView.reloadItem(newParent, reloadChildren: true)
                if let oldParent {
                    outlineView.reloadItem(oldParent, reloadChildren: true)
                } else {
                    outlineView.reloadItem(nil, reloadChildren: true) // penting: refresh root results
                }
                return true
            } catch {
                ReusableFunc.showAlert(
                    title: Self.errorMovingFolderTitle,
                    message: Self.errorMovingFolderDesc,
                    style: .critical
                )
            }

            return false
        }

        // --- RESULT NODE -----------------------------------------------------
        if let idStr = pbItem.string(forType: .resultNode),
           let resultId = Int64(idStr) {

            // Pindahkan di memory
            do {
                try vm.moveResult(resultId, to: newParent?.id)
                // Reload UI: jika ada old folder reload itu, kalau tidak reload root
                if let oldParentId = Int64(idStr), let oldFolder = vm.findFolder(oldParentId) {
                    outlineView.reloadItem(oldFolder, reloadChildren: true)
                } else {
                    outlineView.reloadItem(nil, reloadChildren: true) // penting: refresh root results
                }

                outlineView.reloadItem(newParent, reloadChildren: true)
                return true
            } catch {
                ReusableFunc.showAlert(title: Self.errorMovingResultTitle, message: Self.errorMovingResultDesc, style: .critical)
            }

            return false
        }

        return false
    }


    private func findParent(of node: FolderNode, in roots: [FolderNode]) -> FolderNode? {
        for root in roots {
            if root.children.contains(where: { $0.id == node.id }) {
                return root
            }
            if let parent = findParent(of: node, in: root.children) {
                return parent
            }
        }
        return nil
    }
}

extension ResultsViewManager: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField,
              let cell = textField.superview as? NSTableCellView
        else {
            return
        }

        let row = outlineView.row(for: cell)
        let item = outlineView.item(atRow: row)

        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            outlineView.reloadItem(item)
            return
        }

        var errorTitle: String = "Error unhandled."

        do {
            if let folderNode = item as? FolderNode {
                guard folderNode.name != newName else { return }
                // Perbarui model data di ViewModel dan Database
                errorTitle = Self.renameFolderErrorTitle
                try vm.updateFolderName(id: folderNode.id, newName: newName)
            } else if let resultNode = item as? ResultNode {
                guard resultNode.name != newName else { return }
                let parent = outlineView.parent(forItem: item) as? FolderNode
                // Kasus 2: Mengubah nama Result (Query)
                // Panggil fungsi database untuk memperbarui nama query/result
                // Dapatkan nilai lama sebelum perubahan
                let folderId = parent?.id

                // Perbarui model data di ViewModel (penting untuk OutlineView)
                errorTitle = Self.renameResultErrorTitle
                try vm.updateResultQueryName(id: resultNode.id, newName: newName, folderId: folderId)
            }
        } catch {
            ReusableFunc.showAlert(title: errorTitle, message: Self.renameFolderOrResultErrorDesc, style: .critical)
            outlineView.reloadItem(item)
            #if DEBUG
            print(error)
            #endif
        }
    }
}

extension NSPasteboard.PasteboardType {
    static let folderNode = NSPasteboard.PasteboardType("com.maktab.folderNode")
    static let resultNode = NSPasteboard.PasteboardType("com.maktab.resultNode")
}
