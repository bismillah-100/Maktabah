//
//  ResultsViewModel.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

import Foundation
#if os(iOS)
import Observation
#endif

#if os(iOS)
@Observable
#endif
@MainActor
class ResultsViewModel {
    static var shared: ResultsViewModel = .init()

    let db: ResultsHandler = .shared

    // sumber data
    var folderRoots: [FolderNode] = []
    var folderResults: [Int64?: [ResultNode]] = [:] // hasil per folder (nullable key -> root)

    // CACHE STRUKTURAL (index untuk operasi cepat)
    var folderById: [Int64: FolderNode] = [:]
    var parentById: [Int64: Int64?] = [:] // parentById[childId] = parentId (nil = root)
    var resultById: [Int64: ResultNode] = [:] // lookup ResultNode by id

    var allFolders: [FolderNode] {
        var list = [FolderNode]()
        func walk(_ node: FolderNode) {
            list.append(node)
            for child in node.children { walk(child) }
        }
        for root in folderRoots { walk(root) }
        return list
    }

    var allResults: [ResultNode] {
        folderResults.values.flatMap { $0 }
    }

    /// Dipanggil setelah setiap operasi yang mengubah data.
    /// Mac (`ResultsViewManager`) menggunakannya untuk reload `NSOutlineView`.
    var onTreeChange: ((BookmarkTreeChange) -> Void)?

