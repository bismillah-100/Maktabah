//
//  iPhoneLayout.swift
//  Maktabah-iOS
//
//  Created by Ghoys Mawahib on 03/05/26.
//

import SwiftUI

// MARK: - iPhone Layout

struct iPhoneLayout: View {
    @Bindable var bManager: iOSNavigationManager
    @Binding var selectedTab: iOSTab
    @Binding var showSettings: Bool
    @State private var showingAddFavorites = false
    @AppStorage("lastSelectedTab") private var savedSelectedTab: iOSTab = .viewer

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(iOSTab.viewer.title, systemImage: iOSTab.viewer.icon, value: .viewer) {
                viewerTabContent
            }

            Tab(iOSTab.search.title, systemImage: iOSTab.search.icon, value: .search, role: .search) {
                searchTabContent
            }

            Tab(iOSTab.author.title, systemImage: iOSTab.author.icon, value: .author) {
                authorTabContent
            }

            Tab(iOSTab.annotations.title, systemImage: iOSTab.annotations.icon, value: .annotations) {
                annotationsTabContent
            }

            Tab(iOSTab.history.title, systemImage: iOSTab.history.icon, value: .history) {
                historyTabContent
            }
        }
        .themeTint()
        .sheet(isPresented: $showingAddFavorites) {
            iOSAddFavoriteSheet(viewModel: HistoryViewModel.shared)
        }
        .onAppear {
            selectedTab = savedSelectedTab
        }
        .onChange(of: selectedTab) { _, newValue in
            savedSelectedTab = newValue
            bManager.switchToMode(newValue.appMode)
        }
    }

    // MARK: - Tab Contents

    @ViewBuilder
    private var viewerTabContent: some View {
        NavigationStack {
            iOSLibraryView()
                .navigationTitle(iOSTab.viewer.title)
                .adaptiveReaderPush(
                    item: $bManager.selectedBook,
                    manager: bManager
                )
                .toolbarGeneral(showSettings: $showSettings)
        }
        .searchable(
            text: Bindable(bManager.libraryViewModel).searchQuery,
            placement: .toolbar,
            prompt: String(localized: "Search Library")
        )
    }

    @ViewBuilder
    private var searchTabContent: some View {
        NavigationStack {
            SearchModeView()
                .navigationTitle(iOSTab.search.title)
                .adaptiveReaderPush(
                    item: $bManager.selectedBook,
                    manager: bManager
                )
                .toolbarGeneral(showSettings: $showSettings)
        }
        .searchable(
            text: Bindable(bManager.searchViewModel).filterText,
            placement: .toolbar,
            prompt: String(localized: "Filter Books to Search")
        )
    }

    @ViewBuilder
    private var authorTabContent: some View {
        NavigationStack {
            AuthorModeView()
                .navigationTitle(iOSTab.author.title)
                .adaptiveReaderPush(
                    item: $bManager.selectedBook,
                    manager: bManager
                )
                .toolbarGeneral(showSettings: $showSettings)
        }
        .searchable(
            text: Bindable(bManager.authorViewModel).searchText,
            placement: .toolbar,
            prompt: String(localized: "Search Narrators")
        )
    }

    @ViewBuilder
    private var annotationsTabContent: some View {
        NavigationStack {
            AnnotationListView()
                .navigationTitle(iOSTab.annotations.title)
                .adaptiveReaderPush(
                    item: $bManager.selectedBook,
                    manager: bManager
                )
                .toolbarGeneral(showSettings: $showSettings)
        }
        .searchable(
            text: Bindable(bManager.annotationViewModel).searchText,
            placement: .toolbar,
            prompt: String(localized: "Search Annotations")
        )
    }

    @ViewBuilder
    private var historyTabContent: some View {
        NavigationStack {
            iOSHistoryView()
                .navigationTitle(iOSTab.history.title)
                .adaptiveReaderPush(
                    item: $bManager.selectedBook,
                    manager: bManager
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel(String(localized: "Settings"))
                        .help(String(localized: "Settings"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showingAddFavorites = true }) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(String(localized: "Add Favorite"))
                        .help(String(localized: "Add Favorite"))
                    }
                }
        }
        .searchable(
            text: Binding(
                get: { HistoryViewModel.shared.searchText },
                set: { HistoryViewModel.shared.searchText = $0 }
            ),
            placement: .toolbar,
            prompt: String(localized: "Search History & Favorites")
        )
    }
}
