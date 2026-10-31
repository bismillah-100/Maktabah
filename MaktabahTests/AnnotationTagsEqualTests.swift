//
//  AnnotationTagsEqualTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 31/10/26.
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("Annotation Tags Equality Tests")
struct AnnotationTagsEqualTests {
    let repo = AnnotationRepository.shared

    @Test("tagsEqual handles empty and whitespace tags")
    func testEmptyAndWhitespaceTags() {
        #expect(repo.tagsEqual([], []))
        #expect(repo.tagsEqual([""], []))
        #expect(repo.tagsEqual(["   "], []))
        #expect(repo.tagsEqual(["   ", ""], []))
    }

    @Test("tagsEqual ignores element ordering and case")
    func testOrderAndCaseInvariance() {
        #expect(repo.tagsEqual(["Fiqh", "Hadith"], ["hadith", "FIQH"]))
        #expect(repo.tagsEqual(["A", "B", "C"], ["c", "b", "a"]))
        #expect(repo.tagsEqual(["tag1", "tag2"], ["tag2", "tag1"]))
        #expect(!repo.tagsEqual(["tag1"], ["tag2"]))
        #expect(!repo.tagsEqual(["tag1", "tag2"], ["tag1"]))
    }

    @Test("tagsEqual handles duplicate tags gracefully")
    func testDuplicateTags() {
        #expect(repo.tagsEqual(["Fiqh", "fiqh"], ["Fiqh"]))
        #expect(repo.tagsEqual(["a", "b", "a"], ["b", "a"]))
    }
}
