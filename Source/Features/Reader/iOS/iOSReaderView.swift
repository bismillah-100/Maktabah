import SwiftUI

struct iOSReaderView: View {
    let book: BooksData
    let initialContentId: Int?
    var viewModel: ReaderViewModel
    var textViewState = TextViewState.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(iOSNavigationManager.self) var bManager

    var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    @State private var showingBookInfo = false
    @State private var showingOptions = false
    @State private var showingAnnotationActionSheet = false
    @State private var showingSearch = false
    @State private var tappedAnnotationId: Int64?

    init(book: BooksData,
         viewModel: ReaderViewModel? = nil,
         initialContentId: Int? = nil)
    {
        self.book = book
        self.initialContentId = initialContentId
        self.viewModel = viewModel ?? ReaderViewModel(book: book)
    }

    var backgroundColor: Color {
        textViewState.backgroundColor.color
    }

    var isDarkMode: Bool {
        textViewState.isDarkMode
    }

    var body: some View {
        _ReaderTextContentView(
            book: book,
            viewModel: viewModel,
            textViewState: textViewState,
            tappedAnnotationId: $tappedAnnotationId,
            showingAnnotationActionSheet: $showingAnnotationActionSheet
        )
        .equatable()
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .navigationTitle(book.book)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showingSearch = true
                }) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(String(localized: "Search"))
                .help(String(localized: "Search"))
            }

            if !isRegularLayout {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        bManager.showingTabsList.toggle()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                            Text("\(max(1, bManager.openTabs.count))")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "Opened Books"))
                    .help(String(localized: "Opened Books"))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: {
                        DispatchQueue.main.async {
                            showingOptions = true
                        }
                    }) {
                        Label("View Options", systemImage: "textformat")
                    }
                    .accessibilityLabel(String(localized: "Text Options"))
                    .help(String(localized: "Text Options"))

                    Button(action: {
                        showingBookInfo = true
                    }) {
                        Label(.Library.bookInfo, systemImage: "info.circle")
                    }
                    .accessibilityLabel(String(localized: .Library.bookInfo))
                    .help(String(localized: .Library.bookInfo))
                } label: {
                    Image(systemName: "ellipsis")
                }
                .popover(isPresented: $showingOptions) {
                    ViewOptionsView()
                        .frame(width: 300, height: 500)
                        .presentationCompactAdaptation(.popover)
                }
            }

            ToolbarItemGroup(placement: .bottomBar) {
                iOSReaderBottomToolbarView(viewModel: viewModel)
            }
        }
        .onChange(of: showingOptions) { _, newValue in
            viewModel.isShowingOptionsPopover = newValue
        }
        .onChange(of: initialContentId) { _, newValue in
            if viewModel.contentText.isEmpty {
                viewModel.loadInitialContent()
            }
        }
        .onAppear {
            viewModel.needsScrollRestore = true
        }
        .onDisappear {
            viewModel.saveCurrentState()
        }
        .sheet(isPresented: $showingSearch) {
            if let book = viewModel.currentBook {
                iOSBookSearchView(
                    book: book,
                    onSelect: { contentId, query in
                        viewModel.didSelectSearch(query: query, contentId: contentId)
                        showingSearch = false
                    },
                    viewModel: viewModel.searchViewModel
                )
            }
        }
        .sheet(isPresented: $showingBookInfo) {
            iOSBookInfoView(book: book)
        }
        .sheet(isPresented: Binding(
            get: { showingAnnotationActionSheet && tappedAnnotationId != nil },
            set: { if !$0 { showingAnnotationActionSheet = false; tappedAnnotationId = nil } }
        )) {
            if let id = tappedAnnotationId, let ann = viewModel.currentAnnotations.first(where: { $0.id == id }) {
                iOSAnnotationEditorSheet(
                    annotation: ann,
                    onSave: { updatedAnn in
                        do {
                            try viewModel.updateAnnotation(updatedAnn)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } catch {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    },
                    onDelete: { idToDelete in
                        do {
                            try viewModel.deleteAnnotation(id: idToDelete)
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        } catch {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }
}

// MARK: - Isolated Text Content View

/// Extracted to its own struct so that `@State` sheet toggles in `iOSReaderView`
/// don't invalidate the `UIViewRepresentable` body and trigger `updateUIView`.
private struct _ReaderTextContentView: View {
    let book: BooksData
    var viewModel: ReaderViewModel
    var textViewState: TextViewState
    @Binding var tappedAnnotationId: Int64?
    @Binding var showingAnnotationActionSheet: Bool

    var body: some View {
        @Bindable var viewModel = viewModel
        iOSIbarotTextView(
            text: $viewModel.contentText,
            annotations: viewModel.currentAnnotations,
            searchEvent: viewModel.searchEvent,
            annotationEvent: viewModel.annotationEvent,
            isMultiLanguage: book.isMultiLanguage,
            isImported: book.isImported,
            enhancedUnderline: textViewState.enhancedUnderline,
            viewModel: viewModel,
            onAddAnnotation: { range, mode, sourceText, color in
                do {
                    try viewModel.addAnnotation(in: range, mode: mode, sourceText: sourceText, color: color)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } catch {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            },
            onTapAnnotation: { annId in
                tappedAnnotationId = annId
                showingAnnotationActionSheet = true
            },
            onNavigateNext: { viewModel.goToNextPage() },
            onNavigatePrev: { viewModel.goToPrevPage() }
        )
        .background(textViewState.backgroundColor.color)
        .ignoresSafeArea(edges: .vertical)
        .legacyVisibleToolbarBackgrounds()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension _ReaderTextContentView: @MainActor Equatable {
    static func == (lhs: _ReaderTextContentView, rhs: _ReaderTextContentView) -> Bool {
        lhs.book.id == rhs.book.id &&
            lhs.viewModel === rhs.viewModel &&
            !rhs.viewModel.needsScrollRestore &&
            lhs.viewModel.currentContentId == rhs.viewModel.currentContentId &&
            lhs.viewModel.contentText == rhs.viewModel.contentText &&
            lhs.viewModel.currentAnnotations == rhs.viewModel.currentAnnotations &&
            lhs.viewModel.searchEvent == rhs.viewModel.searchEvent &&
            lhs.viewModel.annotationEvent == rhs.viewModel.annotationEvent &&
            lhs.textViewState.showHarakat == rhs.textViewState.showHarakat &&
            lhs.textViewState.enhancedUnderline == rhs.textViewState.enhancedUnderline &&
            lhs.textViewState.fontName == rhs.textViewState.fontName &&
            lhs.textViewState.fontSize == rhs.textViewState.fontSize &&
            lhs.textViewState.lineHeight == rhs.textViewState.lineHeight &&
            lhs.textViewState.backgroundColorIndex == rhs.textViewState.backgroundColorIndex
    }
}

private extension View {
    @ViewBuilder
    func legacyVisibleToolbarBackgrounds() -> some View {
        if #unavailable(iOS 26) {
            toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(.visible, for: .bottomBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
