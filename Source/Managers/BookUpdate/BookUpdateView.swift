//
//  BookUpdateView.swift
//  Maktabah
//
//  Created by MacBook on 06/02/26.
//

import Foundation
import SwiftUI

struct UpdateView: View {
    @StateObject var viewModel = BookUpdateViewModel()
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var filteredUpdates: [BookUpdateItem] {
        if searchText.isEmpty {
            return viewModel.availableUpdates
        }
        return viewModel.availableUpdates.filter {
            $0.bookName.localizedCaseInsensitiveContains(searchText)
                || "\($0.id)".contains(searchText)
        }
    }

    var body: some View {
        #if os(macOS)
        macOSLayout
            .frame(minWidth: 500, minHeight: 500)
            .toolbar {
                toolbarContent
            }
            .onAppear {
                viewModel.loadAvailableUpdates()
            }
        #else
        NavigationStack {
            iOSLayout
                .navigationTitle("Books Updates")
                .navigationBarTitleDisplayMode(.automatic)
                .searchable(text: $searchText, prompt: "Search books...")
                .toolbar {
                    toolbarContent
                }
                .themeBackground()
                .onAppear {
                    viewModel.loadAvailableUpdates()
                }
        }
        .interactiveDismissDisabled(viewModel.isUpdating)
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button("Close".localized) {
                dismiss()
            }
            .disabled(viewModel.isUpdating)
        }
        #endif

        if viewModel.hasUpdates {
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarTrailing) {
                toolbarActionButtons
            }
            #else
            ToolbarItemGroup(placement: .automatic) {
                toolbarActionButtons
            }
            #endif
        }
    }

    @ViewBuilder
    private var toolbarActionButtons: some View {
        let clearSelection = "Clear Selections".localized
        let updateOnly = "Update Only".localized
        let selectAll = "Select All".localized
        Button {
            viewModel.deselectAll()
        } label: {
            Image(systemName: "slash.circle")
        }
        .accessibilityLabel(clearSelection)
        .help(clearSelection)
        .disabled(viewModel.isUpdating || viewModel.selectedCount == 0)

        Button {
            viewModel.selectOnlyUpdates()
        } label: {
            Image(systemName: "arrow.up.circle")
        }
        .help(updateOnly)
        .accessibilityLabel(updateOnly)
        .disabled(viewModel.isUpdating || viewModel.needsUpdateCount == 0)

        Button {
            viewModel.selectAll()
        } label: {
            Image(systemName: "checkmark.circle.fill")
        }
        .help(selectAll)
        .accessibilityLabel(selectAll)
        .disabled(viewModel.isUpdating || viewModel.needsUpdateCount == 0)
    }

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        NavigationStack {
            contentView
                .searchable(text: $searchText, prompt: "Search books...")
                .safeAreaInset(edge: .top, spacing: 0) {
                    macOSHeaderView
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        Divider()
                        macOSFooterView
                            .background(.bar)
                    }
                }
        }
    }

    @ViewBuilder
    private var macOSHeaderView: some View {
        if !viewModel.isLoadingList,
           !viewModel.progressMessage.isEmpty ||
            viewModel.isUpdating
        {
            progressStatusView
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }

    private var macOSFooterView: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                NSApp.stopModal()
                NSApp.keyWindow?.close()
            } label: {
                Text("Close")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .clipShape(.capsule)
            .disabled(viewModel.isUpdating)

            Spacer()

            if viewModel.hasUpdates {
                updateBookButton
            }
        }
        .padding()
    }
    #endif

    // MARK: - iOS Layout

    #if !os(macOS)
    private var iOSLayout: some View {
        contentView
            .toolbar {
                if viewModel.hasUpdates {
                    ToolbarItem(placement: .bottomBar) {
                        iOSFooterView
                    }
                }
            }
    }
    #endif

    // MARK: - Shared Views

    private var iOSFooterView: some View {
        VStack(spacing: 8) {
            bookUpdateInfo
            updateBookButton
        }
        .padding()
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var updateBookButton: some View {
        let buttonTitle = "Update selected (\(viewModel.selectedCount))".localized
        Button {
            viewModel.performSelectedUpdates()
        } label: {
            Text(
                verbatim: "\(buttonTitle) - \(viewModel.totalSelectedSizeFormatted)"
            )
            #if os(iOS)
            .frame(maxWidth: .infinity)
            #else
            .padding(.horizontal, 6)
            #endif
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .clipShape(.capsule)
        .disabled(viewModel.isUpdating || viewModel.selectedCount == 0)
    }

    @ViewBuilder
    private var bookUpdateInfo: some View {
        if viewModel.needsUpdateCount > 0 {
            statusBadge(
                text: "\(viewModel.needsUpdateCount) books needs updates",
                color: .orange
            )
        }
    }

    private var progressStatusView: some View {
        HStack(alignment: .center, spacing: 8) {
            if viewModel.isUpdating {
                ProgressView()
                    .controlSize(.small)
            }

            Text(viewModel.progressMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoadingList {
            loadingView
        } else if viewModel.availableUpdates.isEmpty {
            emptyStateView
        } else {
            bookListView
                .disabled(viewModel.isUpdating)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading update lists...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("All books are up to date")
                .font(.headline)

            Button("Check Again") {
                viewModel.loadAvailableUpdates()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var bookListView: some View {
        #if os(iOS)
        ThemeList(filteredUpdates, isGrouped: true) { item in
            BookUpdateRow(item: item, fontSize: 17) {
                viewModel.toggleSelection(for: item)
            }
        }
        #else
        List(filteredUpdates, rowContent: { item in
            BookUpdateRow(item: item, fontSize: 15) {
                viewModel.toggleSelection(for: item)
            }
        })
        #endif
    }
}

// MARK: - Book Update Row

struct BookUpdateRow: View {
    @ObservedObject var item: BookUpdateItem
    let fontSize: Double
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.bookName)
                    .font(.custom(ArabicFont.kfgqpcUthmanTahaNaskh.rawValue, size: fontSize))
                    .multilineTextAlignment(.leading)

                // Book info
                HStack(spacing: 8) {
                    statusBadge(
                        text: item.categoryName,
                        color: .blue
                    )

                    statusBadge(
                        text: item.fileSizeFormatted,
                        color: item.status == .upToDate ? .green : .orange
                    )

                    statusView
                }
            }

            Spacer()

            // Checkbox / Up to Date Icon
            if item.needsUpdate {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isSelected ? Color.accentColor : Color.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
        }
        .opacity(item.needsUpdate ? 1.0 : 0.7)
        .contentShape(Rectangle())
        .onTapGesture {
            guard item.needsUpdate else { return }
            if let onToggle {
                onToggle()
            } else {
                item.isSelected.toggle()
            }
        }
        .lineLimit(1)
        .environment(\.layoutDirection, .rightToLeft)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .pending, .skipped:
            EmptyView()

        case .checking, .downloading, .processing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(item.status.displayText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .downloaded:
            statusBadge(text: item.status.displayText, color: .blue)

        case .new:
            statusBadge(text: item.status.displayText, color: .orange)

        case .needsUpdate:
            statusBadge(text: item.status.displayText, color: .orange)

        case .upToDate:
            statusBadge(text: item.status.displayText, color: .green)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

        case .failed(let msg):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
}

private extension View {
    func statusBadge(text: String, color: Color = .blue) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Preview

#Preview {
    UpdateView()
}
