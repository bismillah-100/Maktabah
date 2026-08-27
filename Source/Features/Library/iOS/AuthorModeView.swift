import SwiftUI

struct AuthorModeView: View {
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager
    @State private var navigateToReader = false

    var body: some View {
        let viewModel = navigationManager.authorViewModel

        Group {
            if viewModel.state == .loading {
                ProgressView("Loading Narrators...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themeBackground()
            } else {
                iOSRowiSidebarView(viewModel: viewModel, searchQuery: viewModel.lastSearchQuery)
                    .themeTint()
                    .ignoresSafeArea(edges: [.vertical])
                    .onChange(of: viewModel.currentRowi) { _, newRowi in
                        if newRowi != nil {
                            navigateToReader = true
                        }
                    }
                    .navigationDestination(isPresented: $navigateToReader) {
                        iOSRowiReaderView(viewModel: viewModel)
                            .onDisappear {
                                viewModel.currentRowi = nil
                            }
                    }
                    .withActiveIntegrationStates()
            }
        }
        .task {
            await viewModel.loadData()
        }
    }
}

struct iOSRowiReaderView: View {
    @Bindable var viewModel: NarratorViewModel

    var body: some View {
        ThemeScrollView {
            Text(viewModel.rowiContentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .environment(\.layoutDirection, .rightToLeft)
                .padding()
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Picker("Mode", selection: $viewModel.displayMode) {
                    ForEach(RowiDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(viewModel.currentRowi?.isoName ?? "الراوي")
        .navigationBarTitleDisplayMode(.inline)
    }
}
