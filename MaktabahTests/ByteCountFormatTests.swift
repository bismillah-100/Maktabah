//
//  ByteCountFormatTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 18/10/26.
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("ByteCountFormat Extension Tests")
struct ByteCountFormatTests {
    @Test("Format berbagai ukuran byte count dengan tipe BinaryInteger")
    func testByteCountFormatting() {
        let zero = 0
        #expect(!zero.formattedByteCount.isEmpty)

        let oneKB: Int64 = 1024
        let kbString = oneKB.formattedByteCount
        #expect(kbString.localizedCaseInsensitiveContains("kb") || kbString.localizedCaseInsensitiveContains("byte"))

        let tenMB: UInt64 = 10 * 1024 * 1024
        let mbString = tenMB.formattedByteCount
        #expect(mbString.localizedCaseInsensitiveContains("mb"))

        let oneGB = 1024 * 1024 * 1024
        let gbString = oneGB.formattedByteCount
        #expect(gbString.localizedCaseInsensitiveContains("gb"))

        let smallInt: Int16 = 512
        #expect(!smallInt.formattedByteCount.isEmpty)
    }
}
