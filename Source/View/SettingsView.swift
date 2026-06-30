//
//  SettingsView.swift
//  Maktabah
//

import SwiftUI

final class SettingsViewModel: ObservableObject {
    static var shared: SettingsViewModel = .init()
    @Published var isBundleMode: Bool = AppConfig.isUsingBundleMode
    @Published var databaseFilesPath: String = "N/A"
    @Published var archiveFilesPath: String = "N/A"
    @Published var annotationsPath: String = "N/A"
    @Published var useICloud: Bool = AppConfig.useICloud
    @Published var isProcessingICloud = false
    @Published var showCollisionAlert = false
    @Published var hasBundledData: Bool = false
    @Published var hasPendingVacuum: Bool = false
    @Published var isVacuuming: Bool = false
    @Published var enableAutoCoreVersionCheck: Bool = true

    @AppStorage("hideMissingBookAnnotations") var hideMissingBookAnnotations: Bool = false
    @AppStorage("useDefaultTheme") var useDefaultTheme: Bool = false

    enum PendingCollisionAction {
        case moveFolder(url: URL)
    }
    
    private var pendingCollisionAction: PendingCollisionAction?

    #if DIRECT_DISTRIBUTION
    @Published var autoCheckAppUpdates: Bool = true


    func setAutoCheckAppUpdates(_ enabled: Bool) {
        UserDefaults.standard.autoCheckAppUpdates = enabled
        refreshPaths()
    }
    #endif

    private init() {
        refreshPaths()
    }

    func refreshPaths() {
        databaseFilesPath = AppConfig.databaseFilesPath ?? "N/A"
        archiveFilesPath = AppConfig.archiveFilesPath ?? "N/A"
        annotationsPath =
            AppConfig.folder(for: AppConfig.annotationsAndResultsFolder)?
                .path ?? "N/A"
        isBundleMode = AppConfig.isUsingBundleMode
        useICloud = AppConfig.useICloud
        #if DIRECT_DISTRIBUTION
        autoCheckAppUpdates = UserDefaults.standard.autoCheckAppUpdates
        #endif
        checkBundledData()
        hasPendingVacuum = BookArchiveIntegrator.shared.hasPendingVacuum
        enableAutoCoreVersionCheck = UserDefaults.standard.enableAutoCoreVersionCheck
    }

    func runVacuum() {
        isVacuuming = true
        Task.detached(priority: .userInitiated) {
            BookArchiveIntegrator.shared.vacuumPendingArchives()
            await MainActor.run {
                self.isVacuuming = false
                // Re-check pending vacuum status to update UI
                self.hasPendingVacuum = BookArchiveIntegrator.shared.hasPendingVacuum
                self.refreshPaths()
            }
        }
    }

    func checkBundledData() {
        guard let path = AppConfig.archiveCachePath else {
            hasBundledData = false
            return
        }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else {
            hasBundledData = false
            return
        }
        // Check if any relevant files exist
        hasBundledData = items.contains { 
            $0.hasSuffix(".sqlite") || $0 == "index.json" || $0 == "integration_cache" || $0 == "Books"
        }
    }

    func cleanupBundledData() {
        guard let path = AppConfig.archiveCachePath else { return }
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        
        do {
            let items = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for item in items {
                try fm.removeItem(at: item)
            }
            refreshPaths()
        } catch {
            #if DEBUG
            print("Failed to cleanup bundled data:", error)
            #endif
        }
    }
    
    func setBundleMode(_ enabled: Bool) {
        if enabled {
            SettingsActions.switchToBundleMode(
                onCompletion: { [weak self] in
                    self?.refreshPaths()
                }
            )
            return
        }
        _ = SettingsActions.selectLibraryFolder(
            showSuccessAlert: false,
            shouldTerminateOnCancel: false
        ) { [weak self] success in
            DispatchQueue.main.async {
                if !success { self?.isBundleMode = true }
                self?.refreshPaths()
            }
        }
    }

