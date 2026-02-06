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

    private(set) var folderRoots: [FolderNode] = []
    private(set) var folderResults: [Int64?: [ResultNode]] = [:] // TAMBAHKAN INI

    private init() {}

    func getFolders() async {
        var roots = db.fetchFolderTree()
        roots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        sortTree(roots)

        folderRoots = roots
    }

    func sortTree(_ nodes: [FolderNode]) {
        for node in nodes {
            node.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            sortTree(node.children)
        }
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
            }
        }

        // load root results (folderId == nil)
        loadResultsForFolderId(nil)

        // load for every folder in tree
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
    }

    func addRootFolder(name: String) throws {
        guard let id = try db.insertRootFolder(name: name) else {
            return
        }

        folderRoots.append(FolderNode(id: id, name: name))
    }

    func addSubFolder(parentNode: FolderNode, name: String) throws {
        guard let id = try db.insertSubFolder(
            parentNode: parentNode,
            name: name
        ) else {
            return
        }

        let newNode = FolderNode(id: id, name: name)
        parentNode.children.append(newNode)
    }

    // Memperbarui nama folder di folderRoots
    func updateFolderName(id folderId: Int64, newName: String) throws {
        try db.updateFolderName(id: folderId, newName: newName)
        if let index = folderRoots.firstIndex(where: { $0.id == folderId }) {
            folderRoots[index].name = newName
        }
    }

    // Memperbarui nama query di folderResults
    func updateResultQueryName(id resultId: Int64, newName: String, folderId: Int64?) throws {
        // Cari folder yang sesuai
        guard let resultsArray = folderResults[folderId] else { return }

        // Cari ResultNode yang sesuai di dalam array
        if let index = resultsArray.firstIndex(where: { $0.id == resultId }) {
            // Panggil fungsi database BARU untuk memperbarui SEMUA baris
            try db.updateResultQueryName(
                folderId: folderId,
                oldName: resultsArray[index].name,
                newName: newName
            )

            resultsArray[index].name = newName
            // Perbarui dictionary
            folderResults[folderId] = resultsArray
        }
    }

    func deleteFolder(node: FolderNode) {
        db.deleteFolder(node.id)
        removeNodeFromTree(node)
    }

    func deleteResult(_ parentFolderId: Int64?, name: String) {
        // 1. Delete dari database (atomic)
        db.deleteResult(parentFolderId, name: name)

        // 2. Hapus dari memory
        if var results = folderResults[parentFolderId] {
            results.removeAll(where: { $0.name == name })

            // Update atau hapus entry jika kosong
            if results.isEmpty {
                folderResults.removeValue(forKey: parentFolderId)
            } else {
                folderResults[parentFolderId] = results
            }
        }
    }

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
        } else {
            folderRoots.append(draggedNode)
            folderRoots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        // 4. Update results di semua descendant folders
        let allIds = getAllDescendantIds(of: draggedNode)
        for id in allIds {
            db.updateResultsFolder(oldFolderId: id, newFolderId: id)
        }
    }

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

    func findFolder(_ id: Int64) -> FolderNode? {
        for root in folderRoots {
            if let found = findFolderRecursive(root, id) {
                return found
            }
        }
        return nil
    }

    func findFolder(optionalId id: Int64?) -> FolderNode? {
        guard let id = id else { return nil } // nil berarti root, tidak ada FolderNode
        return findFolder(id)
    }

    private func findFolderRecursive(_ node: FolderNode, _ id: Int64) -> FolderNode? {
        if node.id == id { return node }

        for child in node.children {
            if let found = findFolderRecursive(child, id) {
                return found
            }
        }

        return nil
    }

    func findResultNode(_ id: Int64) -> ResultNode? {
        for (_, results) in folderResults {
            if let result = results.first(where: { $0.id == id }) {
                return result
            }
        }
        return nil
    }

    // gunakan Int64? untuk from dan to
    func moveResult(_ resultId: Int64, to newFolderId: Int64?) throws {
        guard let node = findResultNode(resultId) else { return }
        let oldFolderId = node.parentId
        try db.updateResultParent(
            newParentId: newFolderId,
            oldParent: oldFolderId,
            name: node.name
        )

        // Hapus dari folder lama (oldFolderId bisa nil)
        if var oldList = folderResults[oldFolderId] {
            oldList.removeAll { $0.id == resultId }
            folderResults[oldFolderId] = oldList
        }

        // Tambah ke folder baru (newFolderId bisa nil = root)
        folderResults[newFolderId, default: []].append(node)

        // Sort kembali jika perlu
        folderResults[newFolderId] = folderResults[newFolderId]?.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // Cari di semua folder (in-memory)
    func searchResultsInMemory(_ query: String) -> [ResultNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let lower = q.lowercased()
        var matches: [ResultNode] = []

        for (_, results) in folderResults {
            for r in results {
                if r.name.lowercased().contains(lower) {
                    matches.append(r)
                }
                // jika ResultNode punya properti lain (mis. body/text) tambahkan ceknya di sini
                // else if r.body?.lowercased().contains(lower) { matches.append(r) }
            }
        }

        return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /*
    // Cari di folder tertentu (folderId bisa nil -> root)
    func searchResults(inFolder folderId: Int64?, query: String) -> [ResultNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let lower = q.lowercased()
        guard let list = folderResults[folderId] else { return [] }
        
        return list.filter { $0.name.lowercased().contains(lower) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
     */

    // Mengembalikan tuple (result, folderId, folderPathString)
    func searchResultsWithFolderPath(_ query: String) -> [(result: ResultNode, folderId: Int64?, folderPath: String)] {
        let results = searchResultsInMemory(query)
        return results.map { result in
            let path = folderPath(for: result.parentId)
            return (result: result, folderId: result.parentId, folderPath: path)
        }
    }

    // Helper: buat path folder dari folderRoots; jika nil -> "Root"
    private func folderPath(for folderId: Int64?) -> String {
        guard let id = folderId else { return "Root" }

        // cari node
        if findFolder(optionalId: id) != nil {
            // naik sampai root — kita butuh parent references; jika FolderNode tidak menyimpan parent,
            // kita bisa membangun path dengan traversal dari folderRoots.
            var stack: [String] = []
            func dfs(_ current: FolderNode, _ targetId: Int64) -> Bool {
                if current.id == targetId {
                    stack.insert(current.name, at: 0)
                    return true
                }
                for child in current.children {
                    if dfs(child, targetId) {
                        stack.insert(current.name, at: 0)
                        return true
                    }
                }
                return false
            }

            for root in folderRoots {
                if dfs(root, id) { break }
            }
            return stack.joined(separator: " / ")
        } else {
            return "Unknown Folder"
        }
    }

}
