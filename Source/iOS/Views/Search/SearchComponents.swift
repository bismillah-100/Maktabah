import SwiftUI

// MARK: - Search History Overlay

struct SearchHistoryOverlay: View {
    @Environment(\.isSearching) var isSearching
    @Environment(\.dismissSearch) var dismissSearch
    @Bindable var viewModel: SearchViewModel
    @State var inputBarHeight: CGFloat = 0
    @Binding var isVisible: Bool?
    @State private var showingHelp: Bool = false
    @State private var isShowing = false

    private var shouldShow: Bool {
        isVisible == true ||
        (isSearching && isVisible == nil &&
         !viewModel.isSearching && viewModel.results.isEmpty)
    }

    var body: some View {
        Group {
            if isShowing {
                VStack(spacing: 0) {
                    if !viewModel.searchHistory.isEmpty {
                        historyHeader
                        historyList
                    }
                    inputControls
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.appBackground)
                .cornerRadius(12)
                .shadow(radius: 10)
                .padding(.horizontal)
                .padding(.vertical, inputBarHeight)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .readInputBarHeight()
            }
        }
        .animation(
            .interpolatingSpring(stiffness: 250, damping: 24),
            value: isShowing
        )
        .onChange(of: shouldShow) { _, newValue in
            isShowing = newValue
        }
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 250, damping: 24)) {
                isShowing = shouldShow
            }
        }
    }

    private var historyHeader: some View {
        HStack {
            Button("Clear All") {
                withAnimation(.easeOut(duration: 0.25)) {
                    viewModel.searchHistory.forEach { viewModel.removeFromHistory($0) }
                }
            }
            .font(.caption)

            Spacer()

            Text("History")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.appSecondaryBackground)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.searchHistory.enumerated()), id: \.element) { index, historyQuery in
                    VStack(spacing: 0) {
                        Button(action: {
                            viewModel.query = historyQuery
                            viewModel.addToHistory(historyQuery)
                            viewModel.startSearch()
                            isVisible = false
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
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }
                        Divider()
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))  // ← di dalam
                    .animation(
                        .easeOut(duration: 0.2).delay(Double(index) * 0.04),
                        value: viewModel.searchHistory
                    )
                }
            }
        }
        .frame(maxHeight: 260)
        .background(Color.appBackground)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var inputControls: some View {
        HStack(spacing: 12) {
            Picker("Mode", selection: $viewModel.searchMode) {
                Image(systemName: "text.quote").tag(SearchMode.phrase)
                Image(systemName: "checklist.checked").tag(SearchMode.contains)
                Image(systemName: "checklist").tag(SearchMode.or)
            }
            .controlSize(.regular)
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            Spacer()

            Button(action: { showingHelp = true }) {
                Label("Help", systemImage: "questionmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.foreground)
            }
            .popover(isPresented: $showingHelp) {
                SearchHelpView()
                    .frame(width: 300, height: 450)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .prominentButtonStyleIfAvailable()
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Search Input Bar

struct SearchInputBar: View {
    @Bindable var viewModel: SearchViewModel
    @FocusState var isFocused: Bool
    @AppStorage("useDefaultTheme") private var useDefaultTheme: Bool = false
    var onSubmit: () -> Void

    var body: some View {
        TextField(
            "", text: $viewModel.query,
            prompt: Text(.searchInSelectedBooks)
                .foregroundStyle(Color(useDefaultTheme
                                       ? .secondaryLabel
                                       : .iosTint))
        )
        .focused($isFocused)
        .submitLabel(.go)
        .onSubmit(onSubmit)
        .padding(.leading, 20)
        .padding(.trailing, 44)
        .frame(height: 40)
        .background(Color.appCellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.secondary, lineWidth: 0.3)
        )
        .overlay(alignment: .trailing) {
            Button(action: onSubmit) {
                Image(systemName: "play.fill")
                    .foregroundStyle(Color(useDefaultTheme
                                           ? .secondaryLabel
                                           : .iosTint))
                    .padding(.trailing, 20)
            }
            .accessibilityLabel("Start Search")
            .help("Start Search")
        }
        .shadow(
            color: .black.opacity(isFocused ? 0.15 : 0.1),
            radius: isFocused ? 8 : 15, x: 0, y: 2
        )
        .padding(.vertical)
        .padding(.horizontal, 20)
    }
}

// MARK: - Search Help View

struct SearchHelpView: View {
    var body: some View {
        ThemeScrollView {
            ThemeVStack(alignment: .leading, spacing: 12) {
                Label(.searchOptionsHelp, systemImage: "play")
                    .font(.headline)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Label(.exactSearchTitle, systemImage: "text.quote")
                        .font(.subheadline).bold()
                    Text(NSLocalizedString("exactSearchDesc", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Label(.separateWordsSearchTitle, systemImage: "checklist.checked")
                        .font(.subheadline).bold()
                    Text("separateWordsSearchDesc")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Label("anyWordsSearchTitle", systemImage: "checklist")
                        .font(.subheadline).bold()
                    Text("anyWordsSearchDesc")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

// MARK: - View Modifiers

extension View {
    func prominentButtonStyleIfAvailable() -> some View {
        modifier(ProminentButtonStyle())
    }

    func hideTabBarWhenKeyboardShown() -> some View {
        modifier(HideTabBarWhenKeyboardShown())
    }

    func readInputBarHeight() -> some View {
        modifier(InputBarHeightReader())
    }
}

struct ProminentButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(.clear)
        } else {
            content
                .buttonStyle(.borderedProminent)
        }
    }
}

struct HideTabBarWhenKeyboardShown: ViewModifier {
    @State private var isKeyboardVisible = false

    func body(content: Content) -> some View {
        content
            .toolbarVisibility(isKeyboardVisible ? .hidden : .visible, for: .tabBar)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
    }
}

struct InputBarHeightReader: ViewModifier {
    @State private var inputBarHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { inputBarHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in inputBarHeight = h }
                }
            }
    }
}

// MARK: - Search Toolbar

struct SearchToolbar: ToolbarContent {
    @Bindable var viewModel: SearchViewModel
    var onLeadingAction: (() -> Void)?
    var conditionalLeadingButton: Bool = true
    var showSortMenu: Bool = false
    var showSaveMenu: Bool = false
    var sortKey: SearchSortKey = .bookTitle
    var sortAscending: Bool = true
    var onSortChange: ((SearchSortKey, Bool) -> Void)?
    var onSaveResults: (() -> Void)?
    var onSavedResults: (() -> Void)?

    var body: some ToolbarContent {
        // Leading
        if (!conditionalLeadingButton) ||
            (!viewModel.results.isEmpty && conditionalLeadingButton) {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { onLeadingAction?() }) {
                    Label(.close, systemImage: conditionalLeadingButton
                          ? "xmark.circle"
                          : "")
                }
                .accessibilityLabel(.close)
                .help(.close)
            }
        }

        // Play/Pause + Stop
        ToolbarItemGroup(placement: .topBarTrailing) {
            Toggle(
                "",
                systemImage: viewModel.isSearching && !viewModel.isPaused
                    ? "pause" : "play",
                isOn: Binding(
                    get: { viewModel.isSearching },
                    set: { _, _ in viewModel.startSearch() }
                )
            )
            .labelStyle(.iconOnly)
            .toggleStyle(.button)

            if viewModel.isSearching {
                Button(action: { viewModel.stopSearch() }) {
                    Image(systemName: "stop")
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Stop Search")
                .help("Stop Search")
            } else if showSortMenu, !viewModel.results.isEmpty {
                sortMenu
            }
        }

        CustomToolbarSpacer(placement: .topBarTrailing)

        // Save menu
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                if showSaveMenu {
                    Button(action: { onSavedResults?() }) {
                        Label("Saved Results", systemImage: "bookmark")
                    }
                }

                if !viewModel.results.isEmpty {
                    Button(action: { onSaveResults?() }) {
                        Label("Save Results", systemImage: "pencil.line")
                    }
                }
            } label: {
                Label(.moreOptions, systemImage: "ellipsis")
            }
            .accessibilityLabel("Search Options")
            .help("Search Options")
        }
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            ForEach(SearchSortKey.allCases, id: \.self) { key in
                Button {
                    if sortKey == key {
                        onSortChange?(key, !sortAscending)
                    } else {
                        onSortChange?(key, true)
                    }
                } label: {
                    Label(
                        key.label,
                        systemImage: sortKey == key
                            ? (sortAscending ? "chevron.up" : "chevron.down")
                            : ""
                    )
                }
            }
        } label: {
            Label("Sort By", systemImage: "arrow.up.arrow.down")
        }
    }
}

