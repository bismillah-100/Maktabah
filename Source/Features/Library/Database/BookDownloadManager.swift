//
//  BookDownloadManager.swift
//  Maktabah
//
//  Created by Codex on 11/03/26.
//  Manages per-book downloads for bundle mode
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
            String(localized: "error.invalidBaseURL")
        case let .bookNotAvailable(bookId):
            "Book \(bookId) is not available in the download index."
        case .invalidResponse:
            String(localized: "error.invalidResponse")
        case let .indexRequestFailed(statusCode):
            "Index request failed with HTTP status \(statusCode)."
        case let .httpStatus(bookId, statusCode):
            String(localized: "error.httpStatus.\(bookId).\(statusCode)")
        case let .downloadFailed(bookId):
            String(localized: "error.downloadFailed.\(bookId)")
        case let .decompressionFailed(bookId, reason):
            String(localized: "error.decompressionFailed.\(bookId).\(reason)")
        case .networkUnavailable:
            String(localized: "error.networkUnavailable")
        }
    }
}

final class BookDownloadManager {
    static let shared = BookDownloadManager()

    private let fileManager = FileManager.default
    private let networkMonitor = NetworkMonitor.shared
    private let indexCache = BookDownloadIndexCache.shared
    private let singleFlight = SingleFlight<Int, URL>()

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private init() {
        Task {
            await networkMonitor.registerConnectivityCallbacks(
                onLost: { [weak self] in
                    Task {
                        await self?.cancelAllDownloads()
                    }
                }
            )
        }
    }

    func localBookURL(bookId: Int) -> URL? {
        guard let basePath = AppConfig.bookFilesPath else { return nil }
        let url = URL(fileURLWithPath: basePath).appendingPathComponent("\(bookId).sqlite")
        return fileManager.isNonEmptyFile(at: url) ? url : nil
    }

    func isBookDownloaded(bookId: Int) -> Bool {
        localBookURL(bookId: bookId) != nil
    }

    func ensureBookDownloaded(bookId: Int) async throws -> URL {
        if let existing = localBookURL(bookId: bookId) {
            return existing
        }

        return try await singleFlight.run(key: bookId) {
            try await self.performDownload(bookId: bookId)
        }
    }

    func downloadBookResult(bookId: Int) async -> (bookId: Int, result: Result<URL, Error>) {
        do {
            let url = try await ensureBookDownloaded(bookId: bookId)
            return (bookId, .success(url))
        } catch {
            return (bookId, .failure(error))
        }
    }

    private func performDownload(bookId: Int) async throws -> URL {
        if let local = localBookURL(bookId: bookId) {
            return local
        }
        return try await downloadBook(bookId: bookId)
    }

