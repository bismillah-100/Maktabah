import SwiftUI

enum iOSTab: Int, CaseIterable, Identifiable {
    case viewer
    case search
    case author
    case annotations
    case history

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .viewer: "Library".localized
        case .search: "Search".localized
        case .author: "Narrators".localized
        case .annotations: "Annotations".localized
        case .history: "History".localized
        }
    }

    var icon: String {
        switch self {
        case .viewer: "books.vertical.fill"
        case .search: "magnifyingglass"
        case .author: "person.text.rectangle.fill"
        case .annotations: "quote.closing"
        case .history: "clock.fill"
        }
    }

    var appMode: AppMode {
        switch self {
        case .viewer: .viewer
        case .search: .search
        case .author: .narrator
        case .annotations: .annotations
        case .history: .history
        }
    }
}

// MARK: - Main View

struct iOSMainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var navigationManager = iOSNavigationManager()
    @State private var selectedTab: iOSTab = .viewer
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showSettings = false

    var body: some View {
        @Bindable var bManager = navigationManager

        Group {
            if horizontalSizeClass == .regular {
                iPadLayout(
                    bManager: bManager,
                    selectedTab: $selectedTab,
                    columnVisibility: $columnVisibility,
                    showSettings: $showSettings
                )
            } else {
                iPhoneLayout(
                    bManager: bManager,
                    selectedTab: $selectedTab,
                    showSettings: $showSettings
                )
            }
        }
        .environment(navigationManager)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .listRowBackground(Color.appCellBackground)
                    .background(Color.appBackground)
                    .navigationTitle("Settings".localized)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
            .tint(.header)
        }
        .alert(item: $navigationManager.alertMessage) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                CloudKitSyncManager.shared.fetchChanges()
            }
        }
    }
}

// MARK: - Navigation Helper

extension View {
    func adaptiveReaderPush(item: Binding<BooksData?>, manager: iOSNavigationManager) -> some View {
        navigationDestination(item: item) { book in
            let tab = manager.openTabs.first(where: { $0.book.id == book.id && $0.id == manager.activeTabId })
                   ?? manager.openTabs.first(where: { $0.book.id == book.id })
            iOSReaderView(book: book, viewModel: tab?.viewModel, initialContentId: manager.selectedContentId)
        }
    }

    func toolbarGeneral(showSettings: Binding<Bool>) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings.wrappedValue = true } label: {
                    Image(systemName: "gear")
                }
                .accessibilityLabel(String(localized: "Settings"))
                .help(String(localized: "Settings"))
            }

            CustomToolbarSpacer(placement: .topBarLeading)
        }
    }
}

// MARK: - Custom Toolbar Spacer

struct CustomToolbarSpacer: ToolbarContent {
    let placement: ToolbarItemPlacement
    var minLength: CGFloat?

    init(placement: ToolbarItemPlacement = .automatic, minLength: CGFloat? = 16) {
        self.placement = placement
        self.minLength = minLength
    }

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            // swiftlint:disable:next unavailable_function
            ToolbarSpacer(placement: placement)
        }
    }
}

struct iOSMainView_Previews: PreviewProvider {
    static var previews: some View {
        iOSMainView()
            .task {
                AppConfig.initializeMode()
                AppConfig.setupAnnotationsAndResults()
                ArabicFont.registerCustomFonts()
            }
    }
}
