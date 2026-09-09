//
//  CoreDatabaseDownloader.swift
//  Maktabah
//
//  Mengelola download main.sqlite + special.sqlite dari GitHub Releases
//  ke ~/Library/Application Support/Maktabah/Caches/
//

import Observation
import SwiftUI
import Synchronization

// MARK: - CoreFile

enum CoreFile: CaseIterable {
    case main
    case special

    /// Nama file hasil dekompresi yang disimpan ke disk
    var filename: String {
        switch self {
        case .main: "main.sqlite"
        case .special: "special.sqlite"
        }
    }

    /// Nama file asset di GitHub Release (selalu .zst)
    var releaseFilename: String {
        filename + ".zst"
    }
}

// MARK: - CoreDownloadError

enum CoreDownloadError: LocalizedError {
    case invalidBaseURL
    case destinationUnavailable
    case invalidResponse
    case httpStatus(file: String, statusCode: Int)
    case downloadFailed(file: String)
    case decompressionFailed(file: String, reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            String(localized: "core.error.invalidBaseURL", defaultValue: "Invalid download URL. Please check your configuration.")
        case .destinationUnavailable:
            String(localized: "core.error.destinationUnavailable", defaultValue: "The destination folder could not be created.")
        case .invalidResponse:
            String(localized: "core.error.invalidResponse", defaultValue: "Invalid server response.")
        case let .httpStatus(file, code):
            String(localized: "core.error.httpStatus", defaultValue: "Failed to download “\(file)” (HTTP \(code)).")
        case let .downloadFailed(file):
            String(localized: "core.error.downloadFailed", defaultValue: "File “\(file)” is incomplete after download.")
        case let .decompressionFailed(file, reason):
            String(localized: "core.error.decompressionFailed", defaultValue: "Failed to decompress “\(file)”: \(reason).")
        case .cancelled:
            String(localized: "core.error.cancelled", defaultValue: "Download cancelled.")
        }
    }
}

// MARK: - Download Event

enum DownloadEvent {
    case progress(bytesWritten: Int64, totalBytes: Int64, fraction: Double)
    case success(tempURL: URL)
}

// MARK: - CoreDatabaseDownloader

final class CoreDatabaseDownloader: NSObject, Sendable {
    private nonisolated(unsafe) let fileManager = FileManager.default

    typealias ProgressHandler = @Sendable (_ progress: Double, _ detail: String) -> Void
    typealias CompletionHandler = @Sendable (_ error: Error?) -> Void

    override init() {}

    // MARK: - Check

    func areCoreFilesReady() -> Bool {
        CoreFile.allCases.allSatisfy { fileExistsAndHasSize(for: $0) }
    }

    func areBundleCoreFilesReady() -> Bool {
        CoreFile.allCases.allSatisfy { fileExistsAndHasSize(for: $0, path: AppConfig.archiveCachePath) }
    }

    // MARK: - Total Size (Async)

    func fetchTotalDownloadSize() async -> Int64 {
        let missing = CoreFile.allCases.filter { !self.fileExistsAndHasSize(for: $0) }
        guard !missing.isEmpty else { return 0 }

        guard let baseURL = AppConfig.coreReleaseBaseURL,
              let tag = AppConfig.coreReleaseTag
        else { return 0 }

        let fileURLs = missing.map { file in
            baseURL
                .appendingPathComponent(tag)
                .appendingPathComponent(file.releaseFilename)
        }

        let fileSizes = await fetchRemoteFileSizes(fileURLs: fileURLs)
        return fileSizes.reduce(0, +)
    }

    private func fetchRemoteFileSizes(fileURLs: [URL]) async -> [Int64] {
        await withTaskGroup(of: (Int, Int64).self) { group in
            for (index, url) in fileURLs.enumerated() {
                group.addTask {
                    var req = URLRequest(url: url)
                    req.httpMethod = "HEAD"
                    do {
                        let (_, response) = try await URLSession.shared.data(for: req)
                        let size = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) } ?? 0
                        return (index, size)
                    } catch {
                        return (index, 0)
                    }
                }
            }

