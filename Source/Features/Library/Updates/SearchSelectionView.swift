//
//  SearchSelectionView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 04/09/26.
//

import SwiftUI

struct SearchSelectionItem: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
}

struct SearchSelectionView: View {
    let title: String
    let items: [SearchSelectionItem]
    let onSelect: (SearchSelectionItem) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""

    var filteredItems: [SearchSelectionItem] {
        if searchText.isEmpty {
            return items
        }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.gray.opacity(0.1))
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            List(filteredItems) { item in
                itemRow(for: item)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .frame(width: 400, height: 500)
        #else
        NavigationStack {
            ThemeList(filteredItems) { item in
                itemRow(for: item)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .scrollContentBackground(.hidden)
        .themeBackground()
        #endif
    }

    private func itemRow(for item: SearchSelectionItem) -> some View {
        Button(action: { onSelect(item) }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
