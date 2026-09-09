//
//  SafeCounter.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 09/09/26.
//

import Synchronization

final class SafeCounter: Sendable {
    private let state = Mutex<Int>(0)

    func increment() -> Int {
        state.withLock { count in
            count += 1
            return count
        }
    }
}
