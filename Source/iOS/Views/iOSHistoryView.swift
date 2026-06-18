//
//  iOSHistoryView.swift
//  Maktabah-iOS
//

import SwiftUI

struct iOSHistoryView: View {
    @StateObject private var viewModel = HistoryViewModel.shared
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager

    var body: some View {
        let filteredFavorites = viewModel.filteredFavorites
        let filteredHistory = viewModel.filteredHistory

        ThemeList {
            if !filteredHistory.isEmpty {
                HistorySection(books: filteredHistory,viewModel: viewModel)
            }

            if !filteredFavorites.isEmpty {
                FavoritesSection(
                    books: filteredFavorites,
                    viewModel: viewModel,
                    onOpen: { book in
                        let lastId = viewModel.entriesByBookId[book.id]?.lastContentId
                        navigationManager.openBook(book, initialContentId: lastId)
                    }
                )
            } else if filteredFavorites.isEmpty {
                HistoryEmptyState(searchText: viewModel.searchText)
            }
        }
        .refreshable {
            CloudKitSyncManager.shared.fetchChanges()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        .withActiveIntegrationStates()
        .navigationTitle("History & Favorites")
    }
}

// MARK: - iOSAddFavoriteSheet

struct iOSAddFavoriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: HistoryViewModel
    @State private var searchText = ""
    @State private var searchViewModel = SearchViewModel()

    var body: some View {
        NavigationStack {
            SearchFilterUIKitView(
                viewModel: searchViewModel,
                displayedCategories: searchViewModel.displayedCategories,
                updateTrigger: searchViewModel.updateTrigger
            )
            .ignoresSafeArea(edges: [.vertical])
            .navigationTitle("Select Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search Books")
            .onChange(of: searchText) { _, newValue in
                searchViewModel.filterText = newValue
                searchViewModel.updateDisplayedCategories()
            }
            .onAppear {
                searchViewModel.setSelectedBooks(Set(viewModel.favoriteBookIds))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        let newFavs = searchViewModel.selectedBookIds
                        let currentFavs = Set(viewModel.favoriteBookIds)
                        for id in newFavs.subtracting(currentFavs) {
                            viewModel.toggleFavorite(id)
                        }
                        for id in currentFavs.subtracting(newFavs) {
                            viewModel.toggleFavorite(id)
                        }
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .themeTint()
    }
}
