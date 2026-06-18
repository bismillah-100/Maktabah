//
//  TOCNodeRow.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/05/26.
//

import SwiftUI

struct TOCNodeRow: View {
    let item: TOCNode
    let selectedId: Int?
    let onSelect: (Int) -> Void
    @Binding var expandedPaths: Set<ObjectIdentifier>

    var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedPaths.contains(ObjectIdentifier(item)) },
            set: { isExpanding in
                if isExpanding {
                    expandedPaths.insert(ObjectIdentifier(item))
                } else {
                    expandedPaths.remove(ObjectIdentifier(item))
                }
            }
        )
    }

    var body: some View {
        Group {
            // Baris item saat ini
            HStack {
                // Teks bab di sebelah kanan (leading = kanan di RTL)
                nodeLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Custom panah di sebelah kiri teks jika memiliki sub-bab
                if !item.children.isEmpty {
                    Button(action: {
                        withAnimation {
                            if isExpanded.wrappedValue {
                                expandedPaths.remove(ObjectIdentifier(item))
                            } else {
                                expandedPaths.insert(ObjectIdentifier(item))
                            }
                        }
                    }) {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.left")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, weight: .semibold))
                            // Berikan frame statis pada gambar agar ukurannya konsisten
                            .frame(width: 16, height: 16, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    // Berikan frame statis pada area klik tombol
                    .frame(width: 32, height: 32)
                } else {
                    // Placeholder agar sejajar dengan yang memiliki panah (lebar sama dengan tombol = 32)
                    Spacer().frame(width: 32)
                }
            }
            // Berikan indentasi di sebelah kanan berdasarkan level (RTL: leading = kanan)
            .padding(.leading, CGFloat(max(0, item.level - 1)) * 24)
            .id(ObjectIdentifier(item))
            .environment(\.layoutDirection, .rightToLeft)
            
            // Rekursif untuk menampilkan sub-bab di bawahnya jika sedang diekspansi
            if isExpanded.wrappedValue, !item.children.isEmpty {
                ForEach(item.children) { child in
                    TOCNodeRow(
                        item: child,
                        selectedId: selectedId,
                        onSelect: onSelect,
                        expandedPaths: $expandedPaths
                    )
                }
            }
        }
    }

    var nodeLabel: some View {
        Button(action: {
            onSelect(item.id)
        }) {
            Text(item.bab)
                .font(ReaderViewModel.kfgqpcTitle)
                .foregroundColor(
                    item.id == selectedId ? .accentColor : .primary
                )
        }
    }
}

#Preview {
    let mockNode = TOCNode(from: TOC(bab: "Chapter 1", level: 1, sub: 0, id: 1))
    
    return TOCNodeRow(
        item: mockNode,
        selectedId: 1,
        onSelect: { _ in },
        expandedPaths: .constant(Set([ObjectIdentifier(mockNode)]))
    )
    .padding()
}
