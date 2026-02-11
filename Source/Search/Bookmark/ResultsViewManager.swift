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
    private var searchText: String = ""
    private var matchingFolderIds: Set<Int64> = []

    var writer: Bool = true

    weak var delegate: ResultsDelegate?

    static let folderCreateErrorTitle = NSLocalizedString(
        "errorCreateFolderTitle",
        comment: ""
    )
    static let folderCreateErrorDesc = NSLocalizedString(
        "errorCreateFolderDesc",
        comment: ""
    )
    static let inFolderCreateErrorDesc = NSLocalizedString(
        "errorCreateInFolderDesc",
        comment: ""
    )

    static let saveResultErrorTitle = NSLocalizedString(
        "errorSaveResultTitle",
        comment: ""
    )
    static let saveResultErrorDesc = NSLocalizedString(
        "errorSaveResultDesc",
        comment: ""
    )

    static let renameFolderErrorTitle = NSLocalizedString(
        "errorUpdateFolderTitle",
        comment: ""
    )
    static let renameResultErrorTitle = NSLocalizedString(
        "errorUpdateResultTitle",
        comment: ""
    )
    static let renameFolderOrResultErrorDesc = NSLocalizedString(
        "errorUpdateFolderOrResultDesc",
        comment: ""
    )

    static let errorMovingFolderTitle = NSLocalizedString(
        "errorMovingFolderTitle",
        comment: ""
    )
    static let errorMovingFolderDesc = NSLocalizedString(
        "errorMovingFolderDesc",
        comment: ""
    )
    static let errorMovingResultTitle = NSLocalizedString(
        "errorMovingResultTitle",
        comment: ""
    )
    static let errorMovingResultDesc = NSLocalizedString(
        "errorMovingResultDesc",
        comment: ""
    )

    init(
        outlineView: NSOutlineView!,
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
            .resultNode,
        ])

        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        self.outlineView = outlineView
        self.delegate = delegate
    }

    func searchResults(for text: String) {
        if text.isEmpty {
            isSearching = false
            searchResultsByFolder.removeAll()
            searchText = ""
            matchingFolderIds.removeAll()
            outlineView.reloadData()
            return
        }

        searchWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            let query = text.lowercased()
            searchText = query

            // 1. Folder match (pakai cache)
            let matchedFolders = vm.searchFoldersInMemory(query)
            matchingFolderIds = Set(matchedFolders.map(\.id))

            // 2. Result match (pakai cache)
            let resultsWithPath = vm.searchResultsWithFolderPath(query)

            // group per folderId
            searchResultsByFolder = Dictionary(
                grouping: resultsWithPath.map(\.result),
                by: { $0.parentId }
            )

            // sort tiap folder
            for key in searchResultsByFolder.keys {
                searchResultsByFolder[key]?.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name)
                        == .orderedAscending
                }
            }

            isSearching = true

            DispatchQueue.main.async {
                self.applySearchUI(resultsWithPath: resultsWithPath)
            }
        }

        searchWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated)
            .asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func applySearchUI(
        resultsWithPath: [(
            result: ResultNode, folderId: Int64?, folderPath: String
        )]
    ) {
        outlineView.reloadData()

        // expand semua folder relevan
        let foldersToExpand =
            Set(searchResultsByFolder.keys.compactMap { $0 })
            .union(matchingFolderIds)

        for folderId in foldersToExpand {
            expandFolderChain(folderId)
        }

        // scroll ke item pertama
        if let first = resultsWithPath.first {
            let row = outlineView.row(forItem: first.result)
            outlineView.scrollRowToVisible(row)
        } else if let folderId = matchingFolderIds.first,
            let folder = vm.findFolder(folderId)
        {
            let row = outlineView.row(forItem: folder)
            outlineView.scrollRowToVisible(row)
        }
    }

    private func expandFolderChain(_ folderId: Int64) {
        var currentId: Int64? = folderId

        while let id = currentId, let node = vm.findFolder(id) {
            outlineView.expandItem(node)
            currentId = vm.parentById[id] ?? nil
        }
    }

    private func shouldShowFolder(_ folder: FolderNode) -> Bool {
        guard isSearching else { return true }

        if matchingFolderIds.contains(folder.id) {
            return true
        }

        if let results = searchResultsByFolder[folder.id], !results.isEmpty {
            return true
        }

        return folder.children.contains { shouldShowFolder($0) }
    }

    static func showAlertCreateFolderError(subFolder: Bool = false) {
        let message =
            subFolder
            ? Self.inFolderCreateErrorDesc : Self.folderCreateErrorDesc
        ReusableFunc.showAlert(
            title: Self.folderCreateErrorTitle,
            message: message,
            style: .critical
        )
    }

    func visibleFolders(in folder: FolderNode) -> [FolderNode] {
        guard isSearching else { return folder.children }

        if matchingFolderIds.contains(folder.id) {
            return folder.children
        }

        return folder.children.filter { shouldShowFolder($0) }
    }

    func visibleItems(in folderId: Int64?) -> [ResultNode] {
        guard isSearching else {
            return folderResults[folderId] ?? []
        }

        if folderId == nil {
            return searchResultsByFolder[nil] ?? []
        }

        if matchingFolderIds.contains(folderId!) {
            return folderResults[folderId!] ?? []
        }

        return searchResultsByFolder[folderId!] ?? []
    }

}

