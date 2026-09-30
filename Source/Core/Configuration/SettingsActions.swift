//
//  SettingsActions.swift
//  Maktabah
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import UniformTypeIdentifiers
#endif

enum SettingsActions {
    private static let fullLibraryDownloadURL =
        "https://drive.google.com/file/d/1lAinUQ9Eh_W4_4r3MNfX84Ee3AOCVt_B/view?usp=share_link"
    #if os(macOS)
    private static var coreDownloadModal: CoreDownloadModalCenter?
    #elseif os(iOS)
    private static var documentPickerCoordinator: DocumentPickerCoordinator?
    #endif

    #if os(macOS)
    private static func presentFolderOpenPanel(
        message: String = .init(localized: "personalFolder"),
        prompt: String = .init(localized: "Choose Folder"),
        canCreateDirectories: Bool = true
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = canCreateDirectories
        panel.allowsMultipleSelection = false
        panel.level = .floating

        let response = panel.runModal()
        return (response == .OK) ? panel.url : nil
    }

    #elseif os(iOS)
    private static func presentFolderPickerWithAlert(
        title: String = .init(localized: "personalFolder"),
        chooseTitle: String = .init(localized: "Choose Folder"),
        cancelTitle: String = .init(localized: "Cancel"),
        onPick: @escaping (URL) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        let showPicker = {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            picker.allowsMultipleSelection = false

            documentPickerCoordinator = DocumentPickerCoordinator(onPick: { url in
                onPick(url)
                documentPickerCoordinator = nil
            }, onCancel: {
                onCancel?()
                documentPickerCoordinator = nil
            })
            picker.delegate = documentPickerCoordinator

            ReusableFunc.getTopViewController()?.present(picker, animated: true)
        }

        let alert = UIAlertController(
            title: title,
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: chooseTitle, style: .default) { _ in
            showPicker()
        })
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in
            onCancel?()
        })
        ReusableFunc.getTopViewController()?.present(alert, animated: true)
    }
    #endif

    static func chooseAnnotationsAndResultsFolder(resolution: AppConfig.MigrationResolution = .ask, retryURL: URL? = nil, onCompletion: @escaping (Result<URL, Error>?) -> Void) {
        let processURL = { (url: URL) in
            do {
                try changeAnnotationsBaseUrl(to: url, resolution: resolution)
                AnnotationManager.shared.buildAnnotationTree()
                onCompletion(.success(url))
            } catch {
                onCompletion(.failure(error))
            }
        }

        if let retryURL {
            processURL(retryURL)
            return
        }

        #if os(macOS)
        if let url = presentFolderOpenPanel() {
            processURL(url)
        } else {
            onCompletion(nil)
        }
        #else
        presentFolderPickerWithAlert(
            onPick: { url in processURL(url) },
            onCancel: { onCompletion(nil) }
        )
        #endif
    }

    @discardableResult
    static func selectLibraryFolder(
        showSuccessAlert: Bool,
        shouldTerminateOnCancel: Bool,
        validate: ((URL) -> Error?)? = nil,
        onCompletion: ((Bool) -> Void)? = nil
    ) -> Bool {
        #if os(macOS)
        if let url = presentFolderOpenPanel(
            message: .init(localized: "appNeedAccess"),
            canCreateDirectories: false
        ) {
            if let error = validate?(url) {
                ReusableFunc.showAlert(title: "Error", message: error.localizedDescription)
                onCompletion?(false)
                return false
            }
            let success = performLibraryFolderMigration(url: url, showSuccessAlert: showSuccessAlert)
            onCompletion?(success)
            return success
        }

        if shouldTerminateOnCancel {
            showAccessNeededAlert()
            NSApp.terminate(nil)
        }

        onCompletion?(false)
        return false
        #else
        presentFolderPickerWithAlert(
            title: .init(localized: "appNeedAccess"),
            onPick: { url in
                if let error = validate?(url) {
                    ReusableFunc.showAlert(title: "Error", message: error.localizedDescription)
                    onCompletion?(false)
                    return
                }
                let success = performLibraryFolderMigration(url: url, showSuccessAlert: showSuccessAlert)
                onCompletion?(success)
            },
            onCancel: {
                if shouldTerminateOnCancel {
                    showAccessNeededAlert()
                }
                onCompletion?(false)
            }
        )
        return true
        #endif
    }

    private static func performLibraryFolderMigration(url: URL, showSuccessAlert: Bool) -> Bool {
        let migrateSuccess = AppConfig.migrateToCustomMode(folderUrl: url)

        if !migrateSuccess {
            AppConfig.resetCustomModeKey()
            ReusableFunc.showAlert(
                title: String(localized: "migrationFailed"),
                message: String(localized: "migrationFailedInfo")
            )
            return false
        }

        DatabaseManager.shared.reloadConnectionAndLibrary()

        FtsMigrationManager.shared.checkNeedsMigration()

        if showSuccessAlert {
            ReusableFunc.showAlert(
                title: "masterFolderRenewed".localized,
                message: "masterFolderRenewedInfo".localized
            )
        }

        #if DEBUG
        print("Custom folder selected and migrated: \(url.path)")
        #endif
        return true
    }

    private static func showAccessNeededAlert() {
        ReusableFunc.showAlert(
            title: .init(
                localized: "AccessNeeded",
                comment: "Alert Memilih Folder Master"
            ),
            message: .init(
                localized: "FolderMasterPenjelasan",
                comment: "Informasi Alert Memilih Folder Master"
            )
        )
    }

    static var pendingRestoreAction: (() -> Void)?

    static func cancelBundleModeSwitch() {
        pendingRestoreAction?()
        pendingRestoreAction = nil
        SettingsViewModel.shared.refreshPaths()
    }

    static func switchToBundleMode(onCompletion: (() -> Void)? = nil) {
        let wasBundleMode = AppConfig.isUsingBundleMode
        let previousCustomBookmark = UserDefaults.standard.data(
            forKey: AppConfig.customDatabaseFolderKey
        )

        AppConfig.migrateToBundleMode()

        let finishSetup = {
            DatabaseManager.shared.reloadConnectionAndLibrary()
            FtsMigrationManager.shared.checkNeedsMigration()
        }

        let restorePreviousMode = {
            if let previousCustomBookmark {
                UserDefaults.standard.set(
                    previousCustomBookmark,
                    forKey: AppConfig.customDatabaseFolderKey
                )
                AppConfig.isUsingBundleMode = false
            } else {
                AppConfig.isUsingBundleMode = wasBundleMode
            }
        }

        let downloader = CoreDatabaseDownloader()
        if !downloader.areBundleCoreFilesReady() {
            #if os(macOS)
            let modal = CoreDownloadModalCenter(downloader: downloader)
            coreDownloadModal = modal
            modal.runNonBlocking { result in
                switch result {
                case .downloaded:
                    finishSetup()
                case .choseFolder:
                    break
                case .quit:
                    restorePreviousMode()
                }
                onCompletion?()
                coreDownloadModal = nil
            }
            #else
            pendingRestoreAction = restorePreviousMode
            NotificationCenter.default.post(
                name: .requireCoreDownload, object: nil,
                userInfo: ["isCancellable": true]
            )
            onCompletion?()
            #endif
        } else {
            finishSetup()
            onCompletion?()
        }
    }

    #if os(macOS)
    static func showFtsMigrationModal(archiveId: Int? = nil, onDismiss: (() -> Void)? = nil) {
        var window: NSWindow?
        let view = FtsMigrationProgressView(
            onCancel: {
                window?.close()
                window = nil
                onDismiss?()
            },
            onUpdate: {
                if let archiveId {
                    try await FtsMigrationManager.shared.migrateArchive(archiveId: archiveId)
                } else {
                    try await FtsMigrationManager.shared.performMigration()
                }
                await MainActor.run { [window] in
                    window?.close()
                    onDismiss?()
                }
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.autoresizingMask = [.width, .height]

        let fittingSize = hostingView.fittingSize
        let windowWidth = max(420, fittingSize.width)
        let windowHeight = max(290, fittingSize.height)

        let w = ReusableFunc.makeTitlelessWindow(
            contentView: hostingView,
            size: .init(width: windowWidth, height: windowHeight)
        )
        w.center()
        w.level = .floating
        window = w

        w.makeKeyAndOrderFront(nil)
    }

    static func downloadSelectiveLibrary() {
        BulkDownloadModalCenter.shared.presentModal()
    }
    #endif

    static func openFullLibraryDownloadURL() {
        guard let url = URL(string: fullLibraryDownloadURL) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    static func selectLocalFolderForICloudDisable(onCompletion: @escaping (URL?) -> Void) {
        #if os(macOS)
        onCompletion(presentFolderOpenPanel())
        #else
        presentFolderPickerWithAlert(
            onPick: { url in onCompletion(url) },
            onCancel: { onCompletion(nil) }
        )
        #endif
    }

    private static func changeAnnotationsBaseUrl(to newURL: URL, resolution: AppConfig.MigrationResolution) throws {
        let fm = FileManager.default
        let oldURL = AppConfig.folder(for: AppConfig.annotationsAndResultsFolder)

        try validateNewDirectoryURL(newURL, fm: fm)

        guard newURL.startAccessingSecurityScopedResource() else {
            throw StorageError.cannotAccessSecurityScope
        }
        defer {
            newURL.stopAccessingSecurityScopedResource()
        }

        AnnotationManager.shared.disconnect()
        ResultsHandler.shared.disconnect()

        if let oldURL, fm.fileExists(atPath: oldURL.path) {
            try migrateDatabaseFiles(from: oldURL, to: newURL, resolution: resolution, fm: fm)
        }

        AppConfig.saveBookmark(
            url: newURL,
            key: AppConfig.annotationsAndResultsFolder
        )

        try AnnotationManager.shared.setupAnnotations(at: newURL)
        try ResultsHandler.shared.setupResultDatabase(at: newURL)
    }

    private static func validateNewDirectoryURL(_ newURL: URL, fm: FileManager) throws {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: newURL.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            throw StorageError.invalidDirectory
        }
    }

    private static func migrateDatabaseFiles(
        from oldURL: URL,
        to newURL: URL,
        resolution: AppConfig.MigrationResolution,
        fm: FileManager
    ) throws {
        let filesToMove = [
            "Annotations.sqlite", "SearchResults.sqlite", "History.sqlite",
            "Annotations.sqlite-wal", "Annotations.sqlite-shm",
            "SearchResults.sqlite-wal", "SearchResults.sqlite-shm",
            "History.sqlite-wal", "History.sqlite-shm",
        ]

        // Phase 1: Check for collisions
        if resolution == .ask {
            for fileName in filesToMove {
                let sourceFile = oldURL.appendingPathComponent(fileName)
                guard fm.fileExists(atPath: sourceFile.path) else { continue }

                let destFile = newURL.appendingPathComponent(fileName)
                if fm.fileExists(atPath: destFile.path) {
                    throw StorageError.collision(newURL)
                }
            }
        }

        // Phase 2: Execute migration
        for fileName in filesToMove {
            let sourceFile = oldURL.appendingPathComponent(fileName)
            let destFile = newURL.appendingPathComponent(fileName)

            guard fm.fileExists(atPath: sourceFile.path) else { continue }

            if fm.fileExists(atPath: destFile.path) {
                if resolution == .keepDestination {
                    try? fm.removeItem(at: sourceFile)
                    continue
                } else if resolution == .overwriteDestination {
                    try? fm.removeItem(at: destFile)
                }
            }

            try fm.moveItem(at: sourceFile, to: destFile)
        }
    }

    static func setUseCrossPlatformSync(_ use: Bool) {
        AppConfig.useCrossPlatformSync = use
        if use {
            CloudKitCoreManager.shared.notifyWorkerToSync()
        }
    }
}

#if os(iOS)
class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    var onPick: (URL) -> Void
    var onCancel: (() -> Void)?

    init(onPick: @escaping (URL) -> Void, onCancel: (() -> Void)? = nil) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            onCancel?()
            return
        }

        // Start accessing the security-scoped resource
        if url.startAccessingSecurityScopedResource() {
            onPick(url)
        } else {
            ReusableFunc.showAlert(title: "Access Denied", message: "Cannot access the selected folder.")
            onCancel?()
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onCancel?()
    }
}
#endif