// MARK: - Search Progress View

struct SearchProgressView: View {
    @Bindable var viewModel: SearchViewModel
    var showTablesProgress: Bool = false
    var showIntegrationState: Bool = true
    @Environment(iOSNavigationManager.self) var navigationManager: iOSNavigationManager

    var body: some View {
        let integrationStates = navigationManager.activeIntegrationStates
        if viewModel.isSearching || !integrationStates.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isSearching {
                    VStack(alignment: .leading) {
                        if showTablesProgress {
                            ProgressView(
                                value: Double(min(viewModel.completedTables, viewModel.totalTables)),
                                total: Double(max(viewModel.totalTables, 1))
                            )
                            .progressViewStyle(.linear)
                        }

                        if viewModel.totalRowsInTable > 0 {
                            ProgressView(
                                value: Double(viewModel.completedRowsInTable),
                                total: Double(viewModel.totalRowsInTable)
                            )
                            .progressViewStyle(.linear)
                            .padding(.top, showTablesProgress ? 4 : 0)
                        } else if !showTablesProgress {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }
                if showIntegrationState {
                    ActiveIntegrationStatesView()
                }
            }
            .animation(
                .easeIn(duration: 0.5),
                value: [viewModel.completedRowsInTable, viewModel.completedTables]
            )
        }
    }
}
