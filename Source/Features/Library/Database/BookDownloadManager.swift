//
//  BookDownloadManager.swift
//  Maktabah
//
//  Created by Codex on 11/03/26.
//  Track book download progress.
//

import Foundation
import Network

enum BookDownloadError: LocalizedError {
    case invalidBaseURL
    case bookNotAvailable(bookId: Int)
    case invalidResponse
    case indexRequestFailed(statusCode: Int)
    case httpStatus(bookId: Int, statusCode: Int)
    case downloadFailed(bookId: Int)
    case decompressionFailed(bookId: Int, reason: String)
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            String(localized: .Library.errorInvalidBaseURL)
        case let .bookNotAvailable(bookId):
            String(localized: .Library.errorBookNotAvailable(bookId))
        case .invalidResponse:
            String(localized: .Library.errorInvalidResponse)
        case let .indexRequestFailed(statusCode):
            String(localized: .Library.errorIndexRequestFailed(statusCode))
        case let .httpStatus(bookId, statusCode):
            String(localized: .Library.errorHttpStatus(bookId, statusCode))
        case let .downloadFailed(bookId):
            String(localized: .Library.errorDownloadFailed(bookId))
        case let .decompressionFailed(bookId, reason):
            String(localized: .Library.errorDecompressionFailed(bookId, reason))
        case .networkUnavailable:
            String(localized: .Library.errorNetworkUnavailable)
        }
    }
}

final class BookDownloadManager: Sendable {
    static let shared = BookDownloadManager()

    private var fileManager: FileManager { .default }
    private let networkMonitor = NetworkMonitor.shared
    private let indexCache = BookDownloadIndexCache.shared
    private let singleFlight = SingleFlight<Int, URL>()

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private init() {
        Task { [weak self] in
            await self?.startNetworkMonitor()
        }
    }

    private nonisolated func startNetworkMonitor() async {
        await networkMonitor.registerConnectivityCallbacks(
            onLost: { [weak self] in
                Task { [weak self] in
                    await self?.cancelAllDownloads()
                }
            }
        )
    }

    func localBookURL(bookId: Int) -> URL? {
        guard let basePath = AppConfig.bookFilesPath else { return nil }
        let url = URL(fileURLWithPath: basePath).appendingPathComponent("\(bookId).sqlite")
        return fileManager.isNonEmptyFile(at: url) ? url : nil
    }

    func isBookDownloaded(bookId: Int) -> Bool {
        localBookURL(bookId: bookId) != nil
    }

    func ensureBookDownloaded(
        bookId: Int,
        expectedSize: Int64? = nil,
        onProgress: (@Sendable (_ bytesWritten: Int64, _ totalBytes: Int64) -> Void)? = nil
    ) async throws -> URL {
        if let existing = localBookURL(bookId: bookId) {
            return existing
        }

        return try await singleFlight.run(key: bookId) {
            try await self.performDownload(bookId: bookId, expectedSize: expectedSize, onProgress: onProgress)
        }
    }

    nonisolated func downloadBookResult(
        bookId: Int,
        expectedSize: Int64? = nil,
        onProgress: (@Sendable (_ bytesWritten: Int64, _ totalBytes: Int64) -> Void)? = nil
    ) async -> (bookId: Int, result: Result<URL, Error>) {
        do {
            let url = try await ensureBookDownloaded(bookId: bookId, expectedSize: expectedSize, onProgress: onProgress)
            return (bookId, .success(url))
        } catch {
            return (bookId, .failure(error))
        }
    }

