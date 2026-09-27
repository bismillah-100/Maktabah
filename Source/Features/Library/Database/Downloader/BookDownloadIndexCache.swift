//
//  BookDownloadIndexCache.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 27/09/26.
//

import Foundation
import OSLog

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
            Logger.library.error("Failed to cache index.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
