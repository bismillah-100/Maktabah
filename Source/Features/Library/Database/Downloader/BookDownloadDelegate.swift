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
            continuation.yield(.success(tempURL: tempDest, response: http))
            continuation.finish()
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
            continuation.finish(throwing: error)
        }
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

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                session.invalidateAndCancel()
            }
            task.resume()
        }
    }
}
