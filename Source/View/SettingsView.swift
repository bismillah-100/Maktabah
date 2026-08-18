//
//  SettingsView.swift
//  Maktabah
//

import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel.shared
    #if os(macOS)
    @ObservedObject private var ftsManager = FtsMigrationManager.shared
    #elseif os(iOS)
    @State private var ftsManager = FtsMigrationManager.shared
    #endif
    #if os(iOS)
    @State private var showFtsMigrationOverlay = false
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            macOSForm
            #else
            iOSForm
            #endif
        }
        .onAppear {
            ftsManager.checkNeedsMigration()
        }
    }
    
    @ViewBuilder
    private var searchIndexSection: some View {
        if ftsManager.needsMigration {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(.ftsMigrationAvailable)
                        .font(.caption)
                        .foregroundColor(.primary)

                    if !ftsManager.isMigrating {
                        Button {
                            #if os(macOS)
                            SettingsActions.showFtsMigrationModal()
                            #else
                            showFtsMigrationOverlay = true
                            #endif
                        } label: {
                            Text(.ftsMigrationUpdateIndexBtn(ftsManager.totalArchivesToMigrate))
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Search Index")
            }
        }
    }
}

// MARK: - macOS Form
#if os(macOS)
extension SettingsView {
    private var macOSForm: some View {
        Form {
            databaseModeSection
            searchIndexSection
            libraryStorageSection
            annotationsSection
            searchSection
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
            searchIndexSection
                .listRowBackground(Color.appCellBackground)
            libraryStorageSection
                .listRowBackground(Color.appCellBackground)
            annotationsSection
                .listRowBackground(Color.appCellBackground)
            searchSection
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
        .overlay {
            if showFtsMigrationOverlay {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .zIndex(10)
                FtsMigrationProgressView(
                    onCancel: {
                        showFtsMigrationOverlay = false
                    },
                    onUpdate: {
                        try await ftsManager.performMigration()
                        await MainActor.run { showFtsMigrationOverlay = false }
                    }
                )
                .zIndex(11)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut, value: showFtsMigrationOverlay)
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

    private var searchSection: some View {
        Section {
            Toggle(isOn: $viewModel.recordSearchHistory) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(.readingHistory)
                    Text(.addBooksOpenedFromSearchResultsToReadingHistory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.regular)
        } header: {
            Text("History")
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

            if viewModel.useICloud {
                Toggle(isOn: Binding(
                    get: { viewModel.useCrossPlatformSync },
                    set: { viewModel.setCrossPlatformSync($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cross-Platform Sync")
                        Text("Notify other platforms to sync when changes are made.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .controlSize(.regular)

                #if DEBUG
                TextField("Debug Worker URL", text: Binding(
                    get: { viewModel.customWorkerURL },
                    set: { viewModel.setCustomWorkerURL($0) }
                ))
                .font(.caption)
                .controlSize(.regular)
                #endif
            }

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
