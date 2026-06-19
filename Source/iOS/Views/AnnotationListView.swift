import SwiftUI

struct AnnotationListView: View {
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager
    @State private var showMissingBookAlert = false
    @State private var missingBookId: Int = 0
    @AppStorage("hideMissingBookAnnotations") private var hideMissingBookAnnotations: Bool = false

    var body: some View {
        let viewModel = navigationManager.annotationViewModel
        annotationsVC(viewModel)
            .overlay {
                if viewModel.state == .loading {
                    ProgressView()
                        .controlSize(.large)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.appBackground)
                        )
                }
            }
            .task {
                await viewModel.loadAnnotations()
            }
    }

    @ViewBuilder
    private func annotationsVC(_ viewModel: AnnotationViewModel) -> some View {
        @Bindable var viewModel = viewModel
        AnnotationViewControllerWrapper(
            navigationManager: navigationManager,
            viewModel: viewModel
        )
        .themeTint()
        .ignoresSafeArea(edges: .vertical)
        .onReceive(NotificationCenter.default.publisher(for: .annotationMissingBook)) { notification in
            if let bookId = notification.object as? Int {
                missingBookId = bookId
                showMissingBookAlert = true
            }
        }
        .onChange(of: hideMissingBookAnnotations) { _, _ in
            viewModel.applyFilter()
        }
        .alert(
            .bookNotFound(bookID: missingBookId),
            isPresented: $showMissingBookAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(.bookMissingOnAnnotationClick)
        }
        .withActiveIntegrationStates()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Group By", selection: $viewModel.groupingMode) {
                        Text("Book").tag(AnnotationGroupingMode.book)
                        Text("Tag").tag(AnnotationGroupingMode.tag)
                    }

                    Divider()

                    Picker("Sort By", selection: $viewModel.sortField) {
                        Text("Date Created").tag(AnnotationSortField.createdAt)
                        Text("Context").tag(AnnotationSortField.context)
                        Text("Page").tag(AnnotationSortField.page)
                        Text("Part").tag(AnnotationSortField.part)
                    }

                    Picker("Order", selection: $viewModel.sortAscending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }

                    Divider()

                    Button(role: .destructive) {
                        CloudKitSyncManager.shared.resetChangeToken()
                    } label: {
                        Label("Re-Synchronise All Data", systemImage: "arrow.counterclockwise.icloud")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
            }
        }

    }
}

/// Ensure the Color extension works in SwiftUI using the existing hex string format
extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let hexNum = UInt64(s, radix: 16) else { return nil }

        let r = Double((hexNum & 0xFF0000) >> 16) / 255.0
        let g = Double((hexNum & 0x00FF00) >> 8) / 255.0
        let b = Double(hexNum & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
