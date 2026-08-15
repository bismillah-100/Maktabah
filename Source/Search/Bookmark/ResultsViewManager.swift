//
//  ResultsViewManager.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

import Cocoa

@MainActor
class ResultsViewManager: NSObject {
    weak var outlineView: NSOutlineView!

    let vm: ResultsViewModel = .shared

    private var searchTask: Task<Void, Never>?

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

        // Subscribe ke onTreeChange agar NSOutlineView bisa update inkremental
        super.init()

        setupOutlineView()

        vm.onTreeChange = { [weak self] change in
            self?.applyTreeChange(change)
        }
    }

    private func setupOutlineView() {
        guard let outlineView = outlineView else { return }
        outlineView.target = self
        outlineView.doubleAction = #selector(onDoubleClick(_:))

        let itemMenu = NSMenu()
        itemMenu.delegate = self
        outlineView.menu = itemMenu
    }

    func applyTreeChange(_ change: BookmarkTreeChange) {
        guard !isSearching else {
            // Jika sedang searching, mapping index terlalu rumit, kita pakai reloadData
            outlineView.reloadData()
            return
        }

        if case .fullReload = change {
            outlineView.reloadData()
            return
        }

        switch change {
        case .insertFolder(_, let parent, let index):
            outlineView.insertItems(at: IndexSet(integer: index), inParent: parent, withAnimation: .effectGap)

        case .removeFolder(_, let parent, let index):
            outlineView.removeItems(at: IndexSet(integer: index), inParent: parent, withAnimation: .effectFade)

        case .updateFolder(let folder):
            outlineView.reloadItem(folder)

        case .moveFolder(_, let oldParent, let oldIndex, let newParent, let newIndex):
            outlineView.moveItem(at: oldIndex, inParent: oldParent, to: newIndex, inParent: newParent)
            outlineView.reloadItem(newParent)
            outlineView.reloadItem(oldParent)

        case .insertResult(_, let parentId, let index):
            if writer { return }
            let parentFolder = parentId.flatMap { vm.findFolder($0) }
            let folderCount = parentFolder?.children.count ?? vm.folderRoots.count
            let outlineIndex = folderCount + index
            outlineView.insertItems(at: IndexSet(integer: outlineIndex), inParent: parentFolder, withAnimation: .effectGap)
            outlineView.reloadItem(parentFolder)

        case .removeResult(_, let parentId, let index):
            if writer { return }
            let parentFolder = parentId.flatMap { vm.findFolder($0) }
            let folderCount = parentFolder?.children.count ?? vm.folderRoots.count
            let outlineIndex = folderCount + index
            outlineView.removeItems(at: IndexSet(integer: outlineIndex), inParent: parentFolder, withAnimation: .effectFade)
            outlineView.reloadItem(parentFolder)

        case .updateResult(let result):
            if writer { return }
            outlineView.reloadItem(result)

        case .moveResult(_, let oldParentId, let oldIndex, let newParentId, let newIndex):
            if writer { return }
            let oldParent = oldParentId.flatMap { vm.findFolder($0) }
            let newParent = newParentId.flatMap { vm.findFolder($0) }

            let oldFolderCount = oldParent?.children.count ?? vm.folderRoots.count
            let newFolderCount = newParent?.children.count ?? vm.folderRoots.count

            outlineView.moveItem(at: oldFolderCount + oldIndex, inParent: oldParent, to: newFolderCount + newIndex, inParent: newParent)
            if let newParent { outlineView.reloadItem(newParent) }
            outlineView.reloadItem(oldParent)

        default: break
        }
    }

    func searchResults(for text: String) {
        searchTask?.cancel()

        if text.isEmpty {
            isSearching = false
            searchResultsByFolder.removeAll()
            matchingFolderIds.removeAll()
            outlineView.reloadData()
            return
        }

        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return // Task cancelled
            }

            let query = text.lowercased()

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

            self.applySearchUI(resultsWithPath: resultsWithPath)
        }
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

    /// Simpan ID unik item
    func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
        if let folder = item as? FolderNode {
            return folder.id
        }
        return nil
    }

    /// Restore item dari ID unik saat data di-load
    func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? {
        if let id = object as? Int64 {
            return vm.findFolder(id)
        }
        return nil
    }
}

