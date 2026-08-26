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
    var writer: Bool = true
    weak var delegate: ResultsDelegate?

    var folderRoots: [FolderNode] {
        vm.folderRoots
    }

    var folderResults: [Int64?: [ResultNode]] {
        vm.folderResults
    }

    private let folderCellIdentifier = NSUserInterfaceItemIdentifier(CellIViewIdentifier.bookmarkParent.rawValue)
    private let resultCellIdentifier = NSUserInterfaceItemIdentifier(CellIViewIdentifier.bookmarkChild.rawValue)

    private var isSearching = false
    private var searchResultsByFolder: [Int64?: [ResultNode]] = [:]
    private var matchingFolderIds: Set<Int64> = []

    // MARK: - Error Strings

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

    // MARK: - Init

    init(
        outlineView: NSOutlineView!,
        delegate: ResultsDelegate? = nil,
        writer: Bool = true
    ) {
        self.writer = writer
        self.outlineView = outlineView
        self.delegate = delegate
        super.init()

        setupNibs()
        setupOutlineView()
        setupViewModelBindings()
    }

    private func setupNibs() {
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
        outlineView.registerForDraggedTypes([.folderNode, .resultNode])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
    }

    private func setupOutlineView() {
        guard let outlineView else { return }
        outlineView.target = self
        outlineView.doubleAction = #selector(onDoubleClick(_:))

        let itemMenu = NSMenu()
        itemMenu.delegate = self
        outlineView.menu = itemMenu
    }

    private func setupViewModelBindings() {
        vm.onTreeChange = { [weak self] change in
            self?.applyTreeChange(change)
        }
    }

    // MARK: - Tree Changes

    func applyTreeChange(_ change: BookmarkTreeChange) {
        guard !isSearching else {
            outlineView.reloadData()
            return
        }

        switch change {
        case .fullReload:
            outlineView.reloadData()
        case .insertFolder, .removeFolder, .updateFolder, .moveFolder:
            applyFolderTreeChange(change)
        case .insertResult, .removeResult, .updateResult, .moveResult:
            applyResultTreeChange(change)
        }
    }

    private func applyFolderTreeChange(_ change: BookmarkTreeChange) {
        switch change {
        case let .insertFolder(_, parent, index):
            outlineView.insertItems(at: IndexSet(integer: index), inParent: parent, withAnimation: .effectGap)
        case let .removeFolder(_, parent, index):
            outlineView.removeItems(at: IndexSet(integer: index), inParent: parent, withAnimation: .effectFade)
        case let .updateFolder(folder):
            outlineView.reloadItem(folder)
        case let .moveFolder(_, oldParent, oldIndex, newParent, newIndex):
            outlineView.moveItem(at: oldIndex, inParent: oldParent, to: newIndex, inParent: newParent)
            outlineView.reloadItem(newParent)
            outlineView.reloadItem(oldParent)
        default:
            break
        }
    }

    private func applyResultTreeChange(_ change: BookmarkTreeChange) {
        guard !writer else { return }

        switch change {
        case let .insertResult(_, parentId, index):
            let parentFolder = parentId.flatMap { vm.findFolder($0) }
            let folderCount = parentFolder?.children.count ?? vm.folderRoots.count
            outlineView.insertItems(at: IndexSet(integer: folderCount + index), inParent: parentFolder, withAnimation: .effectGap)
            outlineView.reloadItem(parentFolder)

        case let .removeResult(_, parentId, index):
            let parentFolder = parentId.flatMap { vm.findFolder($0) }
            let folderCount = parentFolder?.children.count ?? vm.folderRoots.count
            outlineView.removeItems(at: IndexSet(integer: folderCount + index), inParent: parentFolder, withAnimation: .effectFade)
            outlineView.reloadItem(parentFolder)

        case let .updateResult(result):
            outlineView.reloadItem(result)

        case let .moveResult(_, oldParentId, oldIndex, newParentId, newIndex):
            let oldParent = oldParentId.flatMap { vm.findFolder($0) }
            let newParent = newParentId.flatMap { vm.findFolder($0) }
            let oldFolderCount = oldParent?.children.count ?? vm.folderRoots.count
            let newFolderCount = newParent?.children.count ?? vm.folderRoots.count

            outlineView.moveItem(
                at: oldFolderCount + oldIndex, inParent: oldParent,
                to: newFolderCount + newIndex, inParent: newParent
            )
            if let newParent { outlineView.reloadItem(newParent) }
            outlineView.reloadItem(oldParent)

        default:
            break
        }
    }

    // MARK: - Search & Filtering

    func searchResults(for text: String) {
        searchTask?.cancel()

        if text.isEmpty {
            resetSearchState()
            return
        }

        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }

            let query = text.lowercased()
            let matchedFolders = vm.searchFoldersInMemory(query)
            matchingFolderIds = Set(matchedFolders.map(\.id))

            let resultsWithPath = vm.searchResultsWithFolderPath(query)
            buildGroupedSearchResults(from: resultsWithPath)

            isSearching = true
            applySearchUI(resultsWithPath: resultsWithPath)
        }
    }

    private func resetSearchState() {
        isSearching = false
        searchResultsByFolder.removeAll()
        matchingFolderIds.removeAll()
        outlineView.reloadData()
    }

    private func buildGroupedSearchResults(from resultsWithPath: [SearchResultWithPath]) {
        searchResultsByFolder = Dictionary(
            grouping: resultsWithPath.map(\.result),
            by: { $0.parentId }
        )

        for key in searchResultsByFolder.keys {
            searchResultsByFolder[key]?.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func applySearchUI(resultsWithPath: [SearchResultWithPath]) {
        outlineView.reloadData()

        let foldersToExpand = Set(searchResultsByFolder.keys.compactMap { $0 }).union(matchingFolderIds)
        for folderId in foldersToExpand {
            expandFolderChain(folderId)
        }

        if let first = resultsWithPath.first {
            let row = outlineView.row(forItem: first.result)
            outlineView.scrollRowToVisible(row)
        } else if let folderId = matchingFolderIds.first, let folder = vm.findFolder(folderId) {
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
        if matchingFolderIds.contains(folder.id) { return true }
        if let results = searchResultsByFolder[folder.id], !results.isEmpty { return true }
        return folder.children.contains { shouldShowFolder($0) }
    }

    func visibleFolders(in folder: FolderNode) -> [FolderNode] {
        guard isSearching else { return folder.children }
        if matchingFolderIds.contains(folder.id) { return folder.children }
        return folder.children.filter { shouldShowFolder($0) }
    }

    func visibleItems(in folderId: Int64?) -> [ResultNode] {
        guard isSearching else { return folderResults[folderId] ?? [] }
        guard let folderId else { return searchResultsByFolder[nil] ?? [] }
        if matchingFolderIds.contains(folderId) { return folderResults[folderId] ?? [] }
        return searchResultsByFolder[folderId] ?? []
    }

    static func showAlertCreateFolderError(subFolder: Bool = false) {
        let message = subFolder ? Self.inFolderCreateErrorDesc : Self.folderCreateErrorDesc
        ReusableFunc.showAlert(title: Self.folderCreateErrorTitle, message: message, style: .critical)
    }
}

// MARK: - NSOutlineViewDataSource

extension ResultsViewManager: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let folder = item as? FolderNode {
            let foldersToShow = visibleFolders(in: folder)
            let itemsToShow = writer ? 0 : visibleItems(in: folder.id).count
            return foldersToShow.count + itemsToShow
        }

        let rootFolders = isSearching ? folderRoots.filter { shouldShowFolder($0) } : folderRoots
        let rootItems = writer ? [] : visibleItems(in: nil)
        return rootFolders.count + rootItems.count
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let folder = item as? FolderNode else { return false }
        let folders = visibleFolders(in: folder)
        let items = visibleItems(in: folder.id)
        return !folders.isEmpty || (!writer && !items.isEmpty)
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let folder = item as? FolderNode {
            let foldersToShow = visibleFolders(in: folder)
            if index < foldersToShow.count {
                return foldersToShow[index]
            }
            let itemsToShow = visibleItems(in: folder.id)
            return itemsToShow[index - foldersToShow.count]
        }

        let rootFolders = isSearching ? folderRoots.filter { shouldShowFolder($0) } : folderRoots
        if index < rootFolders.count {
            return rootFolders[index]
        }
        let rootItems = writer ? [] : visibleItems(in: nil)
        return rootItems[index - rootFolders.count]
    }

    func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
        (item as? FolderNode)?.id
    }

    func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? {
        guard let id = object as? Int64 else { return nil }
        return vm.findFolder(id)
    }
}