            var sizes = [Int64](repeating: 0, count: fileURLs.count)
            for await (index, size) in group {
                sizes[index] = size
            }
            return sizes
        }
    }

    // MARK: - Version Handlers

    static func fetchLatestCoreVersion() async throws -> String {
        guard let url = AppConfig.coreVersionURL else {
            throw CoreDownloadError.invalidBaseURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CoreDownloadError.httpStatus(file: "version.txt", statusCode: code)
        }

        guard let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else {
            throw CoreDownloadError.downloadFailed(file: "version.txt")
        }
        return version
    }

    func fetchLatestCoreVersionSync() {
        guard let url = AppConfig.coreVersionURL else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let sem = DispatchSemaphore(value: 0)

        let resultVersion = Mutex<String?>(nil)

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { sem.signal() }
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
                  let data,
                  let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty
            else { return }

            resultVersion.withLock { $0 = version }
        }.resume()

        _ = sem.wait(timeout: .now() + 30)

        if let version = resultVersion.withLock({ $0 }) {
            UserDefaults.standard.set(version, forKey: AppConfig.coreReleaseTagKey)
        }
    }

    // MARK: - Download Execution

    func startDownload(onProgress: @escaping ProgressHandler, onCompletion: @escaping CompletionHandler) {
        Task.detached(priority: .userInitiated) {
            do {
                try await self.downloadMissingCoreFiles(onProgress: onProgress)
                await MainActor.run { onCompletion(nil) }
            } catch {
                await MainActor.run { onCompletion(error) }
            }
        }
    }

    private func downloadMissingCoreFiles(onProgress: @escaping ProgressHandler) async throws {
        let missing = CoreFile.allCases.filter { !fileExistsAndHasSize(for: $0) }
        guard !missing.isEmpty else { return }

        guard let baseURL = AppConfig.coreReleaseBaseURL, let tag = AppConfig.coreReleaseTag else {
            throw CoreDownloadError.invalidBaseURL
        }

        let fileURLs = missing.map { baseURL.appendingPathComponent(tag).appendingPathComponent($0.releaseFilename) }
        let fileSizes = await fetchRemoteFileSizes(fileURLs: fileURLs)
        let grandTotal = fileSizes.reduce(0, +)
        var cumulativeOffset: Int64 = 0

        for (i, (file, fileURL)) in zip(missing, fileURLs).enumerated() {
            let offsetAtStart = cumulativeOffset

            try await downloadSingleFile(file, from: fileURL) { bytesWritten, _, _ in
                let totalWritten = offsetAtStart + bytesWritten
                let combinedProgress: Double = grandTotal > 0
                    ? Double(totalWritten) / Double(grandTotal)
                    : (Double(i) + Double(bytesWritten) / max(1, Double(fileSizes[i]))) / Double(missing.count)

                let writtenMB = String(format: "%.1f", Double(totalWritten) / 1_048_576)
                let totalStr = grandTotal > 0 ? String(format: "%.1f MB", Double(grandTotal) / 1_048_576) : "? MB"

                Task { @MainActor in
                    onProgress(combinedProgress, "\(writtenMB) / \(totalStr)")
                }
            }

            cumulativeOffset += fileSizes[i] > 0 ? fileSizes[i] : 0
        }
    }

    // MARK: - AsyncStream Bridge for URLSession

    private func downloadStream(for url: URL) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            let delegate = CoreDownloadDelegate(continuation: continuation)
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 3600
            config.waitsForConnectivity = false

            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                session.invalidateAndCancel()
            }
            task.resume()
        }
    }

    private func downloadSingleFile(
        _ coreFile: CoreFile,
        from url: URL,
        onProgress: @escaping (_ bytesWritten: Int64, _ totalBytes: Int64, _ progress: Double) -> Void
    ) async throws {
        guard let destDir = AppConfig.coreDatabasePath else { throw CoreDownloadError.destinationUnavailable }
        let destURL = URL(fileURLWithPath: destDir).appendingPathComponent(coreFile.filename)
        var downloadedTempURL: URL?

        for try await event in downloadStream(for: url) {
            switch event {
            case let .progress(bytesWritten, totalBytes, progress):
                onProgress(bytesWritten, totalBytes, progress)
            case let .success(tempURL):
                downloadedTempURL = tempURL
            }
        }

        guard let tempURL = downloadedTempURL else { throw CoreDownloadError.downloadFailed(file: coreFile.filename) }
        defer { try? fileManager.removeItem(at: tempURL) }

        if url.pathExtension.lowercased() == "zst" {
            do {
                try ZstdDecompressor.decompressFile(from: tempURL, to: destURL)
            } catch {
                throw CoreDownloadError.decompressionFailed(file: coreFile.filename, reason: error.localizedDescription)
            }
        } else {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.moveItem(at: tempURL, to: destURL)
        }

        guard fileExistsAndHasSize(for: coreFile) else { throw CoreDownloadError.downloadFailed(file: coreFile.filename) }
    }

    // MARK: - Core Updater (version.txt + 6 month cache)

    func fetchIndexJSON(forceRefresh: Bool, onProgress: @escaping ProgressHandler) async throws {
        if forceRefresh {
            UserDefaults.standard.removeObject(forKey: "book_index_etag")
            UserDefaults.standard.removeObject(forKey: "book_index_last_modified")
        }

        guard let indexURL = AppConfig.bookIndexURL else { throw CoreDownloadError.invalidBaseURL }

        await MainActor.run { onProgress(0.1, "Checking index...") }
        let cache = BookDownloadIndexCache.shared
        let entries = try await cache.entries(indexURL: indexURL, urlSession: URLSession.shared, forceRefresh: forceRefresh)
        await MainActor.run { onProgress(1.0, "Index ready (\(entries.count) books)") }
    }

    func updateToVersion(_ newTag: String, onProgress: @escaping ProgressHandler, onCompletion: @escaping CompletionHandler) {
        purgeExistingCoreFiles()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await downloadMissingCoreFiles { progress, detail in
                    let adjustedProgress = progress * 0.45
                    Task { @MainActor in onProgress(adjustedProgress, "Core: \(detail)") }
                }

                await MainActor.run { onProgress(0.5, "Updating book index...") }

                try await fetchIndexJSON(forceRefresh: true) { idxProgress, idxDetail in
                    let adjustedProgress = 0.5 + (idxProgress * 0.45)
                    Task { @MainActor in onProgress(adjustedProgress, idxDetail) }
                }

                UserDefaults.standard.set(newTag, forKey: AppConfig.coreReleaseTagKey)
                await MainActor.run { onCompletion(nil) }
            } catch {
                await MainActor.run { onCompletion(error) }
            }
        }
    }

    private func purgeExistingCoreFiles() {
        for file in CoreFile.allCases {
            if let path = AppConfig.coreDatabasePath {
                let filePath = URL(fileURLWithPath: path).appendingPathComponent(file.filename).path
                try? FileManager.default.removeItem(atPath: filePath)
            }
        }
    }

    private func fileExistsAndHasSize(for coreFile: CoreFile, path: String? = nil) -> Bool {
        let dirPath = path == nil ? AppConfig.coreDatabasePath : path
        guard let dirPath else { return false }
        let filePath = URL(fileURLWithPath: dirPath).appendingPathComponent(coreFile.filename).path
        return fileManager.isNonEmptyFile(atPath: filePath)
    }
}

