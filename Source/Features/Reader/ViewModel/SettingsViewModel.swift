//
//  SettingsViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 21/07/26.
//

import SQLite3
import SwiftUI

final class SettingsViewModel: ObservableObject {
    static var shared: SettingsViewModel = .init()
    @Published var isBundleMode: Bool = AppConfig.isUsingBundleMode
    @Published var databaseFilesPath: String = "N/A"
    @Published var archiveFilesPath: String = "N/A"
    @Published var annotationsPath: String = "N/A"
    @Published var useICloud: Bool = AppConfig.useICloud
    @Published var useCrossPlatformSync: Bool = AppConfig.useCrossPlatformSync
    @Published var customWorkerURL: String = AppConfig.customWorkerURL
    @Published var isProcessingICloud = false
    @Published var showCollisionAlert = false
    @Published var hasBundledData: Bool = false
    @Published var hasPendingVacuum: Bool = false
    @Published var isVacuuming: Bool = false
    @Published var enableAutoCoreVersionCheck: Bool = true

    @AppStorage("hideMissingBookAnnotations") var hideMissingBookAnnotations: Bool = false
    @AppStorage("useDefaultTheme") var useDefaultTheme: Bool = false
    @AppStorage("recordSearchHistory") var recordSearchHistory: Bool = true

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
        useCrossPlatformSync = AppConfig.useCrossPlatformSync
        customWorkerURL = AppConfig.customWorkerURL
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
            shouldTerminateOnCancel: false,
            validate: DatabaseManager.validateDatabaseFolder
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
                            title: String(localized: "errorFolderAnnotations"),
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
            shouldTerminateOnCancel: false,
            validate: DatabaseManager.validateDatabaseFolder
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

    func setCustomWorkerURL(_ url: String) {
        customWorkerURL = url
        AppConfig.customWorkerURL = url
    }

    func setCrossPlatformSync(_ enabled: Bool) {
        useCrossPlatformSync = enabled
        SettingsActions.setUseCrossPlatformSync(enabled)
    }

    func setICloud(_ enabled: Bool) {
        if enabled {
            isProcessingICloud = true
            AppConfig.setUseICloud(true, resolution: .ask) { [weak self] error in
                guard let self else { return }
                self.isProcessingICloud = false

                if let error {
                    self.useICloud = false // rollback
                    ReusableFunc.showAlert(
                        title: String(localized: "errorICloud"),
                        message: error.localizedDescription
                    )
                }
                self.refreshPaths()
            }
        } else {
            // Must choose folder before disabling
            chooseAnnotationsFolder { [weak self] success in
                guard let self = self else { return }
                if success {
                    self.isProcessingICloud = true
                    AppConfig.setUseICloud(false, resolution: .ask) { [weak self] error in
                        guard let self = self else { return }
                        self.isProcessingICloud = false
                        if let error {
                            self.useICloud = true // rollback
                            ReusableFunc.showAlert(
                                title: String(localized: "errorICloud"),
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
            title: String(localized: "success"),
            message: String(localized: "CloudKit token has been reset. Full sync will start.")
        )
    }

    func resolveCollision(_ resolution: AppConfig.MigrationResolution) {
        guard let action = pendingCollisionAction else { return }

        switch action {
        case .moveFolder(let url):
            if resolution == .ask {
                pendingCollisionAction = nil
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
                            title: String(localized: "errorFolderAnnotations"),
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
