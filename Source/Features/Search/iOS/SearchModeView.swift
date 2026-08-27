import SwiftUI

struct SearchModeView: View {
    @Environment(iOSNavigationManager.self) var navigationManager: iOSNavigationManager
    @Environment(\.isSearching) var isSearching
    @State private var showingSaveResults = false
    @State private var showingSavedResults = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var kitabFilter: String = ""
    @State private var sortKey: SearchSortKey = .bookTitle
    @State private var sortAscending: Bool = true
    @State private var ftsManager = FtsMigrationManager.shared
    @State private var showFtsMigrationOverlay = false
    @AppStorage("hideFtsMigrationBanner") private var hideFtsMigrationBanner = false

    var body: some View {
        @Bindable var viewModel = navigationManager.searchViewModel
        filterAndInputView(viewModel: viewModel)
            .overlay {
                if !viewModel.results.isEmpty {
                    searchResultsView(viewModel: viewModel)
                        .transition(.move(edge: .bottom))
                }
            }
            .safeAreaInset(edge: .bottom, content: {
                SearchProgressView(
                    viewModel: viewModel,
                    showTablesProgress: true
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            })
            .navigationBarTitleDisplayMode(viewModel.results.isEmpty ? .automatic : .inline)
            .toolbar {
                SearchToolbar(
                    viewModel: viewModel,
                    onLeadingAction: {
                        viewModel.clearResults()
                        viewModel.query = ""
                    },
                    showSortMenu: true,
                    showSaveMenu: true,
                    sortKey: sortKey,
                    sortAscending: sortAscending,
                    onSortChange: { key, ascending in
                        sortKey = key
                        sortAscending = ascending
                    },
                    onSaveResults: { showingSaveResults = true },
                    onSavedResults: { showingSavedResults = true }
                )
            }
            .sheet(isPresented: $showingSaveResults) {
                iOSResultWriterView(
                    results: viewModel.results,
                    query: viewModel.query,
                    searchMode: viewModel.searchMode,
                    searchViewModel: viewModel
                )
            }
            .sheet(isPresented: $showingSavedResults) {
                iOSSavedResultsView()
            }
            .animation(.easeInOut(duration: 0.5), value: viewModel.results.isEmpty)
            .animation(.interpolatingSpring(stiffness: 300, damping: 20),
                       value: viewModel.isSearching)
            .onAppear {
                ftsManager.checkNeedsMigration()
            }
            .overlay {
                if showFtsMigrationOverlay {
                    Color.appBackground
                        .ignoresSafeArea()
                        .onTapGesture {
                            // blocking tap, do nothing or dismiss if not migrating?
                            // let's do nothing to force user to use Cancel button
                        }
                        .zIndex(10)

                    FtsMigrationProgressView(
                        onCancel: {
                            showFtsMigrationOverlay = false
                        },
                        onUpdate: {
                            try await ftsManager.performMigration()
                            await MainActor.run { showFtsMigrationOverlay = false }
                        }
                    )
                    .zIndex(11)
                    .transition(AnyTransition.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut, value: showFtsMigrationOverlay)
    }

    // MARK: - Sub-views

    private func filterAndInputView(viewModel: SearchViewModel) -> some View {
        ZStack(alignment: .bottom) {
            SearchFilterUIKitView(
                viewModel: viewModel,
                displayedCategories: viewModel.displayedCategories,
                updateTrigger: viewModel.updateTrigger,
                onTap: { isSearchFieldFocused = false }
            )
            .themeTint()
            .ignoresSafeArea(edges: .vertical)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ftsMigrationBanner()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isSearching {
                    SearchInputBar(
                        viewModel: viewModel,
                        isFocused: _isSearchFieldFocused,
                        onSubmit: {
                            Task {
                                viewModel.addToHistory(viewModel.query)
                                await viewModel.startSearch()
                                isSearchFieldFocused = false
                            }
                        }
                    )
                }
            }
            .overlay(alignment: .bottom) {
                if !isSearching {
                    SearchHistoryOverlay(
                        viewModel: viewModel,
                        inputBarHeight: 75,
                        isVisible: .init(
                            get: { isSearchFieldFocused },
                            set: { isSearchFieldFocused = $0 ?? false }
                        )
                    )
                    .hideTabBarWhenKeyboardShown()
                    .zIndex(2)
                }
            }
        }
    }

    private func searchResultsView(viewModel: SearchViewModel) -> some View {
        var filtered: [SearchResultItem] = kitabFilter.isEmpty
            ? viewModel.results
            : viewModel.results.filter {
                $0.bookTitle
                    .normalizeArabic(false)
                    .contains(
                        kitabFilter.normalizeArabic(false)
                )
            }

        SearchResultsSorter.sort(&filtered, by: sortKey, ascending: sortAscending)

        return SearchResultsListView(results: filtered) { item in
            handleSelection(item)
        }
        .searchable(
            text: $kitabFilter,
            placement: .toolbar,
            prompt: .filterByBooks
        )
        .onChange(of: viewModel.results) { _, _ in
            kitabFilter = ""
        }
    }

    private func handleSelection(_ item: SearchResultItem) {
        Task {
            let table = item.tableName.hasPrefix("b") ? String(item.tableName.dropFirst()) : item.tableName
            if let tableInt = Int(table), let bookData = LibraryDataManager.shared.getBook([tableInt]).first {
                let shouldRecord = UserDefaults.standard.recordSearchHistory
                await MainActor.run {
                    navigationManager.openBook(
                        bookData,
                        initialContentId: item.bookId,
                        searchText: navigationManager.searchViewModel.query,
                        searchMode: navigationManager.searchViewModel.searchMode,
                        nearDistance: navigationManager.searchViewModel.nearDistance,
                        recordHistory: shouldRecord
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func ftsMigrationBanner() -> some View {
        if ftsManager.needsMigration && !hideFtsMigrationBanner && !ftsManager.isMigrating {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                    Text(.ftsMigrationAvailable)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                }

                VStack(spacing: 10) {
                    Button {
                        showFtsMigrationOverlay = true
                    } label: {
                        Text(.ftsMigrationUpdateNowCountBtn(
                            ftsManager.totalArchivesToMigrate
                        ))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(uiColor: .tintColor))

                    Button {
                        hideFtsMigrationBanner = true
                        ReusableFunc.showAlert(
                            title: String(localized: .ftsMigrationAlertTitle),
                            message: String(localized: .ftsMigrationAlertMessage)
                        )
                    } label: {
                        Text(.ftsMigrationHideBannerBtn)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color.appBackground)
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .shadow(radius: 2)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut, value: ftsManager.isMigrating)
            .animation(.easeInOut, value: ftsManager.needsMigration)
        }
    }
}

// MARK: - Previews

struct SearchModeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SearchModeView()
                .environment(iOSNavigationManager())
                .previewDisplayName("Search")
            NavigationStack {
                let vm = SearchViewModel()
                SearchFilterUIKitView(
                    viewModel: vm,
                    displayedCategories: vm.displayedCategories,
                    updateTrigger: vm.updateTrigger
                )
                .navigationTitle("Filter Search")
                .navigationBarTitleDisplayMode(.inline)
            }
            .previewDisplayName("Search Filter")
        }
    }
}
