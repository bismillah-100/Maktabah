//
//  ResultsHandler.swift
//  maktab
//
//  Created by MacBook on 05/12/25.
//

import SQLite
import Foundation

class ResultsHandler {
    private(set) var db: Connection!
    static var shared: ResultsHandler = .init()

    let foldersTbl = Table("folders")
    let id = Expression<Int64>("id")
    let name = Expression<String>("name")
    let parent = Expression<Int64?>("parent")

    let results = Table("results")
    let folderId = Expression<Int64?>("folder_id")
    let query = Expression<String>("query")
    let archive = Expression<Int>("archives")
    let bkId = Expression<Int>("bkId")
    let contentId = Expression<String>("contentId")

    private init() {}

    func setupResultDatabase(at URL: URL?) throws {
        guard var url = URL else { throw NSError(domain: "maktabah", code: 404) }
        url.appendPathComponent("SearchResults.sqlite")
        db = try Connection(url.path)
        createTables()
    }

    func createTables() {
        do {
            guard let db else {
                ReusableFunc.showAlert(title: "Database not initialized", message: "")
                return
            }

            // MARK: - folders table
            try db.run(foldersTbl.create(ifNotExists: true) { t in
                t.column(id, primaryKey: .autoincrement)
                t.column(name)
                t.column(parent)
                t.unique(name, parent)
            })

            // MARK: - results table
            try db.run(results.create(ifNotExists: true) { t in
                t.column(id, primaryKey: .autoincrement)
                t.column(folderId)
                t.column(name)
                t.column(query)
                t.column(archive)
                t.column(bkId)
                t.column(contentId)
                t.unique(folderId, name, bkId)
            })
        } catch {
            #if DEBUG
            print("Error creating tables: \(error)")
            #endif
        }

        createUniqueIndex()
    }

    func createUniqueIndex() {
        do {
            try db.run("CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_parent_name ON folders (COALESCE(parent, 0), name)")
            try db.run("CREATE UNIQUE INDEX IF NOT EXISTS idx_results_folder_name ON results (COALESCE(folder_id, 0), name)")
            // optional: mencegah duplikat konten yang sama di folder yang sama
            try db.run("DROP INDEX IF EXISTS idx_results_folder_name")
            try db.run("CREATE UNIQUE INDEX IF NOT EXISTS idx_results_folder_name_bk ON results (COALESCE(folder_id, 0), name, bkId)")
        } catch {
            #if DEBUG
            print("Create index error:", error)
            #endif
        }
    }
}

extension ResultsHandler {
    func insertRootFolder(name: String) throws -> Int64? {
        let insert = foldersTbl.insert(
            self.name <- name,
            parent <- nil
        )
        return try db.run(insert)
    }

    func insertSubFolder(parentNode: FolderNode, name: String) throws -> Int64? {
        let insert = foldersTbl.insert(
            self.name <- name,
            parent <- parentNode.id
        )
        return try db.run(insert)
    }

    func fetchFolderTree() -> [FolderNode] {
        var nodes: [Int64: FolderNode] = [:]
        var roots: [FolderNode] = []

        do {
            for row in try db.prepare(foldersTbl) {
                let node = FolderNode(id: row[id], name: row[name])
                nodes[row[id]] = node
            }

            // isi children
            for row in try db.prepare(foldersTbl) {
                if let parentId = row[parent], let parentNode = nodes[parentId] {
                    parentNode.children.append(nodes[row[id]]!)
                } else {
                    roots.append(nodes[row[id]]!)
                }
            }
        } catch {
            print("Fetch folder tree error:", error)
        }

        return roots
    }

    func deleteFolder(_ folderId: Int64) {
        do {
            try db.transaction {
                let allFolderIds = getAllDescendantIds(of: folderId)

                // Delete semua results
                for id in allFolderIds {
                    let resultsToDelete = results.filter(self.folderId == id)
                    try db.run(resultsToDelete.delete())
                }

                // Delete semua folders (dari child ke parent)
                for id in allFolderIds.reversed() {
                    let folder = foldersTbl.filter(self.id == id)
                    try db.run(folder.delete())
                }
            }
        } catch {
            print("❌ Delete transaction failed:", error)
        }
    }

