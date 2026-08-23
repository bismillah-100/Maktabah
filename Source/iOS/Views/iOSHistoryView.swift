//
//  iOSHistoryView.swift
//  Maktabah-iOS
//

import SwiftUI

struct iOSHistoryView: View {
    @StateObject private var viewModel = HistoryViewModel.shared
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager
    @ObservedObject private var donationManager = DonationManager.shared

    var body: some View {
        let filteredFavorites = viewModel.filteredFavorites
        let filteredHistory = viewModel.filteredHistory

        ThemeList {
            if !filteredHistory.isEmpty {
                HistorySection(books: filteredHistory, viewModel: viewModel)
            }

            if donationManager.shouldShowDonation {
                donationCard(topPad: 26, btmPad: 4)
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

            #if DEBUG
            donationCard(topPad: 12, btmPad: 24)
            #else
            if filteredHistory.count > 10,
               filteredFavorites.count > 5,
               !donationManager.shouldShowDonation
            {
                donationCard(topPad: 12, btmPad: 24)
            }
            #endif
        }
        .refreshable {
            CloudKitSyncManager.shared.fetchChanges()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        .withActiveIntegrationStates()
        .navigationTitle("History & Favorites")
    }

    private func donationCard(
        topPad: CGFloat,
        btmPad: CGFloat
    ) -> some View {
        Section {
            DonationHistoryButton {
                donationManager.showDonationSheet = true
            }
        }
        .listRowInsets(.init(
            top: topPad, leading: 16, bottom: btmPad, trailing: 16
        ))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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
