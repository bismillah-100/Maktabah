//
//  iOSBookSearchView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/05/26.
//

import SwiftUI

struct iOSBookSearchView: View {
    let book: BooksData
    let onSelect: (Int, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: SearchViewModel
    @State private var ftsManager = FtsMigrationManager.shared
    @State private var showFtsMigrationOverlay = false

    var body: some View {
        NavigationStack {
            ThemeVStack {
                // Results List
                SearchResultsListView(
                    results: viewModel.results,
                    showsBookTitle: false
                ) { item in
                    onSelect(item.bookId, viewModel.query)
                }
            }
            .navigationTitle(book.book)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SearchToolbar(
                    viewModel: viewModel,
                    onLeadingAction: {
                        dismiss()
                    },
                    conditionalLeadingButton: false
                )
            }
            .onAppear {
                viewModel.setSelectedBooks([book.id])
                ftsManager.checkNeedsMigration()
            }
            .safeAreaInset(edge: .top) {
                ftsMigrationBanner()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SearchProgressView(
                    viewModel: viewModel,
                    showIntegrationState: false
                )
            }
            .overlay(alignment: .bottom) {
                SearchHistoryOverlay(
                    viewModel: viewModel,
                    isVisible: .constant(nil)
                )
            }
        }
        .searchable(
            text: $viewModel.query,
            placement: .toolbar,
            prompt: .searchInThisBook
        )
        .onSubmit(of: .search, {
            Task { await viewModel.startSearch() }
        })
        .overlay {
            if showFtsMigrationOverlay {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .zIndex(10)
                FtsMigrationProgressView(
                    onCancel: {
                        showFtsMigrationOverlay = false
                    },
                    onUpdate: {
                        try await FtsMigrationManager.shared.migrateArchive(archiveId: book.archive)
                        await MainActor.run { showFtsMigrationOverlay = false }
                    }
                )
                .zIndex(11)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut, value: showFtsMigrationOverlay)
    }

    @ViewBuilder
    private func ftsMigrationBanner() -> some View {
        if ftsManager.needsMigration {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                    Text(.ftsMigrationAvailableBook)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                }

                if ftsManager.isMigrating {
                    ProgressView(value: ftsManager.progress)
                        .progressViewStyle(.linear)
                    Text(.ftsMigrationStatusBook(
                        ftsManager.completedBooksCount,
                        max(1, ftsManager.totalBooksToMigrate),
                        Int(ftsManager.progress * 100)
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Button {
                        showFtsMigrationOverlay = true
                    } label: {
                        Text(.ftsMigrationUpdateBtn)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top, 8)
            .shadow(radius: 2)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut, value: ftsManager.isMigrating)
            .animation(.easeInOut, value: ftsManager.needsMigration)
        }
    }
}

#Preview {
    let mockBook = BooksData(
        id: 1,
        book: "Sahih al-Bukhari",
        archive: 0,
        muallif: 1
    )
    let mockViewModel = SearchViewModel()
    return iOSBookSearchView(
        book: mockBook,
        onSelect: { _, _ in },
        viewModel: mockViewModel
    )
}
