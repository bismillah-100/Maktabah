//
//  Results+Search.swift
//  Maktabah
//

import Foundation

extension ResultsViewModel {
    // MARK: - Search helpers

    /// search folders in memory (returns folder nodes)
    func searchFoldersInMemory(_ query: String) -> [FolderNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var matches: [FolderNode] = []

        for (_, node) in folderById where node.name.localizedStandardContains(q) {
            matches.append(node)
        }

        return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// search results (all results across folderResults)
    func searchResultsInMemory(_ query: String) -> [ResultNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var matches: [ResultNode] = []

        for (_, r) in resultById where r.name.localizedStandardContains(q) {
            matches.append(r)
        }

        return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Mengembalikan array SearchResultWithPath (result, folderId, folderPathString)
    func searchResultsWithFolderPath(_ query: String) -> [SearchResultWithPath] {
        let results = searchResultsInMemory(query)
        return results.map { result in
            let path = folderPath(for: result.parentId)
            return SearchResultWithPath(result: result, folderId: result.parentId, folderPath: path)
        }
    }
}