    private func downloadBook(bookId: Int) async throws -> URL {
        guard await networkMonitor.isConnected else {
            throw BookDownloadError.networkUnavailable
        }
        guard let destinationDir = AppConfig.bookFilesPath else {
            throw ArchiveError.databasePathNotAvailable
        }

        let destinationURL = URL(fileURLWithPath: destinationDir)
            .appendingPathComponent("\(bookId).sqlite")

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
                    bookId: bookId
                )
                return destinationURL
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? BookDownloadError.downloadFailed(bookId: bookId)
    }

    private func downloadAndProcessCandidate(
        candidate: URL,
        destinationURL: URL,
        bookId: Int
    ) async throws {
        try Task.checkCancellation()
        guard await networkMonitor.isConnected else {
            throw BookDownloadError.networkUnavailable
        }
        let (tempURL, response) = try await urlSession.download(from: candidate)
        defer { try? fileManager.removeItem(at: tempURL) }

        guard let http = response as? HTTPURLResponse else {
            throw BookDownloadError.invalidResponse
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            throw BookDownloadError.httpStatus(bookId: bookId, statusCode: http.statusCode)
        }

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

    private func candidateURLs(for bookId: Int) async -> [URL] {
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

actor BookDownloadIndexCache {
    static let shared = BookDownloadIndexCache()

    private var cachedEntries: [Int: BundleBookIndexEntry] = [:]
    private var lastFetch: Date?
    private var inFlight: Task<[Int: BundleBookIndexEntry], Error>?
    private let ttl: TimeInterval = 60 * 60 * 24 * 30
    private let etagKey = "book_index_etag"
    private let lastModifiedKey = "book_index_last_modified"

    func entry(
        for bookId: Int,
        indexURL: URL,
        urlSession: URLSession
    ) async throws -> BundleBookIndexEntry? {
        if cachedEntries.isEmpty {
            loadCachedIndexIfNeeded()
        }
        if let cached = cachedEntries[bookId] {
            return cached
        }

        let now = Date()
        if let lastFetch,
           now.timeIntervalSince(lastFetch) < ttl,
           !cachedEntries.isEmpty
        {
            return cachedEntries[bookId]
        }

        let entries = try await fetchIndex(
            indexURL: indexURL,
            urlSession: urlSession
        )
        return entries[bookId]
    }

    func entries(
        indexURL: URL,
        urlSession: URLSession,
        forceRefresh: Bool = false
    ) async throws -> [Int: BundleBookIndexEntry] {
        if forceRefresh {
            cachedEntries = [:]
            lastFetch = nil
        } else if cachedEntries.isEmpty {
            loadCachedIndexIfNeeded()
        }

        let now = Date()
        if !forceRefresh,
           let lastFetch,
           now.timeIntervalSince(lastFetch) < ttl,
           !cachedEntries.isEmpty
        {
            return cachedEntries
        }

        return try await fetchIndex(indexURL: indexURL, urlSession: urlSession)
    }

    private func fetchIndex(
        indexURL: URL,
        urlSession: URLSession
    ) async throws -> [Int: BundleBookIndexEntry] {
        if let inFlight {
            return try await inFlight.value
        }

        let task = Task { () throws -> [Int: BundleBookIndexEntry] in
            let defaults = UserDefaults.standard
            let (initialData, initialHTTP) = try await performIndexRequest(
                indexURL: indexURL,
                urlSession: urlSession,
                includeValidators: true
            )

            if initialHTTP.statusCode == 304 {
                return try await handleNotModifiedResponse(
                    indexURL: indexURL,
                    urlSession: urlSession,
                    defaults: defaults
                )
            }

            return try decodeAndCacheEntries(
                from: initialData,
                http: initialHTTP,
                defaults: defaults
            )
        }

        inFlight = task
        do {
            let result = try await task.value
            cachedEntries = result
            lastFetch = Date()
            inFlight = nil
            return result
        } catch {
            inFlight = nil
            throw error
        }
    }

    private func handleNotModifiedResponse(
        indexURL: URL,
        urlSession: URLSession,
        defaults: UserDefaults
    ) async throws -> [Int: BundleBookIndexEntry] {
        if cachedEntries.isEmpty {
            loadCachedIndexIfNeeded()
        }
        if !cachedEntries.isEmpty {
            return cachedEntries
        }

        defaults.removeObject(forKey: etagKey)
        defaults.removeObject(forKey: lastModifiedKey)

        let (retryData, retryHTTP) = try await performIndexRequest(
            indexURL: indexURL,
            urlSession: urlSession,
            includeValidators: false
        )
        return try decodeAndCacheEntries(
            from: retryData,
            http: retryHTTP,
            defaults: defaults
        )
    }

    private func cacheFileURL() -> URL? {
        guard let cachePath = AppConfig.archiveCachePath else { return nil }
        return URL(fileURLWithPath: cachePath).appendingPathComponent("index.json")
    }

    private func performIndexRequest(
        indexURL: URL,
        urlSession: URLSession,
        includeValidators: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: indexURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if includeValidators {
            let defaults = UserDefaults.standard
            if let etag = defaults.string(forKey: etagKey) {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = defaults.string(forKey: lastModifiedKey) {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BookDownloadError.invalidResponse
        }
        return (data, http)
    }

    private func decodeAndCacheEntries(
        from data: Data,
        http: HTTPURLResponse,
        defaults: UserDefaults
    ) throws -> [Int: BundleBookIndexEntry] {
        guard (200 ..< 300).contains(http.statusCode) else {
            throw BookDownloadError.indexRequestFailed(statusCode: http.statusCode)
        }

        let decoder = JSONDecoder()
        let entries = try decoder.decode([BundleBookIndexEntry].self, from: data)
        var mapped: [Int: BundleBookIndexEntry] = [:]
        mapped.reserveCapacity(entries.count)
        for entry in entries {
            mapped[entry.bkid] = entry
        }

        if let etag = http.value(forHTTPHeaderField: "ETag") {
            defaults.set(etag, forKey: etagKey)
        }
        if let lastModified = http.value(forHTTPHeaderField: "Last-Modified") {
            defaults.set(lastModified, forKey: lastModifiedKey)
        }
        saveCachedIndex(data: data)
        return mapped
    }

    private func loadCachedIndexIfNeeded() {
        guard let fileURL = cacheFileURL(),
              let data = try? Data(contentsOf: fileURL)
        else {
            return
        }

        // Ambil tanggal modifikasi file agar TTL berfungsi setelah restart aplikasi
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modificationDate = attributes[.modificationDate] as? Date
        {
            lastFetch = modificationDate
        }

        let decoder = JSONDecoder()
        guard let entries = try? decoder.decode([BundleBookIndexEntry].self, from: data) else {
            return
        }
        var mapped: [Int: BundleBookIndexEntry] = [:]
        mapped.reserveCapacity(entries.count)
        for entry in entries {
            _ = entry.bkid
            mapped[entry.bkid] = entry
        }
        cachedEntries = mapped
    }

    private func saveCachedIndex(data: Data) {
        guard let fileURL = cacheFileURL() else { return }
        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Failed to cache index.json:", error)
            #endif
        }
    }
}
