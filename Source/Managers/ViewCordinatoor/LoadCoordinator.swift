//
//  LoadCoordinator.swift
//  maktab
//
//  Created by MacBook on 18/12/25.
//

import Foundation

// Coordinator untuk menunggu load selesai
actor LoadCoordinator {
    private(set) var isLoaded = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilLoaded() async {
        if isLoaded { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }

    func markLoaded() {
        guard !isLoaded else { return }
        isLoaded = true
        let current = waiters
        waiters.removeAll()
        for cont in current { cont.resume() }
    }
}
