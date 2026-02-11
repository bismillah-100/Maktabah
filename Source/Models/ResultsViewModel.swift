//
//  ResultsViewModel.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

import Foundation

class ResultsViewModel {
    static var shared: ResultsViewModel = .init()

    let db: ResultsHandler = .shared

    // sumber data
    private(set) var folderRoots: [FolderNode] = []
    private(set) var folderResults: [Int64?: [ResultNode]] = [:] // hasil per folder (nullable key -> root)

    // CACHE STRUKTURAL (index untuk operasi cepat)
    private(set) var folderById: [Int64: FolderNode] = [:]
    private(set) var parentById: [Int64: Int64?] = [:]      // parentById[childId] = parentId (nil = root)
    private(set) var resultById: [Int64: ResultNode] = [:]  // lookup ResultNode by id

    private init() {}

    // MARK: - Initial load / indexes

    func getFolders() async {
        var roots = db.fetchFolderTree()
        roots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        sortTree(roots)

        folderRoots = roots
        rebuildFolderIndex()
    }

    func dbLoadAllResults() async {
        var allResults: [Int64?: [ResultNode]] = [:]

        // load results for a specific folder id (nullable)
        func loadResultsForFolderId(_ folderId: Int64?) {
            let results = db.fetchResults(forFolder: folderId)
            if !results.isEmpty {
                let sortedNodes = results.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                allResults[folderId] = sortedNodes
            } else {
                // ensure empty arrays not stored — keep behavior consistent with existing code
            }
        }

        loadResultsForFolderId(nil)

        func loadResultsForFolder(_ folder: FolderNode) {
            loadResultsForFolderId(folder.id)
            for child in folder.children {
                loadResultsForFolder(child)
            }
        }

        for root in folderRoots {
            loadResultsForFolder(root)
        }

        self.folderResults = allResults
        rebuildResultIndex()
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
    }

    func addSubFolder(parentNode: FolderNode, name: String) throws {
        guard let id = try db.insertSubFolder(parentNode: parentNode, name: name) else { return }

        let newNode = FolderNode(id: id, name: name)
        parentNode.children.append(newNode)
        parentNode.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // update caches
        updateFolder(newNode, newParent: parentNode.id)
    }

    // Memperbarui nama folder — temukan node lewat index, jangan asumsi root
    func updateFolderName(id folderId: Int64, newName: String) throws {
        try db.updateFolderName(id: folderId, newName: newName)
        if let node = folderById[folderId] {
            node.name = newName
            // jika perlu, resort siblings parent.children (optional)
            if let parentId = parentById[folderId], let pId = parentId {
                if let parent = folderById[pId] {
                    parent.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            } else {
                folderRoots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        } else {
            // fallback: try to find and update (shouldn't happen if index consistent)
            if let idx = folderRoots.firstIndex(where: { $0.id == folderId }) {
                folderRoots[idx].name = newName
            }
        }
    }

    // Memperbarui nama result berdasarkan id (bukan name)
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
                arr[i] = node
                arr.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                folderResults[folderId] = arr
            }
        }

        // update index
        resultById[resultId] = node
    }

    func deleteFolder(node: FolderNode) {
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
        for rid in removedResultIds { resultById.removeValue(forKey: rid) }

        // remove folder nodes from tree
        removeNodeFromTree(node)

        // update indexes
        for id in ids {
            removeFolder(id)
        }
    }

    func deleteResult(_ parentFolderId: Int64?, name: String) {
        // Prefer deleting by id; but current API deletes by (parent,name)
        db.deleteResult(parentFolderId, name: name)

        // remove from memory
        if var results = folderResults[parentFolderId] {
            // find all matching ids with same name (if duplicates exist, remove all that match name)
            let removed = results.filter { $0.name == name }
            results.removeAll(where: { $0.name == name })

            if results.isEmpty {
                folderResults.removeValue(forKey: parentFolderId)
            } else {
                folderResults[parentFolderId] = results
            }

            // remove from resultById
            for r in removed {
                resultById.removeValue(forKey: r.id)
            }
        }
    }

    // MARK: - Move folder / move result

    func moveNode(draggedNode: FolderNode, newParent: FolderNode?) throws {
        try db.updateParent(of: draggedNode.id, to: newParent?.id)
        // 1. Cek apakah newParent adalah descendant dari draggedNode
        if let parent = newParent {
            if isDescendant(parent, of: draggedNode) {
                #if DEBUG
                print("Tidak bisa memindahkan folder ke dalam dirinya sendiri")
                #endif
                return
            }
        }

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

        // NOTE:
        // descendants tetap memiliki parentById yang menunjuk ke immediate parent (yang berada di subtree).
        // Karena kita memindahkan node sebagai object yang sama, parentById untuk descendant masih valid.
        // Hanya parentById[draggedNode.id] perlu diupdate (sudah di atas).

        // update folderById if missing (usually not necessary)
        folderById[draggedNode.id] = draggedNode
        // 4. Update results di semua descendant folders
        let allIds = getAllDescendantIds(of: draggedNode)
        for id in allIds {
            db.updateResultsFolder(oldFolderId: id, newFolderId: id)
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

        // Update in-memory: remove from old list
        if var oldList = folderResults[oldFolderId] {
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

        // Update index
        resultById[resultId] = node
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

    // search folders in memory (returns folder nodes)
    func searchFoldersInMemory(_ query: String) -> [FolderNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let lower = q.lowercased()
        var matches: [FolderNode] = []

        for (_, node) in folderById {
            if node.name.lowercased().contains(lower) {
                matches.append(node)
            }
        }

        return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // search results (all results across folderResults)
    func searchResultsInMemory(_ query: String) -> [ResultNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let lower = q.lowercased()
        var matches: [ResultNode] = []

        for (_, r) in resultById {
            if r.name.lowercased().contains(lower) {
                matches.append(r)
            }
        }

        return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Mengembalikan tuple (result, folderId, folderPathString)
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

    // Cache helper
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
