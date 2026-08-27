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
            if let customPath = AppConfig.databaseFilesPath {
                let customUrl = URL(fileURLWithPath: customPath)
                let parentUrl = customUrl.deletingLastPathComponent()
                if DatabaseManager.validateDatabaseFolder(parentUrl) == nil {
                    finishSetup()
                    return
                } else {
                    AppConfig.resetCustomModeKey()
                }
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
        resetDownloadState()

        downloader.startDownload(
            onProgress: makeProgressHandler(),
            onCompletion: { [weak self] error in
                guard let self else { return }
                if let error {
                    handleDownloadError(error)
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

            guard case let .updateAvailable(newVersion) = result else { return }

            await MainActor.run { [weak self] in
                self?.availableCoreVersion = newVersion
                self?.showCoreUpdateAlert = true
            }
        }
    }

    func performCoreUpdate() {
        guard let version = availableCoreVersion else { return }
        isUpdating = true
        resetDownloadState()

        downloader.updateToVersion(
            version,
            onProgress: makeProgressHandler(),
            onCompletion: { [weak self] error in
                guard let self else { return }

                if let error {
                    handleDownloadError(error)
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

    private func resetDownloadState() {
        coreDownloadState.phase = .downloading
        coreDownloadState.progress = 0
        coreDownloadState.detail = ""
    }

    private func makeProgressHandler() -> (Double, String) -> Void {
        { [weak self] progress, detail in
            self?.handleDownloadProgress(progress: progress, detail: detail)
        }
    }

    private func handleDownloadProgress(progress: Double, detail: String) {
        coreDownloadState.progress = progress
        coreDownloadState.detail = detail
    }

    private func handleDownloadError(_ error: Error) {
        coreDownloadState.phase = .error(error.localizedDescription)
        coreDownloadState.progress = 0
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
        SettingsActions.selectLibraryFolder(
            showSuccessAlert: false,
            shouldTerminateOnCancel: false,
            onCompletion: { [weak self] success in
                if success {
                    Task { @MainActor in
                        self?.finishSetup()
                    }
                }
            }
        )
    }
}
