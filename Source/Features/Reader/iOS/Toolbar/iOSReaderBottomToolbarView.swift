//
//  iOSReaderBottomToolbarView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/05/26.
//

import SwiftUI

struct iOSReaderBottomToolbarView: View {
    @Bindable var viewModel: ReaderViewModel
    var textViewState = TextViewState.shared
    @State private var showingNavigation = false
    @State private var showingTOC = false
    @State private var showingAnnotationsList = false

    @Environment(\.layoutDirection) private var layoutDirection

    var isDarkMode: Bool {
        textViewState.isDarkMode
    }

    var body: some View {
        Button(
            viewModel.statusSubtitle,
            action: {
                showingNavigation.toggle()
            }
        )
        .popover(isPresented: $showingNavigation) {
            iOSReaderNavigationPopoverView(viewModel: viewModel)
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: showingNavigation) { _, newValue in
            viewModel.isShowingNavigationPopover = newValue
        }

        Spacer()

        Group {
            if layoutDirection == .rightToLeft {
                prevButton
                nextButton
            } else {
                nextButton
                prevButton
            }
        }

        Spacer()

        Button(action: {
            showingAnnotationsList = true
        }) {
            Image(systemName: "quote.closing")
        }
        .accessibilityLabel(String(localized: "Annotations"))
        .help(String(localized: "Annotations"))
        .sheet(isPresented: $showingAnnotationsList) {
            if let book = viewModel.currentBook {
                iOSBookAnnotationsView(
                    bookId: book.id,
                    viewModel: viewModel.bookAnnotationsViewModel,
                    onSelect: { ann in
                        viewModel.didSelectAnnotation(ann)
                        showingAnnotationsList = false
                    },
                    onUpdate: { updated in
                        try viewModel.updateAnnotation(updated)
                    },
                    onDelete: { ann in
                        if let id = ann.id {
                            try viewModel.deleteAnnotation(id: id)
                        }
                    }
                )
            }
        }

        Button(action: {
            showingTOC = true
        }) {
            Image(systemName: "list.bullet")
        }
        .accessibilityLabel(String(localized: "Table of Contents"))
        .help(String(localized: "Table of Contents"))
        .sheet(isPresented: $showingTOC) {
            iOSTOCView(
                tocViewModel: viewModel.tocViewModel,
                selectedId: viewModel.tocViewModel.findNode(
                    forContentId: viewModel.currentContentId
                )?.id,
                onSelect: { id, title in
                    viewModel.didSelectTOCNode(id: id, title: title)
                    showingTOC = false
                }
            )
        }
    }

    private var nextButton: some View {
        Button(action: { viewModel.goToNextPage() }) {
            Image(systemName: "chevron.left")
        }
        .accessibilityLabel(String(localized: "Next Page"))
        .help(String(localized: "Next Page"))
        .keyboardShortcut(.leftArrow, modifiers: [])
    }

    private var prevButton: some View {
        Button(action: { viewModel.goToPrevPage() }) {
            Image(systemName: "chevron.right")
        }
        .accessibilityLabel(String(localized: "Previous Page"))
        .help(String(localized: "Previous Page"))
        .keyboardShortcut(.rightArrow, modifiers: [])
    }
}

#Preview {
    let mockBook = BooksData(
        id: 1,
        book: "Sahih al-Bukhari",
        archive: 0,
        muallif: 1
    )
    let mockViewModel = ReaderViewModel(book: mockBook)
    return iOSReaderBottomToolbarView(viewModel: mockViewModel)
}
