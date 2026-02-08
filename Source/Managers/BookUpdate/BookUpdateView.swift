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
        VStack(spacing: 0) {
            // MARK: - Header
            headerView

            Spacer()
            Divider()

            // MARK: - Search & Filter
            if viewModel.hasUpdates {
                searchAndFilterView
                Divider()
            }

            // MARK: - Content
            if viewModel.isLoadingList {
                loadingView
            } else if viewModel.availableUpdates.isEmpty {
                emptyStateView
            } else {
                bookListView
            }

            Divider()

            // MARK: - Footer
            footerView
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            viewModel.loadAvailableUpdates()
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(alignment: .center, spacing: 0) {
            Text("Books Updates")
                .font(.headline)
                .fontWeight(.semibold)

            if !viewModel.progressMessage.isEmpty || viewModel.isUpdating {
                HStack(alignment: .center,spacing: 8) {
                    if viewModel.isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(viewModel.progressMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Search & Filter View

    private var searchAndFilterView: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search books...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(20)

            // Selection buttons
            HStack {
                Button("Select All") {
                    viewModel.selectAll()
                }
                .buttonStyle(.bordered)

                Button("Clear Selections") {
                    viewModel.deselectAll()
                }
                .buttonStyle(.bordered)

                Button("Update Only") {
                    viewModel.selectOnlyUpdates()
                }
                .buttonStyle(.bordered)

                Spacer()

                if viewModel.selectedCount > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(viewModel.selectedCount) book selected")
                            .font(.caption)
                        Text("\(viewModel.totalSelectedSizeFormatted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading update lists...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 50))
                .foregroundColor(.green)

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

    // MARK: - Book List View

    private var bookListView: some View {
        List {
            ForEach(filteredUpdates) { item in
                BookUpdateRow(item: item)
                    .disabled(viewModel.isUpdating)
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                NSApp.stopModal()
                NSApp.keyWindow?.close()
            } label: {
                Text("Close".localized)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(viewModel.isUpdating)

            Spacer()

            if viewModel.hasUpdates {
                if viewModel.needsUpdateCount > 0 {
                    Text("\(viewModel.needsUpdateCount) books needs updates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Update selected (\(viewModel.selectedCount))") {
                    viewModel.performSelectedUpdates()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isUpdating || viewModel.selectedCount == 0)
            }
        }
        .padding()
    }
}

// MARK: - Book Update Row

struct BookUpdateRow: View {
    @ObservedObject var item: BookUpdateItem

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Toggle("", isOn: $item.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()

            // Book info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.bookName)
                        .fontWeight(.medium)

                    if item.needsUpdate || item.newBook {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.orange)
                            .imageScale(.small)
                    }
                }

                HStack(spacing: 8) {
                    Text(item.categoryName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(3)

                    Text("ID: \(item.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let current = item.currentVersion {
                        Text("v\(current) → v\(item.newVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("v\(item.newVersion) " + "new".localized)
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Text(item.fileSizeFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status
            statusView.cornerRadius(24)
        }
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

        case .new:
            statusBadge(text: item.status.displayText, color: .blue)

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

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 6)) // Lebih modern dari .cornerRadius
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Preview

#Preview {
    UpdateView()
}
