//
//  ZstdShim.swift
//  Maktabah
//
//  Declares the subset of zstd C symbols used by the app without importing
//  the SwiftPM Clang module that triggers config macro warnings on newer Xcode.
//

import Foundation

let ZSTD_CONTENTSIZE_ERROR: UInt64 = .max
let ZSTD_CONTENTSIZE_UNKNOWN: UInt64 = .max - 1

@_silgen_name("ZSTD_getFrameContentSize")
func ZSTD_getFrameContentSize(_ src: UnsafeRawPointer?, _ srcSize: Int) -> UInt64

@_silgen_name("ZSTD_decompress")
func ZSTD_decompress(
    _ dst: UnsafeMutableRawPointer?,
    _ dstCapacity: Int,
    _ src: UnsafeRawPointer?,
    _ compressedSize: Int
) -> Int

@_silgen_name("ZSTD_isError")
func ZSTD_isError(_ code: Int) -> UInt32

@_silgen_name("ZSTD_getErrorName")
func ZSTD_getErrorName(_ code: Int) -> UnsafePointer<CChar>

@_silgen_name("ZSTD_compressBound")
func ZSTD_compressBound(_ srcSize: Int) -> Int

@_silgen_name("ZSTD_compress")
func ZSTD_compress(
    _ dst: UnsafeMutableRawPointer?,
    _ dstCapacity: Int,
    _ src: UnsafeRawPointer?,
    _ srcSize: Int,
    _ compressionLevel: Int32
) -> Int

@_silgen_name("ZSTD_createDCtx")
func ZSTD_createDCtx() -> OpaquePointer?

@_silgen_name("ZSTD_freeDCtx") @discardableResult
func ZSTD_freeDCtx(_ cctx: OpaquePointer?) -> Int

@_silgen_name("ZSTD_decompressDCtx")
func ZSTD_decompressDCtx(
    _ dctx: OpaquePointer?,
    _ dst: UnsafeMutableRawPointer?,
    _ dstCapacity: Int,
    _ src: UnsafeRawPointer?,
    _ srcSize: Int
) -> Int
