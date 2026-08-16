//
//  iOSTOCView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/05/26.
//

import SwiftUI

struct iOSTOCView: View {
    let tocViewModel: BookTOCViewModel
    let selectedId: Int?
    let onSelect: (Int) -> Void

    @State private var searchText = ""
    @State private var expandedPaths: Set<ObjectIdentifier> = []
    @Environment(\.dismiss) private var dismiss

    init(tocViewModel: BookTOCViewModel, selectedId: Int?, onSelect: @escaping (Int) -> Void) {
        self.tocViewModel = tocViewModel
        self.selectedId = selectedId
        self.onSelect = onSelect
    }

    var identifiableNodes: [TOCNode] {
        if searchText.isEmpty {
            return tocViewModel.tocNodes
        } else {
            let normalizedQuery = searchText.normalizeArabic(true)
            // perf: Use a single compactMap pass instead of chaining .map().filter().map()
            // to eliminate intermediate O(N) array allocations during real-time keystroke searches.
            return tocViewModel.tocRanges.compactMap { range in
                let node = range.node
                if node.bab.normalizeArabic(true).localizedStandardContains(normalizedQuery) {
                    return TOCNode(from: TOC(bab: node.bab, level: node.level, sub: node.sub, id: node.id))
                }
                return nil
            }
        }
    }

    func computeExpandedPaths() {
        guard let targetId = selectedId, let node = tocViewModel.findNodeById(targetId) else { return }
        if let path = tocViewModel.pathToNode(node) {
            expandedPaths = Set(path.map { ObjectIdentifier($0) })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ThemeList(isGrouped: true) {
                    ForEach(identifiableNodes) { item in
                        TOCNodeRow(
                            item: item,
                            selectedId: selectedId,
                            onSelect: onSelect,
                            expandedPaths: $expandedPaths
                        )
                    }
                }
                .searchable(text: $searchText, prompt: "Search Contents")
                .navigationTitle("Table of Contents")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    computeExpandedPaths()
                    if let selectedId = selectedId {
                        Task {
                            try await Task.sleep(for: .seconds(0.5))
                            withAnimation {
                                proxy.scrollTo(selectedId, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    let node1 = TOCNode(from: TOC(bab: "المقدمة (Tanpa Sub)", level: 1, sub: 0, id: 1))
    let node2 = TOCNode(from: TOC(bab: "كتاب الطهارة (Dengan Sub)", level: 1, sub: 0, id: 2))
    let node2_1 = TOCNode(from: TOC(bab: "باب الوضوء", level: 2, sub: 1, id: 3))
    let node2_2 = TOCNode(from: TOC(bab: "باب الغسل (Dengan Sub)", level: 2, sub: 1, id: 4))
    let node2_2_1 = TOCNode(from: TOC(bab: "فصل في موجبات الغسل", level: 3, sub: 2, id: 5))
    
    node2_2.children = [node2_2_1]
    node2.children = [node2_1, node2_2]
    
    let node3 = TOCNode(from: TOC(bab: "كتاب الصلاة", level: 1, sub: 0, id: 6))
    
    let mockNodes = [node1, node2, node3]
    
    let dummyVM = BookTOCViewModel(connFactory: { BookConnection() })
    dummyVM.tocNodes = mockNodes

    return iOSTOCView(
        tocViewModel: dummyVM,
        selectedId: 3,
        onSelect: { selectedId in
            print("Selected ID: \(selectedId)")
        }
    )
}
