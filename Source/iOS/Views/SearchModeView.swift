import SwiftUI

struct SearchModeView: View {
    @Environment(iOSNavigationManager.self) var navigationManager: iOSNavigationManager
    @State private var showingFilter = false
    @State private var showingHelp = false
    @State private var showingSaveResults = false
    @State private var showingSavedResults = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var inputBarHeight: CGFloat = 60 // fallback default
    @State private var kitabFilter: String = ""

    var body: some View {
        @Bindable var viewModel = navigationManager.searchViewModel
        VStack(spacing: 0) {
            if viewModel.results.isEmpty {
                filterAndInputView(viewModel: viewModel)
            } else {
                searchResultsView(viewModel: viewModel)
            }
        }
        .safeAreaInset(edge: .bottom, content: {
            searchProgressView(viewModel: viewModel)
        })
        .toolbar {
            toolbarContent(viewModel: viewModel)
        }
        .sheet(isPresented: $showingSaveResults) {
            iOSResultWriterView(results: viewModel.results, query: viewModel.query)
        }
        .sheet(isPresented: $showingSavedResults) {
            iOSSavedResultsView()
        }
    }

    // MARK: - Sub-views

    private func filterAndInputView(viewModel: iOSSearchViewModel) -> some View {
        ZStack(alignment: .bottom) {
            SearchFilterUIKitView(
                viewModel: viewModel,
                displayedCategories: viewModel.displayedCategories,
                updateTrigger: viewModel.updateTrigger,
                onTap: {
                    isSearchFieldFocused = false
                }
            )
            .themeTint()
            .toolbarVisibility(isSearchFieldFocused ? .hidden : .visible, for: .tabBar)
            .ignoresSafeArea(edges: .vertical)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomInputBar(viewModel: viewModel)
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { inputBarHeight = geo.size.height }
                                .onChange(of: geo.size.height) { _, h in inputBarHeight = h }
                        }
                    }
            }

            searchHistoryOverlay(viewModel: viewModel)
        }
    }

    private func searchResultsView(viewModel: iOSSearchViewModel) -> some View {
        let filtered: [SearchResultItem] = kitabFilter.isEmpty
            ? viewModel.results
            : viewModel.results.filter {
                $0.bookTitle
                    .normalizeArabic(false)
                    .contains(
                        kitabFilter.normalizeArabic(false)
                )
            }

        return SearchResultsListView(results: filtered) { item in
            handleSelection(item)
        }
        .searchable(
            text: $kitabFilter,
            placement: .toolbar,
            prompt: Text(.filterByBooks)
        )
        .onChange(of: viewModel.results) { _, _ in
            kitabFilter = ""
        }
    }

    @ViewBuilder
    private func searchProgressView(viewModel: iOSSearchViewModel) -> some View {
        let integrationStates = navigationManager.activeIntegrationStates
        if viewModel.isSearching || !integrationStates.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isSearching {
                    VStack(alignment: .leading) {
                        ProgressView(
                            value: Double(viewModel.completedTables),
                            total: Double(max(viewModel.totalTables, 1))
                        )
                        .progressViewStyle(LinearProgressViewStyle())

                        if viewModel.totalRowsInTable > 0 {
                            ProgressView(
                                value: Double(viewModel.completedRowsInTable),
                                total: Double(viewModel.totalRowsInTable)
                            )
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }

                ActiveIntegrationStatesView()
            }
            .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: integrationStates.count)
        }
    }

    @ViewBuilder
    private func bottomInputBar(viewModel: iOSSearchViewModel) -> some View {
        @Bindable var viewModel = viewModel
        HStack(alignment: .center, spacing: 8) {
            // Search Bar
            TextField("Search...", text: $viewModel.query)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                .onSubmit {
                    viewModel.addToHistory(viewModel.query)
                    viewModel.startSearch()
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(.quinary)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.secondary, lineWidth: 1)
                )
                .cornerRadius(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))

            Picker("Mode", selection: $viewModel.searchMode) {
                Image(systemName: "text.quote").tag(SearchMode.phrase)
                Image(systemName: "checklist.checked").tag(SearchMode.contains)
                Image(systemName: "checklist").tag(SearchMode.or)
            }
            .frame(width: 120)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding(.vertical)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func searchHistoryOverlay(viewModel: iOSSearchViewModel) -> some View {
        if isSearchFieldFocused, !viewModel.searchHistory.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("Search History")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear All") {
                        viewModel.searchHistory.forEach { viewModel.removeFromHistory($0) }
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.appSecondaryBackground)

                ThemeList {
                    ForEach(viewModel.searchHistory, id: \.self) { historyQuery in
                        Button(action: {
                            viewModel.query = historyQuery
                            viewModel.addToHistory(historyQuery)
                            isSearchFieldFocused = false
                            viewModel.startSearch()
                        }) {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)
                                Text(historyQuery)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let item = viewModel.searchHistory[index]
                            viewModel.removeFromHistory(item)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .frame(maxHeight: 250)
            .background(Color.appBackground)
            .cornerRadius(12)
            .shadow(radius: 10)
            .padding(.horizontal)
            .padding(.bottom, inputBarHeight)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            .zIndex(2)
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(viewModel: iOSSearchViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if !viewModel.results.isEmpty {
                Button(action: {
                    viewModel.stopSearch()
                    viewModel.results = []
                    viewModel.query = ""
                }) {
                    Image(systemName: "xmark.circle")
                }
                .accessibilityLabel(String(localized: "Clear Results"))
                .help(String(localized: "Clear Results"))
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if viewModel.isSearching {
                Button(action: { viewModel.stopSearch() }) {
                    Image(systemName: "stop")
                        .foregroundColor(.red)
                }
                .accessibilityLabel(String(localized: "Stop Search"))
                .help(String(localized: "Stop Search"))
            } else {
                Button(action: { viewModel.startSearch() }) {
                    Image(systemName: "play")
                }
                .accessibilityLabel(String(localized: "Start Search"))
                .help(String(localized: "Start Search"))
            }
        }

        CustomToolbarSpacer(placement: .topBarTrailing)

        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button(action: { showingSavedResults = true }) {
                    Label("Saved Results", systemImage: "bookmark")
                }

                if !viewModel.results.isEmpty {
                    Button(action: { showingSaveResults = true }) {
                        Label("Save Results", systemImage: "pencil.line")
                    }
                }

                Button(action: { showingHelp = true }) {
                    Label("Help", systemImage: "questionmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel(String(localized: "Search Options"))
            .help(String(localized: "Search Options"))
            .popover(isPresented: $showingHelp) {
                SearchHelpView()
                    .frame(width: 300, height: 450)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func handleSelection(_ item: SearchResultItem) {
        Task {
            let table = item.tableName.hasPrefix("b") ? String(item.tableName.dropFirst()) : item.tableName
            if let tableInt = Int(table), let bookData = LibraryDataManager.shared.getBook([tableInt]).first {
                await MainActor.run {
                    navigationManager.openBook(
                        bookData,
                        initialContentId: item.bookId,
                        searchText: navigationManager.searchViewModel.query
                    )
                }
            }
        }
    }
}

// MARK: - Help View

struct SearchHelpView: View {
    var body: some View {
        ThemeScrollView {
            ThemeVStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("searchOptionsHelp", comment: ""))
                    .font(.headline)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("exactSearchTitle", comment: ""))
                        .font(.subheadline).bold()
                    Text(NSLocalizedString("exactSearchDesc", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("separateWordsSearchTitle", comment: ""))
                        .font(.subheadline).bold()
                    Text(NSLocalizedString("separateWordsSearchDesc", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "anyWordsSearchTitle"))
                        .font(.subheadline).bold()
                    Text(String(localized: "anyWordsSearchDesc"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
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
                let vm = iOSSearchViewModel()
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
