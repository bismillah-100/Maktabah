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
    @Environment(\.presentationMode) var presentationMode

    @Bindable var viewModel: SearchViewModel

    var body: some View {
        NavigationView {
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
                        presentationMode.wrappedValue.dismiss()
                    },
                    conditionalLeadingButton: false
                )
            }
            .onAppear {
                viewModel.setSelectedBooks([book.id])
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
        .onSubmit(of: .search, viewModel.startSearch)
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
