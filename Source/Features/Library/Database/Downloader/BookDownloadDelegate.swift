//
//  BookDownloadDelegate.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 26/09/26.
//

import Foundation
import Synchronization

// MARK: - Download Stream & Delegate

enum BookDownloadEvent: Sendable {
    case progress(bytesWritten: Int64, totalBytes: Int64)
    case success(tempURL: URL, response: HTTPURLResponse)
}

final class BookDownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private let continuation: AsyncThrowingStream<BookDownloadEvent, Error>.Continuation
    private let bookId: Int
    private let expectedSize: Int64
    private let httpErrorMutex = Mutex<Error?>(nil)
    private var httpError: Error? {
        httpErrorMutex.withLock { $0 }
    }

    init(
        continuation: AsyncThrowingStream<BookDownloadEvent, Error>.Continuation,
        bookId: Int,
        expectedSize: Int64
    ) {
        self.continuation = continuation
        self.bookId = bookId
        self.expectedSize = expectedSize
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
            continuation.finish(throwing: BookDownloadError.invalidResponse)
            return
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            httpErrorMutex.withLock { error in
                error = BookDownloadError.httpStatus(bookId: bookId, statusCode: http.statusCode)
            }
            continuation.finish(throwing: httpError)
            return
        }

        let tempDest = FileManager.default.temporaryDirectory
            .appendingPathComponent("book_\(bookId)_\(UUID().uuidString)")
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
