//
//  iPadLayout.swift
//  Maktabah-iOS
//

import SwiftUI

struct iPadLayout: View {
    @Bindable var bManager: iOSNavigationManager
    @Binding var selectedTab: iOSTab
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var showSettings: Bool

    @State private var showingSearchHelp = false
    @State private var showingAddFavorites = false
    @State private var path: [iOSTab] = []

    var historyViewModel = HistoryViewModel.shared
    var donationManager = DonationManager.shared

    /// Sidebar search tetap lokal — dipakai hanya untuk filter sidebar (Favorites & History)
    @State private var sidebarSearchText: String = ""

    private func filterSidebarBooks(_ books: [BooksData]) -> [BooksData] {
        if sidebarSearchText.isEmpty || !path.isEmpty {
            return books
        }
        let normalized = sidebarSearchText.normalizeArabic(false)
        return books.filter {
            $0.book.normalizeArabic(false).contains(normalized)
        }
    }

    private var filteredFavorites: [BooksData] {
        filterSidebarBooks(historyViewModel.favoriteBooks)
    }

    private var filteredHistory: [BooksData] {
        filterSidebarBooks(historyViewModel.historyBooks)
    }

    private func searchPrompt(for tab: iOSTab) -> String {
        switch tab {
        case .viewer: String(localized: "Search Library")
        case .search: String(localized: "Filter Books to Search")
        case .author: String(localized: "Search Narrators")
        case .annotations: String(localized: "Search Annotations")
        case .history: String(localized: "Search History & Favorites")
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationStack(path: $path) {
                sidebarContent
                    .navigationTitle("Home")
                    .navigationBarTitleDisplayMode(.large)
                    .listStyle(.insetGrouped)
                    .searchable(
                        text: $sidebarSearchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search Favorites & History".localized
                    )
                    .toolbar {
                        HomeToolbarItems(
                            showSettings: $showSettings,
                            showingAddFavorites: $showingAddFavorites
                        )
                    }
                    .withActiveIntegrationStates()
                    .navigationDestination(for: iOSTab.self) { tab in
                        destinationView(for: tab)
                    }
            }
        } detail: {
            iOSReaderTabView()
        }
        .sheet(isPresented: $showingAddFavorites) {
            iOSAddFavoriteSheet(viewModel: historyViewModel)
        }
    }

    private var sidebarContent: some View {
        ThemeList(isGrouped: true) {
            Section {
                ForEach(iOSTab.allCases.filter { $0 != .history }) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .foregroundStyle(.primary)
                }
            }

            if !filteredHistory.isEmpty {
                HistorySection(books: filteredHistory, viewModel: historyViewModel)
            }

            if donationManager.shouldShowDonation {
                Section {
                    DonationHistoryButton {
                        donationManager.showDonationSheet = true
                    }
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if !filteredFavorites.isEmpty {
                FavoritesSection(
                    books: filteredFavorites,
                    viewModel: historyViewModel,
                    onOpen: { book in
                        let lastId = historyViewModel.entriesByBookId[book.id]?.lastContentId
                        bManager.openBook(book, initialContentId: lastId)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func destinationView(for tab: iOSTab) -> some View {
        Group {
            switch tab {
            case .viewer:
                libraryDestination
            case .search:
                searchDestination
            case .author:
                authorDestination
            case .annotations:
                annotationsDestination
            case .history:
                EmptyView()
            }
        }
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if selectedTab != tab {
                selectedTab = tab
                bManager.switchToMode(tab.appMode)
            }
        }
    }

    @ViewBuilder
    private var libraryDestination: some View {
        @Bindable var libraryVM = bManager.libraryViewModel
        iOSLibraryView()
            .searchable(
                text: $libraryVM.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: searchPrompt(for: .viewer).localized
            )
    }

    @ViewBuilder
    private var searchDestination: some View {
        @Bindable var searchVM = bManager.searchViewModel
        SearchModeView()
            .searchable(
                text: $searchVM.filterText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: searchPrompt(for: .search).localized
            )
    }

    @ViewBuilder
    private var authorDestination: some View {
        @Bindable var authorVM = bManager.authorViewModel
        AuthorModeView()
            .searchable(
                text: $authorVM.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: searchPrompt(for: .author).localized
            )
    }

    @ViewBuilder
    private var annotationsDestination: some View {
        @Bindable var annotationVM = bManager.annotationViewModel
        AnnotationListView()
            .searchable(
                text: $annotationVM.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: searchPrompt(for: .annotations).localized
            )
            .searchScopes($annotationVM.searchScope) {
                ForEach(AnnotationSearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
    }
}
