//
//  CloudKitSyncStateTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 18/10/26.
//

import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("CloudKit Core Manager Concurrency & Syncing State", .serialized)
struct CloudKitSyncStateTests {
    let core = CloudKitCoreManager.shared

    @Test("tryBeginSyncing: atomic locking state transitions")
    func testTryBeginSyncingTransitions() {
        core.setSyncing(false)
        #expect(core.isSyncing == false)

        #expect(core.tryBeginSyncing() == true)
        #expect(core.isSyncing == true)

        // Panggilan kedua saat syncing aktif harus mengembalikan false
        #expect(core.tryBeginSyncing() == false)

        // Reset dan coba lagi
        core.setSyncing(false)
        #expect(core.isSyncing == false)
        #expect(core.tryBeginSyncing() == true)
        core.setSyncing(false)
    }

    @Test("Race condition: Hanya satu task konkuren yang berhasil memulai sync")
    func testConcurrentTryBeginSyncing() async {
        core.setSyncing(false)
        defer { core.setSyncing(false) }

        let taskCount = 50
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0 ..< taskCount {
                group.addTask {
                    core.tryBeginSyncing()
                }
            }
            var acc: [Bool] = []
            for await success in group {
                acc.append(success)
            }
            return acc
        }

        let successCount = results.count(where: { $0 })
        #expect(successCount == 1)
        #expect(core.isSyncing == true)
    }
}