    static func isNetworkFailure(_ error: Error) -> Bool {
        if let bookError = error as? BookDownloadError, case .networkUnavailable = bookError {
            return true
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut:
                return true
            default: return false
            }
        }
        return false
    }

    private nonisolated func resolveExpectedSize(for bookId: Int, explicit: Int64?) async -> Int64 {
        if let explicit, explicit > 0 {
            return explicit
        }
        if let indexURL = AppConfig.bookIndexURL,
           let entry = try? await indexCache.entry(for: bookId, indexURL: indexURL, urlSession: urlSession),
           let size = entry.sizeZst, size > 0
        {
            return size
        }
        return 0
    }

    private nonisolated func performDownload(
        bookId: Int,
        expectedSize: Int64? = nil,
        onProgress: (@Sendable (_ bytesWritten: Int64, _ totalBytes: Int64) -> Void)? = nil
    ) async throws -> URL {
        if let local = localBookURL(bookId: bookId) {
            return local
        }
        return try await downloadBook(bookId: bookId, expectedSize: expectedSize, onProgress: onProgress)
    }

    private nonisolated func downloadBook(
        bookId: Int,
        expectedSize: Int64? = nil,
        onProgress: (@Sendable (_ bytesWritten: Int64, _ totalBytes: Int64) -> Void)? = nil
    ) async throws -> URL {
        guard await networkMonitor.isConnected else {
            throw BookDownloadError.networkUnavailable
        }
        guard let destinationDir = AppConfig.bookFilesPath else {
            throw ArchiveError.databasePathNotAvailable
        }

        let destinationURL = URL(fileURLWithPath: destinationDir)
            .appendingPathComponent("\(bookId).sqlite")

        let resolvedExpectedSize = await resolveExpectedSize(for: bookId, explicit: expectedSize)

        let candidates = await candidateURLs(for: bookId)
        guard !candidates.isEmpty else {
            throw BookDownloadError.bookNotAvailable(bookId: bookId)
        }
        var lastError: Error?

        for candidate in candidates {
            do {
                try await downloadAndProcessCandidate(
                    candidate: candidate,
                    destinationURL: destinationURL,
                    bookId: bookId,
                    expectedSize: resolvedExpectedSize,
                    onProgress: onProgress
                )
                return destinationURL
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? BookDownloadError.downloadFailed(bookId: bookId)
    }

    private nonisolated func downloadAndProcessCandidate(
        candidate: URL,
        destinationURL: URL,
        bookId: Int,
        expectedSize: Int64,
        onProgress: (@Sendable (_ bytesWritten: Int64, _ totalBytes: Int64) -> Void)?
    ) async throws {
        try Task.checkCancellation()
        guard await networkMonitor.isConnected else {
            throw BookDownloadError.networkUnavailable
        }

        var downloadedTempURL: URL?
        var lastHTTPResponse: HTTPURLResponse?

        let stream = URLSession.downloadStream(
            from: candidate,
            expectedSize: expectedSize,
            filePrefix: "book_\(bookId)",
            waitsForConnectivity: true,
            customHttpError: { http in
                BookDownloadError.httpStatus(bookId: bookId, statusCode: http.statusCode)
            }
        )

        for try await event in stream {
            switch event {
            case let .progress(bytesWritten, totalBytes):
                onProgress?(bytesWritten, totalBytes)
            case let .success(tempURL, response):
                downloadedTempURL = tempURL
                lastHTTPResponse = response
            }
        }

        guard let tempURL = downloadedTempURL, let _ = lastHTTPResponse else {
            throw BookDownloadError.downloadFailed(bookId: bookId)
        }
        defer { try? fileManager.removeItem(at: tempURL) }

        if candidate.pathExtension.lowercased() == "zst" {
            do {
                fileManager.removeDatabaseAndSidecars(at: destinationURL)
                try ZstdDecompressor.decompressFile(from: tempURL, to: destinationURL)
            } catch {
                throw BookDownloadError.decompressionFailed(bookId: bookId, reason: error.localizedDescription)
            }
        } else {
            fileManager.removeDatabaseAndSidecars(at: destinationURL)
            try fileManager.moveItem(at: tempURL, to: destinationURL)
        }

        guard fileManager.isNonEmptyFile(at: destinationURL) else {
            throw BookDownloadError.downloadFailed(bookId: bookId)
        }
    }

    func removeCachedBook(bookId: Int) {
        guard let basePath = AppConfig.bookFilesPath else { return }
        let url = URL(fileURLWithPath: basePath).appendingPathComponent("\(bookId).sqlite")
        fileManager.removeDatabaseAndSidecars(at: url)
    }

    func cleanupBooksDirectory() {
        guard let basePath = AppConfig.bookFilesPath else { return }
        fileManager.cleanupDirectory(at: URL(fileURLWithPath: basePath))
    }

    func cancelAllDownloads() async {
        await singleFlight.cancelAll()
    }

    private nonisolated func candidateURLs(for bookId: Int) async -> [URL] {
        var urls: [URL] = []

        if let indexURL = AppConfig.bookIndexURL,
           let releaseBase = AppConfig.bookReleaseBaseURL
        {
            if let entry = try? await indexCache.entry(
                for: bookId,
                indexURL: indexURL,
                urlSession: urlSession
            ) {
                let releaseURL = releaseBase
                    .appendingPathComponent(entry.release)
                    .appendingPathComponent(entry.filename)
                urls.append(releaseURL)

                if entry.filename.lowercased().hasSuffix(".sqlite.zst") {
                    let sqliteName = String(entry.filename.dropLast(4))
                    urls.append(
                        releaseBase
                            .appendingPathComponent(entry.release)
                            .appendingPathComponent(sqliteName)
                    )
                }
            }
        }

        if AppConfig.hasCustomBookDownloadBaseURL,
           let baseURL = AppConfig.bookDownloadBaseURL
        {
            let sqliteName = "\(bookId).sqlite"
            let zstName = "\(bookId).sqlite.zst"
            urls.append(baseURL.appendingPathComponent(zstName))
            urls.append(baseURL.appendingPathComponent(sqliteName))
        }

        return urls
    }
}

// MARK: - Book Download Index

struct BundleBookIndexEntry: Decodable {
    let bkid: Int
    let filename: String
    let release: String
    let sizeZst: Int64?

    enum CodingKeys: String, CodingKey {
        case bkid
        case filename
        case release
        case sizeZst = "size_zst"
    }
}
