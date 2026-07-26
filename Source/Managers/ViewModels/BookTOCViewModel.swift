//
//  BookTOCViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//

import Foundation
#if canImport(UIKit)
import SwiftUI
#endif

struct TOCRange {
    let start: Int
    let end: Int
    let node: TOCNode
}

#if os(iOS)
@Observable
#endif
class BookTOCViewModel {
    private let tocLoader: TOCLoaderRefCount

    // State
    var tocNodes: [TOCNode] = []
    private(set) var tocRanges: [TOCRange] = []
    private var nodeIdCache: [Int: TOCNode] = [:]

    // Callbacks
    var onTOCLoadingStateChanged: ((Bool) -> Void)?
    var onTOCLoaded: (([TOCNode]) -> Void)?

    private var loadingTask: Task<Void, Never>?

    init(connFactory: @escaping () -> BookConnection) {
        tocLoader = TOCLoaderRefCount(connFactory: connFactory)
    }

    func loadTOC(book: BooksData) {
        loadingTask?.cancel()
        loadingTask = Task { [weak self] in
            guard let self else { return }

            await MainActor.run {
                self.onTOCLoadingStateChanged?(true)
            }

            let taskHandle = await tocLoader.acquire(book: book)
            defer {
                Task { [weak self] in
                    await self?.tocLoader.release(bookId: book.id)
                }
            }

            do {
                let tree = try await taskHandle.value
                if Task.isCancelled {
                    await MainActor.run {
                        self.onTOCLoadingStateChanged?(false)
                    }
                    return
                }

                let allNodes = flattenNodes(tree)
                if Task.isCancelled {
                    await MainActor.run {
                        self.onTOCLoadingStateChanged?(false)
                    }
                    return
                }

                computeEndIDs(for: allNodes)
                let ranges = buildRanges(from: allNodes)

                tocNodes = tree
                tocRanges = ranges
                nodeIdCache.removeAll()
                for r in ranges {
                    nodeIdCache[r.node.id] = r.node
                }

                await MainActor.run {
                    self.onTOCLoaded?(tree)
                    self.onTOCLoadingStateChanged?(false)
                }
            } catch {
                await MainActor.run {
                    self.onTOCLoadingStateChanged?(false)
                }
                print("Failed to load TOC: \(error)")
            }
        }
    }

    private func flattenNodes(_ roots: [TOCNode]) -> [TOCNode] {
        var result: [TOCNode] = []
        func traverse(_ node: TOCNode) {
            result.append(node)
            for child in node.children {
                traverse(child)
            }
        }
        for r in roots {
            traverse(r)
        }
        return result.sorted {
            if $0.id != $1.id {
                return $0.id < $1.id
            }
            return $0.level < $1.level
        }
    }

    private func computeEndIDs(for allNodes: [TOCNode]) {
        for (i, node) in allNodes.enumerated() {
            if let nextDiffNode = allNodes[(i + 1)...].first(where: { $0.id > node.id }) {
                node.endID = nextDiffNode.id - 1
            } else {
                node.endID = Int.max
            }
        }
    }

    private func buildRanges(from nodes: [TOCNode]) -> [TOCRange] {
        nodes.map { node in
            TOCRange(start: node.id, end: node.endID, node: node)
        }
    }

    // MARK: - Search / Find Path

    func findNode(forContentId contentId: Int) -> TOCNode? {
        let matches = tocRanges.filter { contentId >= $0.start && contentId <= $0.end }
        return matches.min(by: {
            let r0 = $0.end - $0.start
            let r1 = $1.end - $1.start
            if r0 != r1 {
                return r0 < r1
            }
            return $0.node.level > $1.node.level
        })?.node
    }

    func findNodeById(_ id: Int) -> TOCNode? {
        nodeIdCache[id]
    }

    /// Mencari path lengkap dari root ke node terdalam yang mencakup contentId.
    /// Menggunakan tocRanges (endID yang sudah benar) lalu pathToNode untuk full path.
    func deepestPath(forContentId contentId: Int) -> [TOCNode]? {
        let matches = tocRanges.filter { contentId >= $0.start && contentId <= $0.end }
        guard let deepest = matches.min(by: {
            let r0 = $0.end - $0.start
            let r1 = $1.end - $1.start
            if r0 != r1 {
                return r0 < r1
            }
            return $0.node.level > $1.node.level
        })?.node else {
            return nil
        }
        return pathToNode(deepest)
    }

    func pathToNode(_ target: TOCNode) -> [TOCNode]? {
        for root in tocNodes {
            if let p = findPath(root, target) { return p }
        }
        return nil
    }

    private func findPath(_ current: TOCNode, _ target: TOCNode) -> [TOCNode]? {
        if current === target { return [current] }
        for child in current.children {
            if let p = findPath(child, target) {
                return [current] + p
            }
        }
        return nil
    }

    func cleanUp() {
        loadingTask?.cancel()
        loadingTask = nil
        tocNodes.removeAll()
        tocRanges.removeAll()
        nodeIdCache.removeAll()
    }

    deinit {
        cleanUp()
    }
}