// MARK: - NSOutlineViewDelegate

extension ResultsViewManager: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let colId = tableColumn?.identifier.rawValue else { return nil }

        switch colId {
        case "query":
            guard let result = item as? ResultNode else { return nil }
            return makeQueryCell(for: result, in: outlineView)
        case "modifiedDate":
            guard let result = item as? ResultNode else { return nil }
            return makeDateCell(for: result, in: outlineView)
        case "AutomaticTableColumnIdentifier.0":
            return makeNameCell(for: item, in: outlineView)
        default:
            return nil
        }
    }

    private func makeQueryCell(for result: ResultNode, in outlineView: NSOutlineView) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier("queryCell")
        let cell = (outlineView.makeView(
            withIdentifier: cellIdentifier, owner: self
        ) as? NSTableCellView) ?? createCustomCellView(identifier: cellIdentifier)

        cell.textField?.stringValue = result.items.first?.query ?? ""
        return cell
    }

    private func makeDateCell(for result: ResultNode, in outlineView: NSOutlineView) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier("dateCell")
        let cell = (outlineView.makeView(
            withIdentifier: cellIdentifier, owner: self
        ) as? NSTableCellView) ?? createCustomCellView(
            identifier: cellIdentifier, textColor: .secondaryLabelColor
        )

        if let timestamp = result.lastModified {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let formattedString = Calendar.current.isDateInToday(date)
                ? RelativeDateTimeFormatter.shared.localizedString(for: date, relativeTo: Date())
                : DateFormatter.mediumDate.string(from: date)
            cell.textField?.stringValue = formattedString
        } else {
            cell.textField?.stringValue = "-"
        }
        return cell
    }

    private func createCustomCellView(
        identifier: NSUserInterfaceItemIdentifier,
        textColor: NSColor = .labelColor
    ) -> NSTableCellView {
        let newCell = NSTableCellView()
        newCell.identifier = identifier
        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        textField.textColor = textColor
        newCell.addSubview(textField)
        newCell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 2),
            textField.trailingAnchor.constraint(equalTo: newCell.trailingAnchor, constant: -2),
            textField.centerYAnchor.constraint(equalTo: newCell.centerYAnchor),
        ])
        return newCell
    }

    private func makeNameCell(for item: Any, in outlineView: NSOutlineView) -> NSView? {
        if let result = item as? ResultNode,
           let cell = outlineView.makeView(withIdentifier: resultCellIdentifier, owner: self) as? NSTableCellView,
           let textField = cell.textField
        {
            let mode = SearchMode(rawValue: result.searchMode) ?? .phrase
            cell.imageView?.image = .init(systemSymbolName: SearchMode.imageNameForMode(mode), accessibilityDescription: nil)
            textField.stringValue = result.name
            textField.delegate = self
            textField.isEditable = true
            return cell
        }

        if let folder = item as? FolderNode,
           let cell = outlineView.makeView(withIdentifier: folderCellIdentifier, owner: self) as? NSTableCellView,
           let textField = cell.textField
        {
            textField.stringValue = folder.name
            textField.delegate = self
            textField.isEditable = true
            return cell
        }

        return nil
    }

    @objc private func onDoubleClick(_ sender: AnyObject) {
        guard let clickedRow = outlineView?.clickedRow,
              clickedRow >= 0, let item = outlineView?.item(atRow: clickedRow)
        else { return }

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

// MARK: - Pasteboard Types

extension NSPasteboard.PasteboardType {
    static let folderNode = NSPasteboard.PasteboardType("com.maktab.folderNode")
    static let resultNode = NSPasteboard.PasteboardType("com.maktab.resultNode")
}
