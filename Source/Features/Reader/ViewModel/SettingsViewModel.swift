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
        let fm = FileManager.default
        let paths = [AppConfig.archiveCachePath, AppConfig.coreDatabasePath].compactMap { $0 }
        for path in paths {
            if let items = try? fm.contentsOfDirectory(atPath: path),
               items.contains(where: { $0.hasSuffix(".sqlite") || $0 == "index.json" || $0 == "integration_cache" || $0 == "Books" })
            {
                hasBundledData = true
                return
            }
        }
        hasBundledData = false
    }

    func cleanupBundledData() {
        let fm = FileManager.default
        let paths = Set([AppConfig.archiveCachePath, AppConfig.coreDatabasePath].compactMap { $0 })
        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                let items = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                for item in items {
                    try fm.removeItem(at: item)
                }
            } catch {
                #if DEBUG
                print("Failed to cleanup bundled data at \(path):", error)
                #endif
            }
        }
        refreshPaths()
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
                guard let self else {
                    onCompletion?(false)
                    return
                }
                switch result {
                case .success:
                    self.refreshPaths()
                    onCompletion?(true)
                case let .failure(error):
                    if let storageError = error as? StorageError,
                       case let .collision(url) = storageError, let safeUrl = url
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
                isProcessingICloud = false

                if let error {
                    useICloud = false // rollback
                    ReusableFunc.showAlert(
                        title: String(localized: "errorICloud"),
                        message: error.localizedDescription
                    )
                }
                refreshPaths()
            }
        } else {
            // Must choose folder before disabling
            chooseAnnotationsFolder { [weak self] success in
                guard let self else { return }
                if success {
                    isProcessingICloud = true
                    AppConfig.setUseICloud(false, resolution: .ask) { [weak self] error in
                        guard let self else { return }
                        isProcessingICloud = false
                        if let error {
                            useICloud = true // rollback
                            ReusableFunc.showAlert(
                                title: String(localized: "errorICloud"),
                                message: error.localizedDescription
                            )
                        }
                        refreshPaths()
                    }
                } else {
                    // Revert toggle if folder selection was cancelled
                    useICloud = true
                    refreshPaths()
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
        case let .moveFolder(url):
            if resolution == .ask {
                pendingCollisionAction = nil
                return
            }

            SettingsActions.chooseAnnotationsAndResultsFolder(resolution: resolution, retryURL: url) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pendingCollisionAction = nil
                    switch result {
                    case .success:
                        self.refreshPaths()
                    case let .failure(error):
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
