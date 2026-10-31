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

    @Test("Penentuan Bab Aktif (findNode): memilih sub-bab terdalam yang mencakup contentId melalui buildRanges")
    func testFindNode_selectsDeepestMatchingNode() {
        // Buat struktur pohon TOC:
        // Root 1: Kitab Ath-Thaharah (lvl 1, sub 0, id: 10)
        //   Child 1: Bab Al-Miyah (lvl 2, sub 1, id: 10) -> id sama dengan parent!
        //   Child 2: Bab Al-Wudhu (lvl 2, sub 1, id: 20)
        //     SubChild: Fashl Fardhu Wudhu (lvl 3, sub 2, id: 25)
        //   Child 3: Bab Al-Mash (lvl 2, sub 1, id: 31)
        // Root 2: Kitab Ash-Shalah (lvl 1, sub 0, id: 51)

        let root1 = TOCNode(from: TOC(bab: "كتاب الطهارة", level: 1, sub: 0, id: 10))
        let childSameId = TOCNode(from: TOC(bab: "باب المياه", level: 2, sub: 1, id: 10))
        let child2 = TOCNode(from: TOC(bab: "باب الوضوء", level: 2, sub: 1, id: 20))
        let subChild = TOCNode(from: TOC(bab: "فصل في فروض الوضوء", level: 3, sub: 2, id: 25))
        let child3 = TOCNode(from: TOC(bab: "باب المسح", level: 2, sub: 1, id: 31))
        let root2 = TOCNode(from: TOC(bab: "كتاب الصلاة", level: 1, sub: 0, id: 51))

        child2.children = [subChild]
        root1.children = [childSameId, child2, child3]

        // Panggil setTOCData tanpa ranges manual agar flattenNodes + buildRanges diuji langsung
        viewModel.setTOCData(nodes: [root1, root2])

        // 1. ContentId 15: Dicakup oleh childSameId (10..19) -> level 2
        let node15 = viewModel.findNode(forContentId: 15)
        #expect(node15?.id == 10)
        #expect(node15?.level == 2)

        // 2. ContentId 22: Dicakup oleh child2 (20..24) -> level 2
        let node22 = viewModel.findNode(forContentId: 22)
        #expect(node22?.id == 20)
        #expect(node22?.level == 2)

        // 3. ContentId 27: Dicakup oleh subChild (25..30) -> level 3
        let node27 = viewModel.findNode(forContentId: 27)
        #expect(node27?.id == 25)
        #expect(node27?.level == 3)

        // 4. ContentId 5: Sebelum bab pertama -> nil
        let node5 = viewModel.findNode(forContentId: 5)
        #expect(node5 == nil)
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
