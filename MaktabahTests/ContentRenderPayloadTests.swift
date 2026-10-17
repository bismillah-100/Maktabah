//
//  ContentRenderPayloadTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 18/10/26.
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("ContentRenderPayload Equality Tests")
struct ContentRenderPayloadTests {
    @Test("Payload equality membedakan bookId dan content id pada teks yang identik")
    func testPayloadEquality() {
        let content1 = BookContent(id: 101, nash: "نص تجريبي")
        let content2 = BookContent(id: 102, nash: "نص تجريبي")

        let payloadA = ContentRenderPayload(bookId: 1, text: "نص تجريبي", content: content1, keepScrollPosition: false)
        let payloadDifferentBook = ContentRenderPayload(bookId: 2, text: "نص تجريبي", content: content1, keepScrollPosition: false)
        let payloadDifferentContentId = ContentRenderPayload(bookId: 1, text: "نص تجريبي", content: content2, keepScrollPosition: false)
        let payloadDifferentScroll = ContentRenderPayload(bookId: 1, text: "نص تجريبي", content: content1, keepScrollPosition: true)
        let payloadIdentical = ContentRenderPayload(bookId: 1, text: "نص تجريبي", content: content1, keepScrollPosition: false)

        #expect(payloadA != payloadDifferentBook)
        #expect(payloadA != payloadDifferentContentId)
        #expect(payloadA != payloadDifferentScroll)
        #expect(payloadA == payloadIdentical)
    }
}
