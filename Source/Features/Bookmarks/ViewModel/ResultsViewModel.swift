//
//  ResultsViewModel.swift
//  Maktabah
//
//  Created by MacBook on 06/12/25.
//

import Foundation
import Observation

@Observable
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
            for child in node.children {
                walk(child)
            }
        }
        for root in folderRoots {
            walk(root)
        }
        return list
    }

    var allResults: [ResultNode] {
        folderResults.values.flatMap { $0 }
    }

    /// Dipanggil setelah setiap operasi yang mengubah data.
    /// Mac (`ResultsViewManager`) menggunakannya untuk reload `NSOutlineView`.
    var onTreeChange: ((BookmarkTreeChange) -> Void)?

    func notifyChange(_ change: BookmarkTreeChange) {
        onTreeChange?(change)
    }

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSavedResultsTreeDidUpdate),
            name: .savedResultsTreeDidUpdate,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBookIdMigrated(_:)),
            name: .bookIdMigrated,
            object: nil
        )
    }

    @objc private func handleBookIdMigrated(_ notification: Notification) {
        Task {
            await getFolders()
            await dbLoadAllResults()
            notifyChange(.fullReload)
        }
    }

    @objc private func handleSavedResultsTreeDidUpdate() {
        Task {
            await getFolders()
            await dbLoadAllResults()
        }
    }
}