    func deleteResult(_ folderId: Int64?, name: String) {
        let result = results.filter(self.folderId == folderId && self.name == name)
        do {
            try db.run(result.delete())
        } catch {
            print(error.localizedDescription)
        }
    }

    func updateParent(of id: Int64, to newParentId: Int64?) throws {
        let folder = foldersTbl.filter(self.id == id)
        try db.run(folder.update(parent <- newParentId))
    }

    func updateResultParent(newParentId: Int64?, oldParent: Int64?, name: String) throws {
        let row = results.filter(folderId == oldParent && self.name == name)
        try db.run(row.update(folderId <- newParentId))
    }
}

extension ResultsHandler {
    func insertResult(_ archive: Int, bkId: Int, contentId: String, folderId: Int64?, query: String, name: String) throws {
        let insert = results.insert(
            self.folderId <- folderId,
            self.name <- name,
            self.query <- query,
            self.archive <- archive,
            self.bkId <- bkId,
            self.contentId <- contentId
        )
        try db.run(insert)
    }

    func fetchResults(forFolder folderId: Int64?) -> [ResultNode] {
        var groupedResults: [String: (id: Int64, parentId: Int64?, items: [SavedResultsItem])] = [:]

        do {
            let query = results.filter(self.folderId == folderId)

            for row in try db.prepare(query) {
                let queryName = row[self.query]
                let savedName = row[name]
                let resultId = row[id]
                let parentId = row[self.folderId]   // Int64?

                let contentsId = row[contentId].components(separatedBy: ",")

                for cid in contentsId {
                    guard let idInt = Int(cid),
                          let book = LibraryDataManager.shared.getBook([row[bkId]]).first
                    else { continue }

                    let item = SavedResultsItem(
                        archive: String(row[archive]),
                        tableName: String(row[bkId]),
                        query: queryName,
                        bookId: idInt,
                        bookTitle: book.book
                    )

                    if groupedResults[savedName] == nil {
                        groupedResults[savedName] = (id: resultId, parentId: parentId, items: [])
                    }

                    groupedResults[savedName]?.items.append(item)
                }
            }
        } catch {
            print("Fetch results error:", error)
        }

        return groupedResults.map {
            ResultNode(
                id: $0.value.id,
                parentId: $0.value.parentId, // ResultNode harus menerima Int64?
                name: $0.key,
                items: $0.value.items
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

}


extension ResultsHandler {
    func updateFolderName(id folderId: Int64, newName: String) throws {
        let row = foldersTbl.filter(id == folderId)
        try db.run(row.update(name <- newName))
    }

    func updateResultQueryName(folderId: Int64?, oldName: String, newName: String) throws {
        // Filter: Hanya baris dengan folderId DAN query lama yang cocok
        let rowsToUpdate = results.filter(self.folderId == folderId && self.name == oldName)
        // Perbarui kolom 'query' di baris yang terfilter
        try db.run(rowsToUpdate.update(self.name <- newName))
    }

    func updateResultsFolder(oldFolderId: Int64, newFolderId: Int64) {
        do {
            let query = results.filter(folderId == oldFolderId)
            try db.run(query.update(folderId <- newFolderId))
        } catch {
            print("Update results folder error:", error)
        }
    }

    func getAllDescendantIds(of folderId: Int64) -> [Int64] {
        var ids: [Int64] = [folderId]

        do {
            let children = foldersTbl.filter(parent == folderId)
            for row in try db.prepare(children) {
                let childId = row[id]
                ids.append(contentsOf: getAllDescendantIds(of: childId))
            }
        } catch {
            print("Get descendants error:", error)
        }

        return ids
    }
}
