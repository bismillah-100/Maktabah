//
//  ZstdDecompressor.swift
//  Maktabah
//

import Foundation

enum ZstdDecompressionError: LocalizedError {
    case emptyData
    case unknownContentSize
    case decompressionFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyData:
            "Empty compressed data"
        case .unknownContentSize:
            "Unknown content size in zstd frame"
        case let .decompressionFailed(reason):
            "Zstd decompression failed: \(reason)"
        }
    }
}

enum ZstdDecompressor {
    static func decompress(data compressed: Data) throws -> Data {
        guard !compressed.isEmpty else {
            throw ZstdDecompressionError.emptyData
        }

        let expectedSize = compressed.withUnsafeBytes { ptr in
            ZSTD_getFrameContentSize(ptr.baseAddress, compressed.count)
        }

        if expectedSize == ZSTD_CONTENTSIZE_ERROR || expectedSize == ZSTD_CONTENTSIZE_UNKNOWN {
            throw ZstdDecompressionError.unknownContentSize
        }

        var output = Data(count: Int(expectedSize))
        let decompressedSize = output.withUnsafeMutableBytes { outPtr in
            compressed.withUnsafeBytes { inPtr in
                ZSTD_decompress(
                    outPtr.baseAddress,
                    Int(expectedSize),
                    inPtr.baseAddress,
                    compressed.count
                )
            }
        }

        if ZSTD_isError(decompressedSize) != 0 {
            let errorName = String(cString: ZSTD_getErrorName(decompressedSize))
            throw ZstdDecompressionError.decompressionFailed(errorName)
        }

        output.count = decompressedSize
        return output
    }

    static func decompressFile(from sourceURL: URL, to destinationURL: URL) throws {
        let compressed = try Data(contentsOf: sourceURL)
        let decompressed = try decompress(data: compressed)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try decompressed.write(to: destinationURL, options: [.atomic])
    }
}