extension ResultsViewManager: NSOutlineViewDelegate {
        func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {

        if tableColumn?.identifier.rawValue == "query", let result = item as? ResultNode {
            let cellIdentifier = NSUserInterfaceItemIdentifier("queryCell")
            var cell = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = cellIdentifier
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingTail
                cell?.addSubview(textField)
                cell?.textField = textField
                if let cell = cell {
                    NSLayoutConstraint.activate([
                        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                    ])
                }
            }
            if let query = result.items.first?.query, !query.isEmpty {
                cell?.textField?.stringValue = query
            } else {
                cell?.textField?.stringValue = ""
            }
            return cell
        }

        if tableColumn?.identifier.rawValue == "modifiedDate", let result = item as? ResultNode {
            let cellIdentifier = NSUserInterfaceItemIdentifier("dateCell")
            var cell = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = cellIdentifier
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.textColor = .secondaryLabelColor
                textField.lineBreakMode = .byTruncatingTail
                cell?.addSubview(textField)
                cell?.textField = textField
                if let cell = cell {
                    NSLayoutConstraint.activate([
                        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                    ])
                }
            }
            if let timestamp = result.lastModified {
                let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                let formattedString: String = if Calendar.current.isDateInToday(date) {
                    RelativeDateTimeFormatter.shared.localizedString(for: date, relativeTo: Date())
                } else {
                    DateFormatter.mediumDate.string(from: date)
                }
                cell?.textField?.stringValue = formattedString
            } else {
                cell?.textField?.stringValue = "-"
            }
            return cell
        }

        if let result = item as? ResultNode,
           tableColumn?.identifier.rawValue == "AutomaticTableColumnIdentifier.0" {
            if let cell = outlineView.makeView(
                withIdentifier: resultCellIdentifier,
                owner: self
            ) as? NSTableCellView,
            let textField = cell.textField
            {
                let mode = SearchMode(rawValue: result.searchMode) ?? .phrase
                let imageName = SearchMode.imageNameForMode(mode)
                cell.imageView?.image = NSImage(
                    systemSymbolName: imageName, accessibilityDescription: nil
                )
                textField.stringValue = "\(result.name)"
                textField.delegate = self
                textField.isEditable = true
                return cell
            }
        }

        if let folder = item as? FolderNode,
            tableColumn?.identifier.rawValue == "AutomaticTableColumnIdentifier.0" {
            if let cell = outlineView.makeView(
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
        }
        return nil
    }

    @objc private func onDoubleClick(_ sender: AnyObject) {
        guard let outlineView = outlineView else { return }
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0, let item = outlineView.item(atRow: clickedRow) else { return }

        if let folder = item as? FolderNode {
            if outlineView.isItemExpanded(folder) {
                outlineView.collapseItem(folder)
            } else {
                outlineView.expandItem(folder)
            }
        } else if let result = item as? ResultNode {
            delegate?.didSelect(savedResults: result.items)
        }
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

        // Jika yang di-drag adalah folder, jangan izinkan drop
        // jika folder tujuan merupakan child (atau sama) dari folder yang di-drag.
        if let pbItems = info.draggingPasteboard.pasteboardItems {
            for pb in pbItems {
                // 1. Ambil data dasar dan pastikan target adalah FolderNode
                guard let idStr = pb.string(forType: .folderNode),
                      let draggedId = Int64(idStr),
                      let draggedNode = vm.findFolder(draggedId),
                      let targetFolder = item as? FolderNode else {
                    continue // Lanjut ke item pasteboard berikutnya jika data tidak cocok
                }

                // 2. Cek hubungan silsilah (Ancestry Check)
                var current: FolderNode? = targetFolder

                while let cur = current {
                    // Jika target adalah dirinya sendiri atau anak dari dirinya sendiri
                    if cur.id == draggedNode.id {
                        return [] 
                    }

                    // 3. Naik ke parent berikutnya menggunakan guard
                    // Jika parentId nil atau folder tidak ditemukan, break (sudah sampai root)
                    guard let parentId = vm.parentById[cur.id] ?? nil,
                          let nextParent = vm.findFolder(parentId) else {
                        break
                    }
                    current = nextParent
                }
            }
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

            do {
                try vm.moveNode(draggedNode: draggedNode, newParent: newParent)
                // UI update ditangani oleh onTreeChange secara inkremental
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
                // UI update ditangani oleh onTreeChange secara inkremental
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

extension ResultsViewManager: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let outlineView = outlineView else { return }

        if menu == outlineView.headerView?.menu {
            updateHeaderMenu(menu, outlineView: outlineView)
        } else if menu == outlineView.menu {
            updateItemContextMenu(menu, outlineView: outlineView)
        }
    }

    private func updateHeaderMenu(_ menu: NSMenu, outlineView: NSOutlineView) {
        for column in outlineView.tableColumns {
            let title: String
            if column.identifier.rawValue == "AutomaticTableColumnIdentifier.0" {
                title = "Title".localized
            } else if column.identifier.rawValue == "query" {
                title = "Query".localized
            } else if column.identifier.rawValue == "modifiedDate" {
                title = "Date Modified".localized
            } else if !column.title.isEmpty {
                title = column.title
            } else {
                title = column.identifier.rawValue
            }

            let menuItem = NSMenuItem(
                title: title,
                action: #selector(toggleColumnVisibility(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = column
            menuItem.state = column.isHidden ? .off : .on

            if column.identifier.rawValue == "AutomaticTableColumnIdentifier.0" || column == outlineView.outlineTableColumn {
                menuItem.isEnabled = false
            } else {
                menuItem.isEnabled = true
            }

            menu.addItem(menuItem)
        }
    }

    private func updateItemContextMenu(_ menu: NSMenu, outlineView: NSOutlineView) {
        let rows = outlineView.effectiveRows()
        guard !rows.isEmpty else { return }

        let items = rows.compactMap { outlineView.item(atRow: $0) }
        guard !items.isEmpty else { return }

        if items.count == 1 {
            let renameItem = NSMenuItem(
                title: "Rename".localized,
                action: #selector(renameSelectedItem(_:)),
                keyEquivalent: ""
            )
            renameItem.target = self
            renameItem.image = NSImage(
                systemSymbolName: "pencil",
                accessibilityDescription: ""
            )
            menu.addItem(renameItem)
        }

        let deleteItem = NSMenuItem(
            title: "Delete".localized,
            action: #selector(deleteSelectedItems(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: ""
        )
        menu.addItem(deleteItem)

        if items.count == 1 {
            if let result = items.first as? ResultNode {
                menu.addItem(.separator())
                let startSearchItem = NSMenuItem(
                    title: "Start Search".localized,
                    action: #selector(startSearchSelectedItem(_:)),
                    keyEquivalent: ""
                )
                startSearchItem.target = self
                startSearchItem.representedObject = result
                startSearchItem.image = .init(
                    systemSymbolName: "play.fill",
                    accessibilityDescription: ""
                )
                menu.addItem(startSearchItem)
            }
        }
    }

    @objc private func startSearchSelectedItem(_ sender: NSMenuItem) {
        if let result = sender.representedObject as? ResultNode {
            delegate?.didSelect(savedResults: result.items)
            return
        }
        guard let outlineView = outlineView else { return }
        let rows = outlineView.effectiveRows()
        guard let firstRow = rows.first,
              let result = outlineView.item(atRow: firstRow) as? ResultNode
        else { return }
        delegate?.didSelect(savedResults: result.items)
    }

    @objc private func toggleColumnVisibility(_ sender: NSMenuItem) {
        guard let column = sender.representedObject as? NSTableColumn else { return }
        column.isHidden = !column.isHidden
    }

    @objc private func renameSelectedItem(_ sender: NSMenuItem) {
        guard let outlineView = outlineView else { return }
        let rows = outlineView.effectiveRows()
        guard let firstRow = rows.first, firstRow >= 0 else { return }
        outlineView.editColumn(0, row: firstRow, with: nil, select: true)
    }

    @objc private func deleteSelectedItems(_ sender: NSMenuItem) {
        guard let outlineView = outlineView else { return }
        let rows = outlineView.effectiveRows()
        let items = rows.compactMap { outlineView.item(atRow: $0) }
        guard !items.isEmpty else { return }

        for item in items {
            if let folder = item as? FolderNode {
                vm.deleteFolder(node: folder)
            } else if let result = item as? ResultNode {
                let parent = outlineView.parent(forItem: result) as? FolderNode
                vm.deleteResult(parent?.id, name: result.name)
            }
        }
    }
}
