//
//  BookTOCViewModelTests.swift
//  MaktabahTests
//

import Foundation
@testable import Maktabah_Debug
import Testing

@MainActor
struct BookTOCViewModelTests {
    let viewModel: BookTOCViewModel

    init() {
        viewModel = BookTOCViewModel(connFactory: { BookConnection() })
    }

    @Test("Penentuan Bab Aktif (findNode): memilih sub-bab terdalam yang mencakup contentId")
    func testFindNode_selectsDeepestMatchingNode() async {
        // Buat struktur pohon TOC:
        // Root: Kitab Ath-Thaharah (lvl 1, sub 0, id: 10 .. 50)
        //   Child: Bab Al-Wudhu (lvl 2, sub 1, id: 20 .. 35)
        //     Child: Fashl Fardhu Wudhu (lvl 3, sub 2, id: 25 .. 30)

        let root = TOCNode(from: TOC(bab: "كتاب الطهارة", level: 1, sub: 0, id: 10))
        root.endID = 50

        let child = TOCNode(from: TOC(bab: "باب الوضوء", level: 2, sub: 1, id: 20))
        child.endID = 35

        let subChild = TOCNode(from: TOC(bab: "فصل في فروض الوضوء", level: 3, sub: 2, id: 25))
        subChild.endID = 30

        child.children = [subChild]
        root.children = [child]

        // Manual set tocRanges dan nodes di viewModel
        let allNodes = [root, child, subChild]
        let ranges = allNodes.map { TOCRange(start: $0.id, end: $0.endID, node: $0) }

        // Inject state ke viewModel untuk pengujian isolasi
        viewModel.setTOCData(nodes: [root], ranges: ranges)

        // 1. ContentId 15: Hanya dicakup oleh root (10..50)
        let node15 = viewModel.findNode(forContentId: 15)
        #expect(node15?.id == 10)
        #expect(node15?.level == 1)

        // 2. ContentId 22: Dicakup oleh root (10..50) dan child (20..35) -> Pilih child (range lebih sempit / level lebih tinggi)
        let node22 = viewModel.findNode(forContentId: 22)
        #expect(node22?.id == 20)
        #expect(node22?.level == 2)

        // 3. ContentId 27: Dicakup oleh ketiga node -> Pilih subChild (25..30)
        let node27 = viewModel.findNode(forContentId: 27)
        #expect(node27?.id == 25)
        #expect(node27?.level == 3)

        // 4. ContentId 99: Di luar jangkauan -> nil
        let node99 = viewModel.findNode(forContentId: 99)
        #expect(node99 == nil)
    }

    @Test("Penghitungan Path Hirarki (pathToNode)")
    func testPathToNode() {
        let root = TOCNode(from: TOC(bab: "كتاب الصلاة", level: 1, sub: 0, id: 100))
        let child = TOCNode(from: TOC(bab: "باب الأذان", level: 2, sub: 1, id: 105))
        root.children = [child]

        viewModel.tocNodes = [root]

        let path = viewModel.pathToNode(child)
        #expect(path?.count == 2)
        #expect(path?.first?.id == 100)
        #expect(path?.last?.id == 105)
    }
}
