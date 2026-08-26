import SwiftUI
import UIKit

// MARK: - SwiftUI View

struct iOSLibraryView: View {
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager

    var body: some View {
        @Bindable var viewModel = navigationManager.libraryViewModel

        let importErrorBinding = Binding<Bool>(
            get: { viewModel.importErrorMessage != nil },
            set: { if !$0 { viewModel.importErrorMessage = nil } }
        )

        let singleDeleteBinding = Binding<Bool>(
            get: { viewModel.singleBookToDelete != nil },
            set: { if !$0 { viewModel.singleBookToDelete = nil } }
        )

        libraryVC(viewModel: viewModel)
            .onChange(of: viewModel.selectedBookIds) { _, _ in
                handleSelectionChange(viewModel: viewModel)
            }
            .toolbar {
                toolbarContent(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingImportSheet) {
                NavigationStack {
                    OfflineImportFormView { url, metadata, authorRow in
                        await viewModel.importOfflineBook(from: url, metadata: metadata, authorRow: authorRow)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingUpdateSheet) {
                UpdateView()
            }
            .task {
                viewModel.checkBookUpdatesPeriodically()
            }
            .alert("Import Success", isPresented: $viewModel.showImportSuccessAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: .importSuccessDesc))
            }
            .alert("Import Error", isPresented: importErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.importErrorMessage ?? "")
            }
            .alert("Delete Download", isPresented: $viewModel.showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    viewModel.startBulkDeletion {}
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete the downloaded content for \(viewModel.selectedDeleteCount) books?")
            }
            .alert("Delete Download", isPresented: singleDeleteBinding) {
                Button("Delete", role: .destructive) {
                    if let book = viewModel.singleBookToDelete {
                        Task {
                            await viewModel.deleteSingleBook(book)
                            viewModel.singleBookToDelete = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete the downloaded content for \"\(viewModel.singleBookToDelete?.book ?? "")\"?")
            }
    }

    private func libraryVC(viewModel: LibraryViewModel) -> some View {
        LibraryViewControllerWrapper(
            navigationManager: navigationManager,
            viewModel: viewModel,
            showOnlyDownloaded: Binding(
                get: { viewModel.showOnlyDownloaded },
                set: { viewModel.showOnlyDownloaded = $0 }
            ),
            onDeleteSingleBook: { book in
                viewModel.singleBookToDelete = book
            },
            onDownloadSingleBook: { book in
                navigationManager.showBookIntegrationConfirmation(
                    for: book,
                    initialContentId: nil
                )
            }
        )
        .themeTint()
        .ignoresSafeArea(edges: [.vertical])
        .overlay {
            if viewModel.state == .loading {
                ProgressView("Loading Library...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themeBackground()
            }
        }
        .withActiveIntegrationStates()
    }

    private func handleSelectionChange(viewModel: LibraryViewModel) {
        guard !viewModel.isBulkDownloading else { return }

        let downloadBooks = viewModel.selectedDownloadBooks
        if !downloadBooks.isEmpty {
            let hasBulkConfirmation = navigationManager.activeIntegrationStates.contains { state in
                if case .bulk = state.pendingData, state.mode == .confirmation { return true }
                return false
            }

            if !hasBulkConfirmation {
                navigationManager.showBulkDownloadConfirmation(books: downloadBooks)
            } else {
                if let bulkState = navigationManager.activeIntegrationStates.first(where: {
                    if case .bulk = $0.pendingData, $0.mode == .confirmation { return true }
                    return false
                }) {
                    navigationManager.activeIntegrationStates.removeAll { $0.id == bulkState.id }
                    navigationManager.showBulkDownloadConfirmation(books: downloadBooks)
                }
            }
        } else {
            navigationManager.activeIntegrationStates.removeAll { state in
                if case .bulk = state.pendingData, state.mode == .confirmation { return true }
                return false
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(viewModel: LibraryViewModel) -> some ToolbarContent {
        if viewModel.isSelectionMode {
            selectionToolbarItems(viewModel: viewModel)
        } else {
            standardToolbarItems(viewModel: viewModel)
        }
    }

    @ToolbarContentBuilder
    private func selectionToolbarItems(viewModel: LibraryViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") {
                viewModel.exitSelectionMode()
            }
            .disabled(viewModel.isBulkDownloading)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                viewModel.showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(viewModel.selectedDeleteCount == 0 || viewModel.isBulkDownloading)
            .tint(.red)
        }
    }

    @ToolbarContentBuilder
    private func standardToolbarItems(viewModel: LibraryViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            groupByMenu(viewModel: viewModel)
        }

        ToolbarItem(placement: .topBarTrailing) {
            if AppConfig.isUsingBundleMode {
                downloadedFilterToggle(viewModel: viewModel)
            }
        }

        CustomToolbarSpacer(placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            optionsMenu(viewModel: viewModel)
        }
    }

    private func groupByMenu(viewModel: LibraryViewModel) -> some View {
        Menu {
            Section("Group By") {
                Button { viewModel.viewMode = .category } label: {
                    Label("Category", systemImage: "folder")
                }
                Button { viewModel.viewMode = .author } label: {
                    Label("Author", systemImage: "person")
                }
            }
        } label: {
            Label(
                "Group By",
                systemImage: viewModel.viewMode == .category ? "folder" : "person"
            )
        }
    }

    private func downloadedFilterToggle(viewModel: LibraryViewModel) -> some View {
        Toggle(isOn: Binding(
            get: { viewModel.showOnlyDownloaded },
            set: { viewModel.showOnlyDownloaded = $0 }
        )) {
            Label("Downloaded", systemImage: "line.3.horizontal.decrease")
        }
        .labelStyle(.iconOnly)
        .toggleStyle(.button)
    }

    private func optionsMenu(viewModel: LibraryViewModel) -> some View {
        Menu {
            Button {
                viewModel.enterSelectionMode()
            } label: {
                Label("Select".localized + "...", systemImage: "checkmark.circle")
            }

            Button {
                viewModel.showingUpdateSheet = true
            } label: {
                Label(
                    viewModel.availableUpdateCount > 0
                        ? "\("Update Books".localized) (\(viewModel.availableUpdateCount))"
                        : "Update Books".localized,
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }

            Button {
                viewModel.showingImportSheet = true
            } label: {
                Label("Import Book", systemImage: "plus.viewfinder")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(String(localized: "Library Options"))
        .help(String(localized: "Library Options"))
    }

    private func startSelectedDownloads(using viewModel: LibraryViewModel) {
        let state = BundleArchiveDownloadProgressState(
            title: NSLocalizedString(
                "Download Book",
                comment: "Bulk download window title"
            ),
            message: String(localized: "Begin downloading..."),
            mode: .downloading
        )
        navigationManager.activeIntegrationStates.append(state)

        viewModel.startBulkDownload(progressState: state) { message in
            navigationManager.activeIntegrationStates.removeAll { $0.id == state.id }
            viewModel.exitSelectionMode()

            if let message {
                navigationManager.alertMessage = iOSNavigationManager.AlertMessage(
                    title: NSLocalizedString(
                        "Download Book",
                        comment: "Bulk download window title"
                    ),
                    message: message
                )
            }
        }
    }
}
