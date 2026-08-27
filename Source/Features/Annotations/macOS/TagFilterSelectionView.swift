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
    @Environment(\.dismiss) private var dismiss

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
        _selectedTags = State(initialValue: selectedTags)
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
        #if os(macOS)
        macView
            .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
        #else
        iOSView
        #endif
    }

    #if os(iOS)
    private var iOSView: some View {
        NavigationStack {
            tagLists
                .searchable(text: $searchText, prompt: "Search...")
                .navigationTitle("Tag")
                .navigationBarTitleDisplayMode(.automatic)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        deselectAllButton
                        selectAllButton
                    }
                }
                .themeBackground()
                .themeTint()
        }
    }
    #endif

    #if os(macOS)
    private var macView: some View {
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
            tagLists
            Divider()
            bottomButton
        }
    }
    #endif

    private var tagLists: some View {
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
                        #if os(macOS)
                        .padding(.vertical, 6)
                        #else
                        .padding(.vertical, 10)
                        #endif
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < filteredTags.count - 1 {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            #if os(iOS)
            .padding(.horizontal)
            #endif
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    @ViewBuilder
    private var selectAllButton: some View {
        Button {
            selectedTags = Set(baseTags)
            onSelectAll()
        } label: {
            #if os(iOS)
            Image(systemName: "checkmark.circle")
            #else
            Text("Select All")
            #endif
        }
        .accessibilityLabel(String(localized: "Select All"))
        #if os(macOS)
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        #endif
    }

    @ViewBuilder
    private var deselectAllButton: some View {
        Button {
            selectedTags = []
            onDeselectAll()
        } label: {
            #if os(iOS)
            Image(systemName: "xmark.circle")
            #else
            Text("Deselect All")
            #endif
        }
        .accessibilityLabel(String(localized: "Deselect All"))
        #if os(macOS)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        #endif
    }

    private var bottomButton: some View {
        HStack {
            selectAllButton
            Spacer()
            deselectAllButton
        }
        .environment(\.layoutDirection, .rightToLeft)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
