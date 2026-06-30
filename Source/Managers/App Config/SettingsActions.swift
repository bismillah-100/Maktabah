//
//  SettingsActions.swift
//  Maktabah
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif
import Foundation

enum SettingsActions {
    private static let fullLibraryDownloadURL =
        "https://drive.google.com/file/d/1lAinUQ9Eh_W4_4r3MNfX84Ee3AOCVt_B/view?usp=share_link"
    #if os(macOS)
    private static var coreDownloadModal: CoreDownloadModalCenter?
    #elseif os(iOS)
    private static var documentPickerCoordinator: DocumentPickerCoordinator?
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
        
        if let retryURL = retryURL {
            processURL(retryURL)
            return
        }

        #if os(macOS)
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("personalFolder", comment: "")
        panel.prompt = NSLocalizedString("Choose Folder", comment: "")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.level = .floating

        let response = panel.runModal()

        if response == .OK, let url = panel.url {
            processURL(url)
        } else {
            onCompletion(nil)
        }
        #else
        let showPicker = {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            picker.allowsMultipleSelection = false
            
            documentPickerCoordinator = DocumentPickerCoordinator(onPick: { url in
                processURL(url)
                documentPickerCoordinator = nil
            }, onCancel: {
                onCompletion(nil)
                documentPickerCoordinator = nil
            })
            picker.delegate = documentPickerCoordinator
            
            ReusableFunc.getTopViewController()?.present(picker, animated: true)
        }

        let alert = UIAlertController(
            title: NSLocalizedString("personalFolder", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("Choose Folder", comment: ""), style: .default) { _ in
            showPicker()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            onCompletion(nil)
        })
        ReusableFunc.getTopViewController()?.present(alert, animated: true)
        #endif
    }

    static func selectLibraryFolder(
        showSuccessAlert: Bool,
        shouldTerminateOnCancel: Bool,
        onCompletion: ((Bool) -> Void)? = nil
    ) -> Bool {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("appNeedAccess", comment: "")
        panel.prompt = NSLocalizedString("Choose Folder", comment: "")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.level = .floating

        let response = panel.runModal()

        if response == .OK, let url = panel.url {
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
        let showPicker = {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            picker.allowsMultipleSelection = false
            
            documentPickerCoordinator = DocumentPickerCoordinator(onPick: { url in
                let success = performLibraryFolderMigration(url: url, showSuccessAlert: showSuccessAlert)
                onCompletion?(success)
                documentPickerCoordinator = nil
            }, onCancel: {
                onCompletion?(false)
                documentPickerCoordinator = nil
            })
            picker.delegate = documentPickerCoordinator
            
            ReusableFunc.getTopViewController()?.present(picker, animated: true)
        }

        let alert = UIAlertController(
            title: NSLocalizedString("appNeedAccess", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("Choose Folder", comment: ""), style: .default) { _ in
            showPicker()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            if shouldTerminateOnCancel {
                // On iOS we don't usually terminate the app, but we can show an alert
                showAccessNeededAlert()
            }
            onCompletion?(false)
        })
        ReusableFunc.getTopViewController()?.present(alert, animated: true)
        return true // On iOS, we return true as we've shown the alert/picker
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
            title: NSLocalizedString(
                "AccessNeeded",
                comment: "Alert Memilih Folder Master"
            ),
            message: NSLocalizedString(
                "FolderMasterPenjelasan",
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
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("personalFolder", comment: "")
        panel.prompt = NSLocalizedString("Choose Folder", comment: "")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.level = .floating

        let response = panel.runModal()

        if response == .OK, let url = panel.url {
            onCompletion(url)
        } else {
            onCompletion(nil)
        }
        #else
        let showPicker = {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            picker.allowsMultipleSelection = false
            
            documentPickerCoordinator = DocumentPickerCoordinator(onPick: { url in
                onCompletion(url)
                documentPickerCoordinator = nil
            }, onCancel: {
                onCompletion(nil)
                documentPickerCoordinator = nil
            })
            picker.delegate = documentPickerCoordinator
            
            ReusableFunc.getTopViewController()?.present(picker, animated: true)
        }

        let alert = UIAlertController(
            title: NSLocalizedString("personalFolder", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("Choose Folder", comment: ""), style: .default) { _ in
            showPicker()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            onCompletion(nil)
        })
        ReusableFunc.getTopViewController()?.present(alert, animated: true)
        #endif
    }

    private static func changeAnnotationsBaseUrl(to newURL: URL, resolution: AppConfig.MigrationResolution) throws {
        let fm = FileManager.default

        let oldURL = AppConfig.folder(
            for: AppConfig.annotationsAndResultsFolder
        )

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: newURL.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            throw StorageError.invalidDirectory
        }

        guard newURL.startAccessingSecurityScopedResource() else {
            throw StorageError.cannotAccessSecurityScope
        }

        defer {
            newURL.stopAccessingSecurityScopedResource()
        }

        AnnotationManager.shared.disconnect()
        ResultsHandler.shared.disconnect()

        if let oldURL, fm.fileExists(atPath: oldURL.path) {
            let filesToMove = ["Annotations.sqlite", "SearchResults.sqlite", "Annotations.sqlite-wal", "Annotations.sqlite-shm", "SearchResults.sqlite-wal", "SearchResults.sqlite-shm"]

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

        AppConfig.saveBookmark(
            url: newURL,
            key: AppConfig.annotationsAndResultsFolder
        )

        try AnnotationManager.shared.setupAnnotations(at: newURL)
        try ResultsHandler.shared.setupResultDatabase(at: newURL)
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