// MARK: - URLSession Delegate Stream Bridge

private final class CoreDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<DownloadEvent, Error>.Continuation
    private var httpError: Error?

    init(continuation: AsyncThrowingStream<DownloadEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        continuation.yield(.progress(bytesWritten: totalBytesWritten, totalBytes: totalBytesExpectedToWrite, fraction: progress))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            let filename = downloadTask.originalRequest?.url?.lastPathComponent ?? "?"
            httpError = CoreDownloadError.httpStatus(file: filename, statusCode: http.statusCode)
            continuation.finish(throwing: httpError)
            return
        }

        let tempDest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: tempDest)
            continuation.yield(.success(tempURL: tempDest))
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, httpError == nil {
            continuation.finish(throwing: error)
        }
    }
}

// MARK: - CoreDatabaseBootstrap

#if os(macOS)
enum CoreDatabaseBootstrap {
    static func run() {
        if AppConfig.hasCustomDatabaseFolder() {
            if let mainPath = AppConfig.mainDatabasePath, FileManager.default.fileExists(atPath: mainPath) {
                DatabaseManager.shared.setupFolders()
                return
            } else {
                AppConfig.resetCustomModeKey()
            }
        }

        let downloader = CoreDatabaseDownloader()
        if downloader.areCoreFilesReady() {
            DatabaseManager.shared.setupFolders()
            return
        }

        downloader.fetchLatestCoreVersionSync()
        MainActor.assumeIsolated {
            let modal = CoreDownloadModalCenter(downloader: downloader)
            modal.runBlocking()
            DatabaseManager.shared.setupFolders()
        }
    }
}

// MARK: - CoreDownloadModalCenter

enum CoreDownloadModalResult {
    case downloaded
    case choseFolder
    case quit
}

@MainActor
final class CoreDownloadModalCenter {
    private let downloader: CoreDatabaseDownloader
    private var window: NSWindow?
    private var progressState: CoreDownloadProgressState?
    private let fileManager = FileManager.default
    private var onCompletion: ((CoreDownloadModalResult) -> Void)?
    private weak var sheetParent: NSWindow?
    private var presentedAsSheet: Bool = false

    init(downloader: CoreDatabaseDownloader) {
        self.downloader = downloader
    }

