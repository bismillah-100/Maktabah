import SwiftUI

struct iOSReaderView: View {
    let book: BooksData
    let initialContentId: Int?
    var ipad: Bool {
        MaktabahApp.isIpad
    }

    var viewModel: ReaderViewModel
    @State private var textViewState = TextViewState.shared
    @Environment(iOSNavigationManager.self) var bManager

    @State private var showingTOC = false
    @State private var showingOptions = false
    @State private var showingSearch = false
    @State private var showingAnnotationsList = false
    @State private var showingBookInfo = false
    @State private var showingAnnotationActionSheet = false
    @State private var tappedAnnotationId: Int64?
    @State private var showingEditNoteAlert = false
    @State private var editingNoteText = ""
    @State private var showingNavigation = false
    @State private var showingTabsList = false
    @State private var isReading = false

    init(book: BooksData,
         viewModel: ReaderViewModel? = nil,
         initialContentId: Int? = nil)
    {
        self.book = book
        self.initialContentId = initialContentId
        self.viewModel = viewModel ?? ReaderViewModel(book: book)
    }

    var backgroundColor: Color {
        let colors: [Color] = [
            .white,
            .bgSepia,
            .bgSepiaDark,
            .bgGray,
            .black,
        ]
        let index = textViewState.backgroundColorIndex

        if index >= 0, index < colors.count {
            return colors[index]
        }
        return Color(UIColor.systemBackground)
    }

    var isDarkMode: Bool {
        textViewState.isDarkMode
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        iOSIbarotTextView(
            text: $viewModel.contentText,
            annotations: viewModel.currentAnnotations,
            searchText: $viewModel.searchText,
            targetAnnotation: viewModel.targetAnnotation,
            isMultiLanguage: book.isMultiLanguage,
            isImported: book.isImported,
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
        .background(backgroundColor)
        .ignoresSafeArea(edges: .vertical)
        .legacyVisibleToolbarBackgrounds()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .navigationTitle(bManager.openTabs.count > 1 ? "" : book.book)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .if(!MaktabahApp.isIpad) { view in
            view.toolbarVisibility(
                isReading ? .hidden : .visible,
                for: .navigationBar, .bottomBar
            )
        }
        .onTapGesture {
            withAnimation(.easeInOut) {
                isReading.toggle()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !ipad, bManager.openTabs.count > 1 {
                    Button {
                        showingTabsList.toggle()
                    } label: {
                        Text(book.book)
                            .frame(maxWidth: 190)
                            .contentShape(Rectangle())
                    }
                    .popover(isPresented: $showingTabsList) {
                        iOSReaderTabsPopoverView(isPresented: $showingTabsList)
                        .frame(maxWidth: 350)
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }

            CustomToolbarSpacer(placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showingBookInfo = true
                }) {
                    Label("BookInfo", systemImage: "info.circle")
                }
                .accessibilityLabel(String(localized: "Book Information"))
                .help(String(localized: "Book Information"))
                .popover(isPresented: $showingBookInfo) {
                    iOSBookInfoView(book: book)
                        .preferredColorScheme(isDarkMode ? .dark : .light)
                        .presentationCompactAdaptation(.popover)
                        .frame(maxWidth: 350, maxHeight: 450)
                }
            }

            ToolbarItemGroup(placement: .bottomBar) {
                iOSReaderBottomToolbarView(viewModel: viewModel)
            }
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
            iOSBookSearchView(book: book, onSelect: { contentId, query in
                viewModel.didSelectSearch(query: query, contentId: contentId)
                showingSearch = false
            }, viewModel: viewModel.searchViewModel)
        }
        .sheet(isPresented: $showingTOC) {
            iOSTOCView(
                tocViewModel: viewModel.tocViewModel,
                selectedId: viewModel.tocViewModel.findNode(forContentId: viewModel.currentContentId)?.id,
                onSelect: { id in
                    viewModel.didSelectTOCNode(id: id)
                    showingTOC = false
                }
            )
        }
        .sheet(isPresented: $showingAnnotationsList) {
            iOSBookAnnotationsView(
                bookId: book.id,
                annotations: viewModel.currentAnnotations,
                onSelect: { ann in
                    viewModel.didSelectAnnotation(ann)
                    showingAnnotationsList = false
                }
            )
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

private extension View {
    @ViewBuilder
    func legacyVisibleToolbarBackgrounds() -> some View {
        if #unavailable(iOS 26) {
            self
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(.visible, for: .bottomBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}
