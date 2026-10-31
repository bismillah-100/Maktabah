//
//  BookTOCViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//

import Foundation
import Observation
import OSLog
import SwiftUI

struct TOCRange {
    let start: Int
    let end: Int
    let node: TOCNode
}

@Observable @MainActor
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

    init(connFactory: @escaping @Sendable () -> BookConnection) {
        tocLoader = TOCLoaderRefCount(connFactory: connFactory)
    }

    func loadTOC(book: BooksData) {
        loadingTask?.cancel()
        loadingTask = Task { [weak self] in
            guard let self else { return }
            onTOCLoadingStateChanged?(true)

            let taskHandle = await tocLoader.acquire(book: book)
            defer {
                Task { [weak self] in
                    await self?.tocLoader.release(bookId: book.id)
                }
            }

            do {
                let tree = try await taskHandle.value
                guard !Task.isCancelled else {
                    onTOCLoadingStateChanged?(false)
                    return
                }

                // Kalkulasi berat diproses di BACKGROUND thread pool
                let (ranges, cache) = await Task.detached {
                    let allNodes = Self.flattenNodes(tree)
                    let ranges = Self.buildRanges(from: allNodes)
                    var cache: [Int: TOCNode] = [:]
                    for r in ranges {
                        cache[r.node.id] = r.node
                    }
                    return (ranges, cache)
                }.value

                guard !Task.isCancelled else {
                    onTOCLoadingStateChanged?(false)
                    return
                }

                // Update UI kembali di MainActor tanpa lag
                tocNodes = tree
                tocRanges = ranges
                nodeIdCache = cache
                onTOCLoaded?(tree)
                onTOCLoadingStateChanged?(false)
            } catch {
                onTOCLoadingStateChanged?(false)
                Logger.reader.error("Failed to load TOC: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private nonisolated static func flattenNodes(_ roots: [TOCNode]) -> [TOCNode] {
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

    private nonisolated static func buildRanges(from nodes: [TOCNode]) -> [TOCRange] {
        nodes.enumerated().map { i, node in
            let end = nodes[(i + 1)...].first(where: { $0.id > node.id }).map { $0.id - 1 } ?? .max
            return TOCRange(start: node.id, end: end, node: node)
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
    /// Menggunakan tocRanges lalu pathToNode untuk full path.
    func deepestPath(forContentId contentId: Int) -> [TOCNode]? {
        guard let deepest = findNode(forContentId: contentId) else {
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

    func setTOCData(nodes: [TOCNode], ranges: [TOCRange]? = nil) {
        tocNodes = nodes
        if let ranges {
            tocRanges = ranges
        } else {
            let allNodes = Self.flattenNodes(nodes)
            tocRanges = Self.buildRanges(from: allNodes)
        }
        var cache: [Int: TOCNode] = [:]
        for r in tocRanges {
            cache[r.node.id] = r.node
        }
        nodeIdCache = cache
    }

    func cleanUp() {
        loadingTask?.cancel()
        loadingTask = nil
        tocNodes.removeAll()
        tocRanges.removeAll()
        nodeIdCache.removeAll()
    }
}