    func chooseAnnotationsFolder(onCompletion: ((Bool) -> Void)? = nil) {
        SettingsActions.chooseAnnotationsAndResultsFolder(resolution: .ask) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else {
                    onCompletion?(false)
                    return
                }
                switch result {
                case .success:
                    self.refreshPaths()
                    onCompletion?(true)
                case .failure(let error):
                    if let storageError = error as? StorageError,
                        case .collision(let url) = storageError, let safeUrl = url
                    {
                        self.pendingCollisionAction = .moveFolder(url: safeUrl)
                        self.showCollisionAlert = true
                        onCompletion?(false)
                    } else {
                        ReusableFunc.showAlert(
                            title: NSLocalizedString("errorFolderAnnotations", comment: ""),
                            message: error.localizedDescription
                        )
                        onCompletion?(false)
                    }
                case .none:
                    onCompletion?(false)
                }
            }
        }
    }

    func chooseLibraryFolder() {
        _ = SettingsActions.selectLibraryFolder(
            showSuccessAlert: true,
            shouldTerminateOnCancel: false
        ) { [weak self] success in
            DispatchQueue.main.async {
                if success { self?.isBundleMode = false }
                self?.refreshPaths()
            }
        }
    }

    func openFullLibraryDownload() {
        SettingsActions.openFullLibraryDownloadURL()
    }

    #if os(macOS)
    func openSelectiveDownload() {
        SettingsActions.downloadSelectiveLibrary()
    }
    #endif

    func setICloud(_ enabled: Bool) {
        if enabled {
            isProcessingICloud = true
            AppConfig.setUseICloud(true, resolution: .ask) { [weak self] error in
                guard let self else { return }
                self.isProcessingICloud = false

                if let error {
                    self.useICloud = false // rollback
                    ReusableFunc.showAlert(
                        title: NSLocalizedString("errorICloud", comment: ""),
                        message: error.localizedDescription
                    )
                }
                self.refreshPaths()
            }
        } else {
            // Must choose folder before disabling
            self.chooseAnnotationsFolder { [weak self] success in
                guard let self = self else { return }
                if success {
                    self.isProcessingICloud = true
                    AppConfig.setUseICloud(false, resolution: .ask) { [weak self] error in
                        guard let self = self else { return }
                        self.isProcessingICloud = false
                        if let error {
                            self.useICloud = true // rollback
                            ReusableFunc.showAlert(
                                title: NSLocalizedString("errorICloud", comment: ""),
                                message: error.localizedDescription
                            )
                        }
                        self.refreshPaths()
                    }
                } else {
                    // Revert toggle if folder selection was cancelled
                    self.useICloud = true
                    self.refreshPaths()
                }
            }
        }
    }

    func resetCloudKitToken() {
        CloudKitSyncManager.shared.resetChangeToken()
        ReusableFunc.showAlert(
            title: NSLocalizedString("success", comment: ""),
            message: NSLocalizedString("CloudKit token has been reset. Full sync will start.", comment: "")
        )
    }

    func resolveCollision(_ resolution: AppConfig.MigrationResolution) {
        guard let action = pendingCollisionAction else { return }
        
        switch action {
        case .moveFolder(let url):
            if resolution == .ask {
                self.pendingCollisionAction = nil
                return
            }
            
            SettingsActions.chooseAnnotationsAndResultsFolder(resolution: resolution, retryURL: url) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.pendingCollisionAction = nil
                    switch result {
                    case .success:
                        self.refreshPaths()
                    case .failure(let error):
                        ReusableFunc.showAlert(
                            title: NSLocalizedString("errorFolderAnnotations", comment: ""),
                            message: error.localizedDescription
                        )
                    case .none:
                        break
                    }
                }
            }
        }
    }

    func setEnableAutoCoreVersionCheck(_ on: Bool) {
        UserDefaults.standard.enableAutoCoreVersionCheck = on
        enableAutoCoreVersionCheck = on
        if on {
            AppConfig.forceRefreshCoreVersion()
        } else {
            AppConfig.markCoreVersionCheckDone(
                newVersion: DatabaseManager.shared.getLocalVersionDisplay()
            )
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel.shared

    var body: some View {
        #if os(macOS)
        macOSForm
        #else
        iOSForm
        #endif
    }
}

// MARK: - macOS Form
#if os(macOS)
extension SettingsView {
    private var macOSForm: some View {
        Form {
            databaseModeSection
            libraryStorageSection
            annotationsSection
            downloadsSection
            if shouldShowUpdatesSection { updatesSection }
        }
        .formStyle(.grouped)
        .controlSize(.large)
        .frame(minWidth: 520, minHeight: 480)
        .alert(.annotationMoveFolderFileExistsTitle, isPresented: $viewModel.showCollisionAlert) {
            collisionAlertButtons
        } message: {
            Text(.annotationsMoveFolderFileExistsDesc)
        }
    }
}
#endif

// MARK: - iOS Form
#if os(iOS)
extension SettingsView {
    private var iOSForm: some View {
        Form {
            databaseModeSection
                .listRowBackground(Color.appCellBackground)
            libraryStorageSection
                .listRowBackground(Color.appCellBackground)
            annotationsSection
                .listRowBackground(Color.appCellBackground)
            appearanceSection
                .listRowBackground(Color.appCellBackground)

            if AppConfig.isUsingBundleMode,
               viewModel.hasPendingVacuum || viewModel.isVacuuming {
                optimizationSection
                    .listRowBackground(Color.appCellBackground)
            }

            if shouldShowUpdatesSection {
                updatesSection
                    .listRowBackground(Color.appCellBackground)
            }

            downloadsSection
                .listRowBackground(Color.appCellBackground)
        }
        .formStyle(.grouped)
        .controlSize(.large)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .alert(.annotationMoveFolderFileExistsTitle, isPresented: $viewModel.showCollisionAlert) {
            collisionAlertButtons
        } message: {
            Text(.annotationsMoveFolderFileExistsDesc)
        }
    }

    private var appearanceSection: some View {
        Section {
            Toggle(isOn: $viewModel.useDefaultTheme) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use System Theme")
                    Text("Replace the default sepia theme with standard iOS system appereance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.regular)
        } header: {
            Text("Appearance")
        }
    }

    private var optimizationSection: some View {
        Section {
            Button(action: {
                viewModel.runVacuum()
            }) {
                HStack {
                    Text(.optimizeDatabase)
                    if viewModel.isVacuuming {
                        Spacer()
                        ProgressView()
                            .controlSize(.regular)
                    }
                }
            }
            .disabled(viewModel.isVacuuming)

            Text(.optimizationIsNeededToReclaimDiskSpaceAfterDeletingBooks)
                .padding(2)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(.optimization)
        }
    }
}
#endif

// MARK: - Shared Sections
extension SettingsView {
    private var databaseModeSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.isBundleMode },
                set: { viewModel.setBundleMode($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bundle Mode")
                    Text("Use the app's built-in database (read-only). For the Full Library, disable this and choose a custom folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }.controlSize(.regular)
        } header: {
            Text("Database Mode")
        }
    }

    private var libraryStorageSection: some View {
        Section {
            if !viewModel.isBundleMode {
                PathRow(label: "Database Files", path: viewModel.databaseFilesPath)
                PathRow(label: "Archive Files", path: viewModel.archiveFilesPath)
            }

            #if os(macOS)
            HStack(spacing: 8) { libraryButtons }
            #else
            libraryButtons
            #endif

            if !viewModel.isBundleMode && viewModel.hasBundledData {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Cleanup Downloaded Data (Bundle Mode)") {
                        viewModel.cleanupBundledData()
                    }
                    .foregroundColor(.red)

                    Text("This will delete all downloaded SQLite files, index, and cache from the bundle mode storage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Library Storage")
        }
    }

    private var annotationsSection: some View {
        Section {
            Toggle(isOn: $viewModel.hideMissingBookAnnotations) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide Missing Book Annotations")
                    Text("Hide annotations if the corresponding book is not found in the local library.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.regular)

            Toggle(isOn: Binding(
                get: { viewModel.useICloud },
                set: { viewModel.setICloud($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use CloudKit")
                    Text("Sync annotations and search results across devices with CloudKit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.regular)
            .disabled(viewModel.isProcessingICloud)

            if !viewModel.useICloud {
                PathRow(label: "Current Path", path: viewModel.annotationsPath)
            }

            #if os(macOS)
            HStack { actionButtons }
                .padding(.top, 4)
            #else
            actionButtons
            #endif
        } header: {
            Text("Annotations & Search Results")
        }
    }

    @ViewBuilder
    private var libraryButtons: some View {
        Button("Choose Library Folder…") {
            viewModel.chooseLibraryFolder()
        }

        Button("Switch to Bundle Mode") {
            viewModel.setBundleMode(true)
        }
        .disabled(viewModel.isBundleMode)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Choose Annotations Folder…") {
            viewModel.chooseAnnotationsFolder()
        }
        .disabled(viewModel.useICloud)

        Button("Re-Synchronise All Data") {
            viewModel.resetCloudKitToken()
        }
        .foregroundColor(.red)
        .disabled(!viewModel.useICloud)
    }

    @ViewBuilder
    private var collisionAlertButtons: some View {
        Button(.keepExistingDeleteOld) {
            viewModel.resolveCollision(.keepDestination)
        }
        Button(.overwriteExisting, role: .destructive) {
            viewModel.resolveCollision(.overwriteDestination)
        }
        Button("Cancel", role: .cancel) {
            viewModel.resolveCollision(.ask) // used as cancel
        }
    }

    private var shouldShowUpdatesSection: Bool {
        #if os(macOS) && DIRECT_DISTRIBUTION
        // Jika build macOS & Direct Distribution, Toggle pertama PASTI ada
        return true
        #else
        // Jika build lain, tergantung pada runtime config ini
        return AppConfig.isUsingBundleMode
        #endif
    }

    private var updatesSection: some View {
        Section {
            #if os(macOS) && DIRECT_DISTRIBUTION
            Toggle(isOn: Binding(
                get: { viewModel.autoCheckAppUpdates },
                set: { viewModel.setAutoCheckAppUpdates($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Application Update")
                    Text("Check at Start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }.controlSize(.regular)
            #endif

            if AppConfig.isUsingBundleMode {
                Toggle(isOn: Binding(
                    get: { viewModel.enableAutoCoreVersionCheck },
                    set: { viewModel.setEnableAutoCoreVersionCheck($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Library Update")
                        Text("Semi-Annual Check")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Bi-Annual Routine Check until toggled off and on again.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .controlSize(.regular)
            }
        } header: {
            Text("Updates")
        }
    }

    private var downloadsSection: some View {
        Section {
            HStack(spacing: 8) {
                Button("Download Full Library (Google Drive)") {
                    viewModel.openFullLibraryDownload()
                }
                #if os(macOS)
                Button("Download Selective Library…") {
                    viewModel.openSelectiveDownload()
                }
                #endif
            }
            Label {
                Text("Full Library will open the download link in your browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.accentColor)
            }
        } header: {
            Text("Downloads")
        }
    }
}

// MARK: - Helpers

private struct PathRow: View {
    let label: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(path)
                .font(.footnote)
                .monospaced()
                .textSelection(.enabled)
                .foregroundStyle(path == "N/A" ? .tertiary : .primary)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