    private func notifyChange(_ change: BookmarkTreeChange) {
        onTreeChange?(change)
    }

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSavedResultsTreeDidUpdate),
            name: .savedResultsTreeDidUpdate,
            object: nil
        )
    }

    @objc private func handleSavedResultsTreeDidUpdate() {
        Task {
            await getFolders()
            await dbLoadAllResults()
        }
    }

    // MARK: - Initial load / indexes

    func getFolders() async {
        let roots = await Task.detached {
            var roots = ResultsHandler.shared.fetchFolderTree()
            roots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            func localSortTree(_ nodes: [FolderNode]) {
                for node in nodes {
                    node.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    localSortTree(node.children)
                }
            }
            localSortTree(roots)
            return roots
        }.value

        folderRoots = roots
        rebuildFolderIndex()
        notifyChange(.fullReload)
    }

    func dbLoadAllResults() async {
        let currentRoots = folderRoots

        let allResults = await Task.detached {
            var resultsMap: [Int64?: [ResultNode]] = [:]
            let dbHandler = ResultsHandler.shared

            func loadResultsForFolderId(_ folderId: Int64?) {
                let results = dbHandler.fetchResults(forFolder: folderId)
                if !results.isEmpty {
                    let sortedNodes = results.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    resultsMap[folderId] = sortedNodes
                }
            }

            loadResultsForFolderId(nil)

            func loadResultsForFolder(_ folder: FolderNode) {
                loadResultsForFolderId(folder.id)
                for child in folder.children {
                    loadResultsForFolder(child)
                }
            }

            for root in currentRoots {
                loadResultsForFolder(root)
            }

            return resultsMap
        }.value

        self.folderResults = allResults
        rebuildResultIndex()
        notifyChange(.fullReload)
    }

    private func rebuildFolderIndex() {
        folderById.removeAll()
        parentById.removeAll()

        func walk(_ node: FolderNode, parent: Int64?) {
            updateFolder(node, newParent: parent)
            for c in node.children {
                walk(c, parent: node.id)
            }
        }

        for root in folderRoots {
            walk(root, parent: nil)
        }
    }

    private func rebuildResultIndex() {
        resultById.removeAll()
        // folderResults keys are Int64?; iterate and map
        for (folderId, results) in folderResults {
            for r in results {
                resultById[r.id] = r
                // ensure result parentId is consistent
                r.parentId = folderId
            }
        }
    }

    // MARK: - Folder helpers

    func sortTree(_ nodes: [FolderNode]) {
        for node in nodes {
            node.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            sortTree(node.children)
        }
    }

    func addRootFolder(name: String) throws {
        guard let id = try db.insertRootFolder(name: name) else { return }

        let node = FolderNode(id: id, name: name)
        folderRoots.append(node)
        folderRoots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // update caches
        updateFolder(node, newParent: nil)

        let index = folderRoots.firstIndex(of: node) ?? 0
        notifyChange(.insertFolder(folder: node, parent: nil, index: index))
    }

    func addSubFolder(parentNode: FolderNode, name: String) throws {
        guard let id = try db.insertSubFolder(parentNode: parentNode, name: name) else { return }

        let newNode = FolderNode(id: id, name: name)
        parentNode.children.append(newNode)
        parentNode.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // update caches
        updateFolder(newNode, newParent: parentNode.id)

        let index = parentNode.children.firstIndex(of: newNode) ?? 0
        notifyChange(.insertFolder(folder: newNode, parent: parentNode, index: index))
    }

    /// Memperbarui nama folder — temukan node lewat index, jangan asumsi root
    func updateFolderName(id folderId: Int64, newName: String) throws {
        try db.updateFolderName(id: folderId, newName: newName)
        if let node = folderById[folderId] {
            node.name = newName

            var oldIndex = -1
            var newIndex = -1
            var parentNode: FolderNode? = nil

            // jika perlu, resort siblings parent.children (optional)
            if let parentId = parentById[folderId], let pId = parentId {
                if let parent = folderById[pId] {
                    parentNode = parent
                    oldIndex = parent.children.firstIndex(of: node) ?? -1
                    parent.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    newIndex = parent.children.firstIndex(of: node) ?? -1
                }
            } else {
                oldIndex = folderRoots.firstIndex(of: node) ?? -1
                folderRoots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                newIndex = folderRoots.firstIndex(of: node) ?? -1
            }

            if oldIndex != -1, newIndex != -1, oldIndex != newIndex {
                notifyChange(.moveFolder(folder: node, oldParent: parentNode, oldIndex: oldIndex, newParent: parentNode, newIndex: newIndex))
            }
            notifyChange(.updateFolder(folder: node))
        } else {
            // fallback: try to find and update (shouldn't happen if index consistent)
            if let idx = folderRoots.firstIndex(where: { $0.id == folderId }) {
                folderRoots[idx].name = newName
            }
            notifyChange(.fullReload)
        }
    }

    /// Memperbarui nama result berdasarkan id (bukan name)
    func updateResultQueryName(id resultId: Int64, newName: String) throws {
        guard let node = resultById[resultId] else { return }
        let folderId = node.parentId

        // update DB by id if possible; fallback using existing DB API
        try db.updateResultQueryName(
            folderId: folderId,
            oldName: node.name,
            newName: newName
        )

        // in-memory update
        node.name = newName

        // keep folderResults sorted
        if var arr = folderResults[folderId] {
            if let i = arr.firstIndex(where: { $0.id == resultId }) {
                let oldIndex = i
                arr[i] = node
                arr.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                folderResults[folderId] = arr

                let newIndex = arr.firstIndex(where: { $0.id == resultId }) ?? oldIndex
                if oldIndex != newIndex {
                    notifyChange(.moveResult(result: node, oldParentId: folderId, oldIndex: oldIndex, newParentId: folderId, newIndex: newIndex))
                }
            }
        }

        // update index
        resultById[resultId] = node
        notifyChange(.updateResult(result: node))
    }

    func deleteFolder(node: FolderNode) {
        var index = -1
        let parentId = parentById[node.id].flatMap { $0 }
        let parentNode = parentId.flatMap { folderById[$0] }

        if let p = parentNode {
            index = p.children.firstIndex(of: node) ?? -1
        } else {
            index = folderRoots.firstIndex(of: node) ?? -1
        }

        // delete in DB
        db.deleteFolder(node.id)

        // remove results under this subtree
        let ids = getAllDescendantIds(of: node)
        for id in ids {
            // remove folderResults entries for each descendant
            folderResults.removeValue(forKey: id)
        }

        // remove resultById entries that belonged to those folders
        var removedResultIds: [Int64] = []
        for (rid, rnode) in resultById {
            if let p = rnode.parentId, ids.contains(p) {
                removedResultIds.append(rid)
            }
        }

        for rid in removedResultIds {
            resultById.removeValue(forKey: rid)
        }

        // remove folder nodes from tree
        removeNodeFromTree(node)

        // update indexes
        for id in ids {
            removeFolder(id)
        }

        if index != -1 {
            notifyChange(.removeFolder(folder: node, parent: parentNode, index: index))
        } else {
            notifyChange(.fullReload)
        }
    }

    func deleteResult(_ parentFolderId: Int64?, name: String) {
        db.deleteResult(parentFolderId, name: name)

        guard var results = folderResults[parentFolderId] else { return }

        // Kumpulkan index yang akan dihapus
        let deletedIndices: [(ResultNode, Int)] = results.enumerated().compactMap { (i, r) in
            r.name == name ? (r, i) : nil
        }

        // Hapus satu per satu dari belakang, notify setiap kali.
        // Ini menjaga agar index tetap valid karena penghapusan dari
        // belakang tidak menggeser posisi elemen sebelumnya.
        for (r, i) in deletedIndices.reversed() {
            results.remove(at: i)
            folderResults[parentFolderId] = results.isEmpty ? nil : results
            resultById.removeValue(forKey: r.id)
            notifyChange(.removeResult(result: r, parentId: parentFolderId, index: i))
        }

        if results.isEmpty {
            folderResults.removeValue(forKey: parentFolderId)
        }
    }

    func saveSearchResults(results: [SearchResultItem], query: String, folderId: Int64?, name: String) throws {
        var groupedResults: [String: GroupedResult] = [:]

        for item in results {
            let origTable = item.tableName.hasPrefix("b") ? String(item.tableName.dropFirst()) : item.tableName
            guard let arc = Int(item.archive),
                  let table = Int(origTable) else { continue }

            let bookId = String(item.bookId)
            let key = "\(arc)_\(table)"

            if var existingGroup = groupedResults[key] {
                if !existingGroup.contentIds.contains(bookId) {
                    existingGroup.contentIds.append(bookId)
                }
                groupedResults[key] = existingGroup
            } else {
                var newGroup = GroupedResult(archive: arc, bkId: table)
                newGroup.contentIds.append(bookId)
                groupedResults[key] = newGroup
            }
        }

        var firstError: Error?

        for (_, group) in groupedResults {
            let commaSeparatedContentIds = group.contentIds.joined(separator: ",")
            do {
                try db.insertResult(
                    group.archive,
                    bkId: group.bkId,
                    contentId: commaSeparatedContentIds,
                    folderId: folderId,
                    query: query,
                    name: name
                )
            } catch {
                if firstError == nil {
                    firstError = error
                }
                #if DEBUG
                print("Error saving result for group \(group):", error)
                #endif
            }
        }

        if let error = firstError {
            throw error
        }
    }

    // MARK: - Move folder / move result

    func moveNode(draggedNode: FolderNode, newParent: FolderNode?) throws {
        // 1. Cek apakah newParent adalah descendant dari draggedNode
        if let parent = newParent {
            if isDescendant(parent, of: draggedNode) {
#if DEBUG
                print("Tidak bisa memindahkan folder ke dalam dirinya sendiri")
#endif
                return
            }
        }

        let oldParentId = parentById[draggedNode.id].flatMap { $0 }
        let oldParentNode = oldParentId.flatMap { folderById[$0] }
        let oldIndex = oldParentNode?.children.firstIndex(of: draggedNode) ?? folderRoots.firstIndex(of: draggedNode) ?? -1

        try db.updateParent(of: draggedNode.id, to: newParent?.id)

        // 2. Hapus dari parent lama
        removeNodeFromTree(draggedNode)

        // 3. Tambahkan ke parent baru
        if let parent = newParent {
            parent.children.append(draggedNode)
            parent.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            parentById[draggedNode.id] = parent.id
        } else {
            folderRoots.append(draggedNode)
            folderRoots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            parentById[draggedNode.id] = nil
        }

        let newIndex = newParent?.children.firstIndex(of: draggedNode) ?? folderRoots.firstIndex(of: draggedNode) ?? -1

        // update folderById if missing (usually not necessary)
        folderById[draggedNode.id] = draggedNode
        // 4. Update results di semua descendant folders
        let allIds = getAllDescendantIds(of: draggedNode)
        for id in allIds {
            db.updateResultsFolder(oldFolderId: id, newFolderId: id)
        }

        if oldIndex != -1, newIndex != -1 {
            notifyChange(.moveFolder(folder: draggedNode, oldParent: oldParentNode, oldIndex: oldIndex, newParent: newParent, newIndex: newIndex))
        } else {
            notifyChange(.fullReload)
        }
    }

    // MARK: - Tree utilities

    private func isDescendant(_ node: FolderNode, of ancestor: FolderNode) -> Bool {
        if node.id == ancestor.id { return true }

        for child in ancestor.children {
            if isDescendant(node, of: child) { return true }
        }
        return false
    }

    private func getAllDescendantIds(of node: FolderNode) -> [Int64] {
        var ids: [Int64] = [node.id]
        for child in node.children {
            ids.append(contentsOf: getAllDescendantIds(of: child))
        }
        return ids
    }

    private func removeNodeFromTree(_ node: FolderNode) {
        if let i = folderRoots.firstIndex(where: { $0.id == node.id }) {
            folderRoots.remove(at: i)
            return
        }

        func remove(from parent: FolderNode) -> Bool {
            if let i = parent.children.firstIndex(where: { $0.id == node.id }) {
                parent.children.remove(at: i)
                return true
            }
            for child in parent.children {
                if remove(from: child) { return true }
            }
            return false
        }

        for root in folderRoots {
            if remove(from: root) { break }
        }
    }

    func moveResult(_ resultId: Int64, to newFolderId: Int64?) throws {
        guard let node = resultById[resultId] else { return }
        let oldFolderId = node.parentId
        try db.updateResultParent(
            newParentId: newFolderId,
            oldParent: oldFolderId,
            name: node.name
        )

        var oldIndex = -1

        // Update in-memory: remove from old list
        if var oldList = folderResults[oldFolderId] {
            oldIndex = oldList.firstIndex(of: node) ?? -1
            oldList.removeAll { $0.id == resultId }
            if oldList.isEmpty {
                folderResults.removeValue(forKey: oldFolderId)
            } else {
                folderResults[oldFolderId] = oldList
            }
        }

        // Change parentId on node
        node.parentId = newFolderId

        // Add to new folder
        folderResults[newFolderId, default: []].append(node)
        folderResults[newFolderId] = folderResults[newFolderId]?.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let newIndex = folderResults[newFolderId]?.firstIndex(of: node) ?? -1

        // Update index
        resultById[resultId] = node

        if oldIndex != -1, newIndex != -1 {
            notifyChange(.moveResult(result: node, oldParentId: oldFolderId, oldIndex: oldIndex, newParentId: newFolderId, newIndex: newIndex))
        } else {
            notifyChange(.fullReload)
        }
    }

    // MARK: - Find helpers using index

    func findFolder(_ id: Int64) -> FolderNode? {
        return folderById[id]
    }

    /*
     func findResultNode(_ id: Int64) -> ResultNode? {
     return resultById[id]
     }
     */

    func findParent(of node: FolderNode, in roots: [FolderNode]) -> FolderNode? {
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

    // MARK: - Search helpers

    /// search folders in memory (returns folder nodes)
    func searchFoldersInMemory(_ query: String) -> [FolderNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var matches: [FolderNode] = []

        for (_, node) in folderById {
            if node.name.localizedStandardContains(q) {
                matches.append(node)
            }
        }

        return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// search results (all results across folderResults)
    func searchResultsInMemory(_ query: String) -> [ResultNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var matches: [ResultNode] = []

        for (_, r) in resultById {
            if r.name.localizedStandardContains(q) {
                matches.append(r)
            }
        }

        return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Mengembalikan tuple (result, folderId, folderPathString)
    func searchResultsWithFolderPath(_ query: String) -> [(result: ResultNode, folderId: Int64?, folderPath: String)] {
        let results = searchResultsInMemory(query)
        return results.map { result in
            let path = folderPath(for: result.parentId)
            return (result: result, folderId: result.parentId, folderPath: path)
        }
    }

    // Helper: buat path folder dari parentById/folderById; jika nil -> "Root"
    private func folderPath(for folderId: Int64?) -> String {
        guard var id = folderId else { return "Root" }

        var parts: [String] = []
        while let node = folderById[id] {
            parts.insert(node.name, at: 0)
            if let parent = parentById[id], let p = parent {
                id = p
            } else {
                break
            }
        }
        return parts.joined(separator: " / ")
    }

    /// Cache helper
    private func updateFolder(
        _ folder: FolderNode,
        newParent: Int64?
    ) {
        // Single point untuk update semua cache
        folderById[folder.id] = folder
        parentById[folder.id] = newParent
    }

    private func removeFolder(_ id: Int64) {
        folderById.removeValue(forKey: id)
        parentById.removeValue(forKey: id)
    }
}
