//
//  TagFilterSelectionView.swift
//  Maktabah
//

import SwiftUI

struct TagFilterSelectionView: View {
    let allTags: [String]
    let isAndMode: Bool
    let availableTagsProvider: ((Set<String>) -> [String])?
    @State private var selectedTags: Set<String>
    @State private var searchText = ""

    let onToggle: (String) -> Void
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void

    init(
        allTags: [String],
        selectedTags: Set<String>,
        isAndMode: Bool = false,
        availableTagsProvider: ((Set<String>) -> [String])? = nil,
        onToggle: @escaping (String) -> Void,
        onSelectAll: @escaping () -> Void,
        onDeselectAll: @escaping () -> Void
    ) {
        self.allTags = allTags
        self.isAndMode = isAndMode
        self.availableTagsProvider = availableTagsProvider
        self._selectedTags = State(initialValue: selectedTags)
        self.onToggle = onToggle
        self.onSelectAll = onSelectAll
        self.onDeselectAll = onDeselectAll
    }

    private var baseTags: [String] {
        if isAndMode, let provider = availableTagsProvider {
            return provider(selectedTags)
        }
        return allTags
    }

    private var filteredTags: [String] {
        guard !searchText.isEmpty else { return baseTags }
        let normalized = searchText.lowercased()
        return baseTags.filter { $0.lowercased().contains(normalized) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Tag list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredTags.enumerated()), id: \.element) { index, tag in
                        Button {
                            if selectedTags.contains(tag) {
                                selectedTags.remove(tag)
                            } else {
                                selectedTags.insert(tag)
                            }
                            onToggle(tag)
                        } label: {
                            HStack {
                                Text(tag)
                                    .lineLimit(1)
                                    .padding(.leading, 14)
                                Spacer()
                                if selectedTags.contains(tag) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .fontWeight(.semibold)
                                        .padding(.trailing, 8)
                                }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < filteredTags.count - 1 {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)

            Divider()

            // Select All / Deselect All
            HStack {
                Button("Select All") {
                    selectedTags = Set(baseTags)
                    onSelectAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)

                Spacer()

                Button("Deselect All") {
                    selectedTags = []
                    onDeselectAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .environment(\.layoutDirection, .rightToLeft)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
    }
}
