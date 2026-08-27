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

    static func decompressData(_ data: Data?) -> String {
        guard let compressed = data, !compressed.isEmpty else { return "" }
        return compressed.withUnsafeBytes { ptr in decompressData(from: ptr) }
    }

    static func decompressData(from ptr: UnsafeRawBufferPointer?) -> String {
        guard let ptr, ptr.count > 0 else { return "" }

        let expectedSize = ZSTD_getFrameContentSize(ptr.baseAddress, ptr.count)

        if expectedSize == ZSTD_CONTENTSIZE_ERROR || expectedSize == ZSTD_CONTENTSIZE_UNKNOWN {
            #if DEBUG
            print("Ukuran konten tidak diketahui")
            #endif
            return ""
        }

        let expectedSizeInt = Int(expectedSize)
        return String(unsafeUninitializedCapacity: expectedSizeInt) { outBuffer in
            let dict = Thread.current.threadDictionary
            let dctx: OpaquePointer
            if let wrapper = dict["Maktabah.ZSTDDCtx"] as? ZSTDContextWrapper {
                dctx = wrapper.dctx
            } else if let wrapper = ZSTDContextWrapper() {
                dict["Maktabah.ZSTDDCtx"] = wrapper
                dctx = wrapper.dctx
            } else {
                return 0
            }

            let decompressedSize = ZSTD_decompressDCtx(
                dctx,
                outBuffer.baseAddress,
                expectedSizeInt,
                ptr.baseAddress,
                ptr.count
            )

            if ZSTD_isError(decompressedSize) != 0 {
                let errorName = String(cString: ZSTD_getErrorName(decompressedSize))
                #if DEBUG
                print("Zstd Error: \(errorName)")
                #endif
                return 0
            }

            return decompressedSize
        }
    }

    static func compressData(_ text: String, level: Int32 = 10) -> Data? {
        let inputData = Data(text.utf8)
        guard !inputData.isEmpty else { return Data() }

        let bound = ZSTD_compressBound(inputData.count)
        var output = Data(count: Int(bound))

        let compressedSize = output.withUnsafeMutableBytes { outPtr -> Int in
            inputData.withUnsafeBytes { inPtr in
                ZSTD_compress(
                    outPtr.baseAddress,
                    bound,
                    inPtr.baseAddress,
                    inputData.count,
                    level
                )
            }
        }

        if ZSTD_isError(compressedSize) != 0 {
            let errorName = String(cString: ZSTD_getErrorName(compressedSize))
            #if DEBUG
            print("Zstd Compress Error: \(errorName)")
            #endif
            return nil
        }

        output.count = compressedSize
        return output
    }
}
