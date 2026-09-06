//
//  Results+FolderOps.swift
//  Maktabah
//

import Foundation

extension ResultsViewModel {
    // MARK: - Folder Operations

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
        let ids = node.allDescendantIds
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
        for id in draggedNode.allDescendantIds {
            db.updateResultsFolder(oldFolderId: id, newFolderId: id)
        }

        if oldIndex != -1, newIndex != -1 {
            notifyChange(.moveFolder(folder: draggedNode, oldParent: oldParentNode, oldIndex: oldIndex, newParent: newParent, newIndex: newIndex))
        } else {
            notifyChange(.fullReload)
        }
    }
}
