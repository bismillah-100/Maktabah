import SwiftUI

struct AnnotationListView: View {
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager
    @State private var showMissingBookAlert = false
    @State private var missingBookId: Int = 0
    @AppStorage("hideMissingBookAnnotations") private var hideMissingBookAnnotations: Bool = false

    @State private var isExporting = false
    @State private var exportDocument: AnnotationJsonDocument?
    @State private var isImporting = false
    @State private var pendingImportAnnotations: [Annotation] = []
    @State private var showOverwriteDialog = false
    @State private var importAlertTitle = ""
    @State private var importAlertMessage: String?
    @State private var showImportAlert = false

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

                    Button {
                        Task.detached(priority: .userInitiated) {
                            let allAnnotations = AnnotationManager.shared.loadAnnotations()
                            if let jsonString = AnnotationJsonSerializer.encode(annotations: allAnnotations) {
                                await MainActor.run {
                                    exportDocument = AnnotationJsonDocument(jsonString: jsonString)
                                    isExporting = true
                                }
                            }
                        }
                    } label: {
                        Label("Export Annotations (JSON)".localized, systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isImporting = true
                    } label: {
                        Label("Import Annotations (JSON)".localized, systemImage: "square.and.arrow.down")
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
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "maktabah_annotations.json"
        ) { result in
            if case let .failure(error) = result {
                importAlertTitle = "Export Failed".localized
                importAlertMessage = error.localizedDescription
                showImportAlert = true
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    importAlertTitle = "Import Failed".localized
                    importAlertMessage = "Unable to access selected file.".localized
                    showImportAlert = true
                    return
                }
                Task.detached(priority: .userInitiated) {
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let data = try Data(contentsOf: url)
                        let decoded = try AnnotationJsonSerializer.decode(from: data)
                        await MainActor.run {
                            guard !decoded.isEmpty else {
                                importAlertTitle = "Import Annotations".localized
                                importAlertMessage = "No annotations found in the selected file.".localized
                                showImportAlert = true
                                return
                            }
                            pendingImportAnnotations = decoded
                            showOverwriteDialog = true
                        }
                    } catch {
                        await MainActor.run {
                            importAlertTitle = "Import Failed".localized
                            importAlertMessage = error.localizedDescription
                            showImportAlert = true
                        }
                    }
                }
            case let .failure(error):
                importAlertTitle = "Import Failed".localized
                importAlertMessage = error.localizedDescription
                showImportAlert = true
            }
        }
        .confirmationDialog(
            "Import Annotations".localized,
            isPresented: $showOverwriteDialog,
            titleVisibility: .visible
        ) {
            Button("Overwrite Existing".localized) {
                performImport(overwrite: true, viewModel: viewModel)
            }
            Button("Skip Duplicates".localized) {
                performImport(overwrite: false, viewModel: viewModel)
            }
            Button("Cancel".localized, role: .cancel) {
                pendingImportAnnotations = []
            }
        } message: {
            Text("Some annotations may already exist. How would you like to handle duplicates?".localized)
        }
        .onChange(of: showOverwriteDialog) { _, isPresented in
            if !isPresented {
                pendingImportAnnotations = []
            }
        }
        .alert(
            importAlertTitle,
            isPresented: $showImportAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let msg = importAlertMessage {
                Text(msg)
            }
        }
    }

    private func performImport(overwrite: Bool, viewModel: AnnotationViewModel) {
        let annotations = pendingImportAnnotations
        pendingImportAnnotations = []
        Task.detached(priority: .userInitiated) {
            do {
                let count = try AnnotationManager.shared.importAnnotations(annotations, overwrite: overwrite)
                await MainActor.run {
                    importAlertTitle = "Import Annotations".localized
                    importAlertMessage = String(format: "%d annotations imported successfully".localized, count)
                    showImportAlert = true
                }
                await viewModel.loadAnnotations()
            } catch {
                await MainActor.run {
                    importAlertTitle = "Import Failed".localized
                    importAlertMessage = error.localizedDescription
                    showImportAlert = true
                }
            }
        }
    }
}
