//
//  Results+Tree.swift
//  Maktabah
//

import Foundation

extension ResultsViewModel {
    // MARK: - Tree utilities

    func isDescendant(_ node: FolderNode, of ancestor: FolderNode) -> Bool {
        if node.id == ancestor.id {
            return true
        }

        for child in ancestor.children where isDescendant(node, of: child) {
            return true
        }
        return false
    }

    func removeNodeFromTree(_ node: FolderNode) {
        if let i = folderRoots.firstIndex(where: { $0.id == node.id }) {
            folderRoots.remove(at: i)
            return
        }

        func remove(from parent: FolderNode) -> Bool {
            if let i = parent.children.firstIndex(where: { $0.id == node.id }) {
                parent.children.remove(at: i)
                return true
            }
            for child in parent.children where remove(from: child) {
                return true
            }
            return false
        }

        for root in folderRoots where remove(from: root) {
            break
        }
    }

    func sortTree(_ nodes: [FolderNode]) {
        for node in nodes {
            node.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            sortTree(node.children)
        }
    }

    func folderPath(for folderId: Int64?) -> String {
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

    func updateFolder(
        _ folder: FolderNode,
        newParent: Int64?
    ) {
        // Single point untuk update semua cache
        folderById[folder.id] = folder
        parentById[folder.id] = newParent
    }

    func removeFolder(_ id: Int64) {
        folderById.removeValue(forKey: id)
        parentById.removeValue(forKey: id)
    }

    func findFolder(_ id: Int64) -> FolderNode? {
        folderById[id]
    }

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
}