    func runBlocking(onCompletion: ((CoreDownloadModalResult) -> Void)? = nil) {
        self.onCompletion = onCompletion
        presentedAsSheet = false
        sheetParent = nil
        showConfirmation()
    }

    func runNonBlocking(parentWindow: NSWindow? = nil, onCompletion: ((CoreDownloadModalResult) -> Void)? = nil) {
        self.onCompletion = onCompletion
        _ = setupModalWindow()

        if let parent = parentWindow ?? NSApp.keyWindow ?? NSApp.mainWindow {
            presentedAsSheet = true
            sheetParent = parent
            parent.beginSheet(window!)
        } else {
            presentedAsSheet = false
            sheetParent = nil
        }
    }

    private func showConfirmation() {
        _ = setupModalWindow()
        NSApp.runModal(for: window!)
    }

    private func setupModalWindow() -> CoreDownloadProgressState {
        let state = CoreDownloadProgressState()
        progressState = state

        Task { [weak state] in
            let size = await downloader.fetchTotalDownloadSize()
            await MainActor.run {
                if size > 0 {
                    let mb = Double(size) / 1_048_576
                    state?.totalSizeString = String(format: "%.1f MB", mb)
                }
            }
        }

        presentWindow(state: state)
        return state
    }

    private func presentWindow(state: CoreDownloadProgressState) {
        let view = CoreDownloadProgressView(
            state: state,
            onDownload: { [weak self] in self?.userDidTapDownload() },
            onChooseFolder: { [weak self] in self?.userDidTapChooseFolder() },
            onQuit: { [weak self] in self?.userDidTapQuit() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 0)
        let fittedSize = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: fittedSize)

        let w = ReusableFunc.makeTitlelessWindow(contentView: hosting, size: fittedSize)
        window = w
        w.center()
    }

    private func userDidTapDownload() {
        guard let state = progressState else { return }
        state.phase = .downloading
        state.progress = 0
        state.detail = ""

        downloader.startDownload(
            onProgress: { [weak state] progress, detail in
                Task { @MainActor in
                    state?.progress = progress
                    state?.detail = detail
                }
            },
            onCompletion: { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.progressState?.phase = .error(error.localizedDescription)
                        self?.progressState?.progress = 0
                    } else {
                        self?.closeModal(result: .downloaded)
                    }
                }
            }
        )
    }

    private func userDidTapChooseFolder() {
        let success = SettingsActions.selectLibraryFolder(showSuccessAlert: false, shouldTerminateOnCancel: false)
        guard success else { return }

        if coreFilesExistInSelectedFolder() {
            closeModal(result: .choseFolder)
        } else {
            SettingsActions.switchToBundleMode()
            ReusableFunc.showAlert(
                title: String(localized: "core.modal.missingFiles.title", defaultValue: "Database files not found"),
                message: String(localized: "core.modal.missingFiles.message", defaultValue: "The selected folder doesn’t contain “Files/main.sqlite” and “Files/special.sqlite”. Choose another folder or download the core database.")
            )
        }
    }

    private func userDidTapQuit() {
        closeModal(result: .quit)
        if !presentedAsSheet {
            NSApp.terminate(nil)
        }
    }

    private func closeModal(result: CoreDownloadModalResult) {
        if presentedAsSheet, let parent = sheetParent, let w = window {
            parent.endSheet(w)
        } else {
            NSApp.stopModal()
            window?.orderOut(nil)
        }
        window?.close()
        window = nil
        progressState = nil
        NSApplication.shared.activate(ignoringOtherApps: true)
        let completion = onCompletion
        onCompletion = nil
        completion?(result)
    }

    private func coreFilesExistInSelectedFolder() -> Bool {
        guard let basePath = AppConfig.databaseFilesPath else { return false }
        let baseURL = URL(fileURLWithPath: basePath)
        let mainPath = baseURL.appendingPathComponent("main.sqlite").path
        let specialPath = baseURL.appendingPathComponent("special.sqlite").path
        return fileExistsAndHasSize(at: mainPath) && fileExistsAndHasSize(at: specialPath)
    }

    private func fileExistsAndHasSize(at path: String) -> Bool {
        guard fileManager.fileExists(atPath: path) else { return false }
        let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        return size > 0
    }
}
#endif

// MARK: - Progress State

@Observable @MainActor
final class CoreDownloadProgressState {
    enum Phase: Equatable {
        case confirmation
        case downloading
        case error(String)
    }

    var phase: Phase = .confirmation
    var progress: Double = 0
    var detail: String = ""
    var totalSizeString: String = ""
}
