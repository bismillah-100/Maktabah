//
//  Results+ResultOps.swift
//  Maktabah
//

import Foundation

extension ResultsViewModel {
    // MARK: - Result Operations

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

    func deleteResult(_ parentFolderId: Int64?, name: String) {
        db.deleteResult(parentFolderId, name: name)

        guard var results = folderResults[parentFolderId] else { return }

        // Kumpulkan index yang akan dihapus
        let deletedIndices: [(ResultNode, Int)] = results.enumerated().compactMap { i, r in
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

    func saveSearchResults(results: [SearchResultItem], query: String, searchMode: Int = 0, nearDistance: Int = 10, folderId: Int64?, name: String) throws {
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

        let options = ResultSaveOptions(
            folderId: folderId,
            query: query,
            name: name,
            searchMode: searchMode,
            nearDistance: nearDistance
        )
        try db.insertResults(
            groupedResults,
            options: options
        )
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
}
