//
//  SettingsView.swift
//  Maktabah
//

import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Bindable var viewModel = SettingsViewModel.shared
    var ftsManager = FtsMigrationManager.shared
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
                Text(.Setting.searchIndex)
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
        .alert(.Setting.annotationMoveFolderFileExistsTitle, isPresented: $viewModel.showCollisionAlert) {
            collisionAlertButtons
        } message: {
            Text(.Setting.annotationsMoveFolderFileExistsDesc)
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
        .alert(.Setting.annotationMoveFolderFileExistsTitle, isPresented: $viewModel.showCollisionAlert) {
            collisionAlertButtons
        } message: {
            Text(.Setting.annotationsMoveFolderFileExistsDesc)
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
                    Text(.Setting.useSystemTheme)
                    Text(.Setting.useSystemThemeDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.regular)
        } header: {
            Text(.Setting.appearance)
        }
    }

    private var optimizationSection: some View {
        Section {
            Button(action: {
                viewModel.runVacuum()
            }) {
                HStack {
                    Text(.Setting.optimizeDatabase)
                    if viewModel.isVacuuming {
                        Spacer()
                        ProgressView()
                            .controlSize(.regular)
                    }
                }
            }
            .disabled(viewModel.isVacuuming)

            Text(.Setting.optimizationDesc)
                .padding(2)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(.Setting.optimization)
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
                    Text(.Setting.bundleMode)
                    Text(.Setting.bundleModeDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }.controlSize(.regular)
        } header: {
            Text(.Setting.databaseMode)
        }
    }

    private var searchSection: some View {
        Section {
            Toggle(isOn: $viewModel.recordSearchHistory) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(.Setting.readingHistory)
                    Text(.Setting.readingHistoryDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.regular)
        } header: {
            Text(.Setting.history)
        }
    }

    private var libraryStorageSection: some View {
        Section {
            if !viewModel.isBundleMode {
                PathRow(label: .Setting.databaseFiles, path: viewModel.databaseFilesPath)
                PathRow(label: .Setting.archiveFiles, path: viewModel.archiveFilesPath)
            }

            #if os(macOS)
            HStack(spacing: 8) { libraryButtons }
            #else
            libraryButtons
            #endif

            if !viewModel.isBundleMode && viewModel.hasBundledData {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        viewModel.cleanupBundledData()
                    } label: {
                        Text(.Setting.cleanupDownloadedDataBundleMode)
                    }
                    .foregroundColor(.red)

                    Text(.Setting.cleanupDownloadedDataBundleModeDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(.Setting.libraryStorage)
        }
    }

    private var annotationsSection: some View {
        Section {
            Toggle(isOn: $viewModel.hideMissingBookAnnotations) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(.Setting.hideMissingBookAnnotations)
                    Text(.Setting.hideMissingBookAnnotationsDesc)
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
                    Text(.Setting.useCloudKit)
                    Text(.Setting.useCloudKitDesc)
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
                        Text(.Setting.crossPlatformSync)
                        Text(.Setting.crossPlatformSyncDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .controlSize(.regular)

                #if DEBUG
                TextField(String(localized: .Setting.debugWorkerURL), text: Binding(
                    get: { viewModel.customWorkerURL },
                    set: { viewModel.setCustomWorkerURL($0) }
                ))
                .font(.caption)
                .controlSize(.regular)
                #endif
            }

            if !viewModel.useICloud {
                PathRow(label: .Setting.currentPath, path: viewModel.annotationsPath)
            }

            #if os(macOS)
            HStack { actionButtons }
                .padding(.top, 4)
            #else
            actionButtons
            #endif
        } header: {
            Text(.Setting.annotationsAndSearchResults)
        }
    }

    @ViewBuilder
    private var libraryButtons: some View {
        Button {
            viewModel.chooseLibraryFolder()
        } label: {
            Text(.Setting.chooseLibraryFolder)
        }

        Button {
            viewModel.setBundleMode(true)
        } label: {
            Text(.Setting.switchToBundleMode)
        }
        .disabled(viewModel.isBundleMode)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            viewModel.chooseAnnotationsFolder()
        } label: {
            Text(.Setting.chooseAnnotationsFolder)
        }
        .disabled(viewModel.useICloud)

        Button {
            viewModel.resetCloudKitToken()
        } label: {
            Text(.Setting.reSynchroniseAllData)
        }
        .foregroundColor(.red)
        .disabled(!viewModel.useICloud)
    }

    @ViewBuilder
    private var collisionAlertButtons: some View {
        Button {
            viewModel.resolveCollision(.keepDestination)
        } label: {
            Text(.Setting.keepExistingDeleteOld)
        }
        Button(role: .destructive) {
            viewModel.resolveCollision(.overwriteDestination)
        } label: {
            Text(.Setting.overwriteExisting)
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
                    Text(.Setting.applicationUpdate)
                    Text(.Setting.checkAtStart)
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
                        Text(.Setting.libraryUpdate)
                        Text(.Setting.semiAnnualCheck)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(.Setting.biAnnualRoutineCheckDesc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .controlSize(.regular)
            }
        } header: {
            Text(.Setting.updates)
        }
    }

    private var downloadsSection: some View {
        Section {
            HStack(spacing: 8) {
                Button {
                    viewModel.openFullLibraryDownload()
                } label: {
                    Text(.Setting.downloadFullLibraryGoogleDrive)
                }
                #if os(macOS)
                Button {
                    viewModel.openSelectiveDownload()
                } label: {
                    Text(.Setting.downloadSelectiveLibrary)
                }
                #endif
            }
            Label {
                Text(.Setting.fullLibraryBrowserDesc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.accentColor)
            }
        } header: {
            Text(.Setting.downloads)
        }
    }
}

// MARK: - Helpers

private struct PathRow: View {
    let label: LocalizedStringResource
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
