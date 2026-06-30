//
//  BootstrapManager.swift
//  Maktabah-iOS
//
//  Created by Ghoys Mawahib on 03/05/26.
//

import SwiftUI

// MARK: - Bootstrap

@MainActor
@Observable
final class iOSBootstrapManager {
    var isReady = false
    var coreDownloadState = CoreDownloadProgressState()
    var isChecking = true
    var isUpdating = false
    var isCancellable = false

    // Core update alert state
    var showCoreUpdateAlert = false
    var availableCoreVersion: String?

    private let downloader = CoreDatabaseDownloader()
    private var didPrepare = false

    func prepareIfNeeded() {
        guard !didPrepare else { return }
        didPrepare = true

        if AppConfig.hasCustomDatabaseFolder() {
            if let mainPath = AppConfig.mainDatabasePath, FileManager.default.fileExists(atPath: mainPath) {
                finishSetup()
                return
            } else {
                AppConfig.resetCustomModeKey()
            }
        }

        if downloader.areCoreFilesReady() {
            finishSetup()
            return
        }

        downloader.fetchTotalDownloadSize { [weak self] size in
            Task { @MainActor in
                if size > 0 {
                    let mb = Double(size) / 1_048_576
                    self?.coreDownloadState.totalSizeString = String(format: "%.1f MB", mb)
                }
                self?.isChecking = false
                self?.coreDownloadState.phase = .confirmation
            }
        }
    }

    func startDownload() {
        isChecking = false
        coreDownloadState.phase = .downloading
        coreDownloadState.progress = 0
        coreDownloadState.detail = ""

        downloader.startDownload(
            onProgress: { [weak self] progress, detail in
                self?.coreDownloadState.progress = progress
                self?.coreDownloadState.detail = detail
            },
            onCompletion: { [weak self] error in
                guard let self else { return }
                if let error {
                    coreDownloadState.phase = .error(error.localizedDescription)
                    coreDownloadState.progress = 0
                    return
                }
                finishSetup()
            }
        )
    }

    private func finishSetup() {
        DatabaseManager.shared.reloadConnectionAndLibrary()
        isChecking = false
        isReady = true

        // Check for core database updates (non-blocking, throttled 6 months)
        checkCoreDatabaseUpdate()
    }

    private func checkCoreDatabaseUpdate() {
        // Hanya check jika di bundle mode dan core files sudah ada
        guard AppConfig.isUsingBundleMode, downloader.areCoreFilesReady() else { return }

        Task.detached(priority: .low) { [weak self] in
            let result = await CoreUpdateChecker.checkAsync()

            guard case .updateAvailable(let newVersion) = result else { return }

            await MainActor.run { [weak self] in
                self?.availableCoreVersion = newVersion
                self?.showCoreUpdateAlert = true
            }
        }
    }

    func performCoreUpdate() {
        guard let version = availableCoreVersion else { return }
        isUpdating = true

        // Reset state untuk download
        coreDownloadState.phase = .downloading
        coreDownloadState.progress = 0
        coreDownloadState.detail = ""

        downloader.updateToVersion(
            version,
            onProgress: { [weak self] progress, detail in
                self?.coreDownloadState.progress = progress
                self?.coreDownloadState.detail = detail
            },
            onCompletion: { [weak self] error in
                guard let self else { return }

                if let error {
                    coreDownloadState.phase = .error(error.localizedDescription)
                    coreDownloadState.progress = 0
                    showCoreUpdateAlert = false
                    isUpdating = false
                    return
                }

                // Berhasil - reload database
                DatabaseManager.shared.reloadConnectionAndLibrary()
                showCoreUpdateAlert = false
                availableCoreVersion = nil
                isUpdating = false
            }
        )
    }

    func reloadLibrary(isCancellable: Bool = false) {
        self.isCancellable = isCancellable
        didPrepare = false
        isReady = false
        prepareIfNeeded()
    }

    func cancelDownload() {
        SettingsActions.cancelBundleModeSwitch()
        isChecking = false
        isReady = true
    }

    func chooseLibraryFolder() {
        _ = SettingsActions.selectLibraryFolder(showSuccessAlert: false, shouldTerminateOnCancel: false) { [weak self] success in
            if success {
                Task { @MainActor in
                    self?.finishSetup()
                }
            }
        }
    }
}
