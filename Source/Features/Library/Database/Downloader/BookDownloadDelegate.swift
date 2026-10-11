//
//  BookDownloadDelegate.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 26/09/26.
//

import Foundation
import Synchronization

// MARK: - Download Stream & Delegate

enum DownloadStreamEvent: Sendable {
    case progress(bytesWritten: Int64, totalBytes: Int64)
    case success(tempURL: URL, response: HTTPURLResponse)
}

enum DownloadStreamError: LocalizedError {
    case invalidResponse
    case httpStatus(statusCode: Int)
}

final class DownloadStreamDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private let continuation: AsyncThrowingStream<DownloadStreamEvent, Error>.Continuation
    private let expectedSize: Int64
    private let filePrefix: String
    private let customHttpError: (@Sendable (HTTPURLResponse) -> Error?)?
    private let httpErrorMutex = Mutex<Error?>(nil)
    private let stagedTempURL = Mutex<URL?>(nil)
    private var httpError: Error? {
        httpErrorMutex.withLock { $0 }
    }

    init(
        continuation: AsyncThrowingStream<DownloadStreamEvent, Error>.Continuation,
        expectedSize: Int64 = 0,
        filePrefix: String = "download",
        customHttpError: (@Sendable (HTTPURLResponse) -> Error?)? = nil
    ) {
        self.continuation = continuation
        self.expectedSize = expectedSize
        self.filePrefix = filePrefix
        self.customHttpError = customHttpError
    }

    func cleanupStagedFile() {
        let tempDest = stagedTempURL.withLock { target in
            defer { target = nil }
            return target
        }
        if let tempDest {
            try? FileManager.default.removeItem(at: tempDest)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        continuation.yield(.progress(bytesWritten: totalBytesWritten, totalBytes: total))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let http = downloadTask.response as? HTTPURLResponse else {
            continuation.finish(throwing: DownloadStreamError.invalidResponse)
            return
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let error = customHttpError?(http) ?? DownloadStreamError.httpStatus(statusCode: http.statusCode)
            httpErrorMutex.withLock { $0 = error }
            continuation.finish(throwing: error)
            return
        }

        let tempDest = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filePrefix)_\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: tempDest)
            stagedTempURL.withLock { $0 = tempDest }
            let yieldResult = continuation.yield(.success(tempURL: tempDest, response: http))
            switch yieldResult {
            case .enqueued:
                continuation.finish()
            case .dropped, .terminated:
                cleanupStagedFile()
            @unknown default:
                continuation.finish()
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error, httpError == nil {
            cleanupStagedFile()
            Self.cleanupResumeDataTempFile(from: error)
            continuation.finish(throwing: error)
        }
    }

    static func cleanupResumeDataTempFile(_ data: Data) {
        let tmpDir = FileManager.default.temporaryDirectory
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            if let tempName = plist["NSURLSessionResumeInfoTempFileName"] as? String {
                try? FileManager.default.removeItem(at: tmpDir.appendingPathComponent(tempName))
            } else if let objects = plist["$objects"] as? [Any] {
                for obj in objects {
                    if let str = obj as? String, str.hasPrefix("CFNetworkDownload_"), str.hasSuffix(".tmp") {
                        try? FileManager.default.removeItem(at: tmpDir.appendingPathComponent(str))
                    }
                }
            }
        }
        if let str = String(data: data, encoding: .isoLatin1) {
            let pattern = #"CFNetworkDownload_[A-Za-z0-9_-]+\.tmp"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: str.utf16.count)
                for match in regex.matches(in: str, range: range) {
                    if let r = Range(match.range, in: str) {
                        let filename = String(str[r])
                        try? FileManager.default.removeItem(at: tmpDir.appendingPathComponent(filename))
                    }
                }
            }
        }
    }

    static func cleanupResumeDataTempFile(from error: Error?) {
        guard let err = error as NSError?,
              let data = err.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        else {
            return
        }
        cleanupResumeDataTempFile(data)
    }
}

// MARK: - URLSession Download Stream Extension

extension URLSession {
    static func downloadStream(
        from url: URL,
        expectedSize: Int64 = 0,
        filePrefix: String = "download",
        waitsForConnectivity: Bool = false,
        timeoutIntervalForRequest: TimeInterval = 120,
        timeoutIntervalForResource: TimeInterval = 3600,
        customHttpError: (@Sendable (HTTPURLResponse) -> Error?)? = nil
    ) -> AsyncThrowingStream<DownloadStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let delegate = DownloadStreamDelegate(
                continuation: continuation,
                expectedSize: expectedSize,
                filePrefix: filePrefix,
                customHttpError: customHttpError
            )
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeoutIntervalForRequest
            config.timeoutIntervalForResource = timeoutIntervalForResource
            config.waitsForConnectivity = waitsForConnectivity

            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)

            continuation.onTermination = { @Sendable reason in
                task.cancel { resumeData in
                    if let resumeData {
                        DownloadStreamDelegate.cleanupResumeDataTempFile(resumeData)
                    }
                }
                session.invalidateAndCancel()
                if case .cancelled = reason {
                    delegate.cleanupStagedFile()
                }
            }
            task.resume()
        }
    }
}
