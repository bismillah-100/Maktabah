import SwiftUI

struct iOSHistoryView: View {
    @StateObject private var viewModel = iOSHistoryViewModel.shared
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager

    var body: some View {
        let searchText = navigationManager.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSearchText = searchText.normalizeArabic(true)

        let filteredFavorites = viewModel.favoriteBooks.filter { book in
            searchText.isEmpty || book.book.normalizeArabic(true).localizedStandardContains(normalizedSearchText)
        }
        
        let filteredHistory = viewModel.historyBooks.filter { book in
            searchText.isEmpty || book.book.normalizeArabic(true).localizedStandardContains(normalizedSearchText)
        }

        List {
            if !filteredFavorites.isEmpty {
                Section(header: Text("Favorites")) {
                    ForEach(filteredFavorites, id: \.id) { book in
                        BookRowView(book: book, isFavorite: true, viewModel: viewModel) {
                            navigationManager.openBook(book, initialContentId: viewModel.lastContentId(for: book.id))
                        }
                    }
                    .onDelete(perform: removeFavorite)
                }
            }

            if !filteredHistory.isEmpty {
                Section(header: Text("History")) {
                    ForEach(filteredHistory, id: \.id) { book in
                        BookRowView(book: book, isFavorite: viewModel.favoriteBookIds.contains(book.id), viewModel: viewModel) {
                            navigationManager.openBook(book, initialContentId: viewModel.lastContentId(for: book.id))
                        }
                    }
                    .onDelete(perform: removeHistory)
                }
            } else if filteredFavorites.isEmpty {
                if !searchText.isEmpty {
                    Text("No results found for \"\(searchText)\"")
                        .foregroundColor(.secondary)
                } else {
                    Text("No recent history")
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !navigationManager.activeIntegrationStates.isEmpty {
                VStack(spacing: 0) {
                    ForEach(navigationManager.activeIntegrationStates) { state in
                        iOSBookDownloadProgressView(
                            state: state,
                            onConfirm: { navigationManager.confirmPendingBookIntegration(state: state) },
                            onCancel: { navigationManager.cancelPendingBookIntegration(state: state) }
                        )
                        .background(.ultraThinMaterial)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("History & Favorites")
        .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: navigationManager.activeIntegrationStates.count)
        .onAppear {
            viewModel.loadBooksData()
        }
    }

    private func removeFavorite(at offsets: IndexSet) {
        for index in offsets {
            let book = viewModel.favoriteBooks[index]
            viewModel.toggleFavorite(book.id)
        }
    }

    private func removeHistory(at offsets: IndexSet) {
        for index in offsets {
            let book = viewModel.historyBooks[index]
            viewModel.removeHistory(book.id)
        }
    }
}

struct BookRowView: View {
    let book: BooksData
    let isFavorite: Bool
    @ObservedObject var viewModel: iOSHistoryViewModel
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(book.book)
                    .font(iOSReaderViewModel.kfgqpc)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {
                    viewModel.toggleFavorite(book.id)
                }) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundColor(isFavorite ? .yellow : .gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .contentShape(Rectangle())
        }
    }
}

struct iOSAddFavoriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: iOSHistoryViewModel
    @State private var searchText = ""
    @State private var searchViewModel = iOSSearchViewModel()

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
                    searchViewModel.selectedBookIds = Set(viewModel.favoriteBookIds)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            viewModel.favoriteBookIds = Array(searchViewModel.selectedBookIds)
                            viewModel.saveToUserDefaults()
                            viewModel.loadBooksData()
                            dismiss()
                        }
                        .fontWeight(.bold)
                    }
                }
        }
    }
}