extension ResultsViewManager: NSOutlineViewDataSource {
    func outlineView(
        _ outlineView: NSOutlineView,
        numberOfChildrenOfItem item: Any?
    ) -> Int {
        if let folder = item as? FolderNode {
            let foldersToShow = visibleFolders(in: folder)
            let itemsToShow = writer ? 0 : visibleItems(in: folder.id).count
            return foldersToShow.count + itemsToShow
        }

        let rootFolders: [FolderNode] =
            isSearching
            ? folderRoots.filter { shouldShowFolder($0) }
            : folderRoots

        let rootItems = writer ? [] : visibleItems(in: nil)

        return rootFolders.count + rootItems.count
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any)
        -> Bool
    {
        if item is ResultNode { return false }
        if let folder = item as? FolderNode {
            // Gunakan helper visible agar konsisten
            let folders = visibleFolders(in: folder)
            let items = visibleItems(in: folder.id)
            return !folders.isEmpty || (!writer && !items.isEmpty)
        }
        return false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        child index: Int,
        ofItem item: Any?
    ) -> Any {
        if let folder = item as? FolderNode {
            let foldersToShow = visibleFolders(in: folder)
            let itemsToShow = visibleItems(in: folder.id)

            // Urutan: Tampilkan Folder dulu, baru Item
            if index < foldersToShow.count {
                return foldersToShow[index]
            } else {
                return itemsToShow[index - foldersToShow.count]
            }
        } else {
            let rootFolders: [FolderNode] =
                isSearching
                ? folderRoots.filter { shouldShowFolder($0) }
                : folderRoots

            let rootItems = writer ? [] : visibleItems(in: nil)

            if index < rootFolders.count {
                return rootFolders[index]
            } else {
                return rootItems[index - rootFolders.count]
            }
        }
    }
}

extension ResultsViewManager: NSOutlineViewDelegate {
    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {

        if let result = item as? ResultNode,
            let cell = outlineView.makeView(
                withIdentifier: resultCellIdentifier,
                owner: self
            ) as? NSTableCellView,
            let textField = cell.textField
        {
            textField.stringValue = "\(result.name)"
            textField.delegate = self
            textField.isEditable = true
            return cell
        }

        if let folder = item as? FolderNode,
            let cell = outlineView.makeView(
                withIdentifier: folderCellIdentifier,
                owner: self
            ) as? NSTableCellView,
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
    func outlineView(
        _ outlineView: NSOutlineView,
        pasteboardWriterForItem item: Any
    ) -> NSPasteboardWriting? {

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
    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {

        // Hanya izinkan drop ON item
        guard index == NSOutlineViewDropOnItemIndex else {
            return []
        }

        if item is ResultNode {
            return []
        }

        return .move
    }
}

extension ResultsViewManager {
    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {

        guard let pbItem = info.draggingPasteboard.pasteboardItems?.first else {
            return false
        }

        let newParent = item as? FolderNode

        // --- FOLDER NODE -----------------------------------------------------
        if let idStr = pbItem.string(forType: .folderNode),
            let draggedId = Int64(idStr),
            let draggedNode = vm.findFolder(draggedId)
        {

            let oldParent = vm.findParent(of: draggedNode, in: vm.folderRoots)

            do {
                try vm.moveNode(draggedNode: draggedNode, newParent: newParent)

                // reload UI
                outlineView.reloadItem(newParent, reloadChildren: true)
                if let oldParent {
                    outlineView.reloadItem(oldParent, reloadChildren: true)
                } else {
                    outlineView.reloadItem(nil, reloadChildren: true)  // penting: refresh root results
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
            let resultId = Int64(idStr)
        {

            // Pindahkan di memory
            do {
                try vm.moveResult(resultId, to: newParent?.id)
                // Reload UI: jika ada old folder reload itu, kalau tidak reload root
                if let oldParentId = Int64(idStr),
                    let oldFolder = vm.findFolder(oldParentId)
                {
                    outlineView.reloadItem(oldFolder, reloadChildren: true)
                } else {
                    outlineView.reloadItem(nil, reloadChildren: true)  // penting: refresh root results
                }

                outlineView.reloadItem(newParent, reloadChildren: true)
                return true
            } catch {
                ReusableFunc.showAlert(
                    title: Self.errorMovingResultTitle,
                    message: Self.errorMovingResultDesc,
                    style: .critical
                )
            }

            return false
        }

        return false
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

        let newName = textField.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
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
                // Kasus 2: Mengubah nama Result (Query)
                // Panggil fungsi database untuk memperbarui nama query/result
                // Perbarui model data di ViewModel (penting untuk OutlineView)
                errorTitle = Self.renameResultErrorTitle
                try vm.updateResultQueryName(
                    id: resultNode.id,
                    newName: newName
                )
            }
        } catch {
            ReusableFunc.showAlert(
                title: errorTitle,
                message: Self.renameFolderOrResultErrorDesc,
                style: .critical
            )
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
