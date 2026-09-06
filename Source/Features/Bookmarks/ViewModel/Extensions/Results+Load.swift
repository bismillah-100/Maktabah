//
//  Results+Load.swift
//  Maktabah
//

import Foundation

extension ResultsViewModel {
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

        folderResults = allResults
        rebuildResultIndex()
        notifyChange(.fullReload)
    }

    func rebuildFolderIndex() {
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

    func rebuildResultIndex() {
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
}
