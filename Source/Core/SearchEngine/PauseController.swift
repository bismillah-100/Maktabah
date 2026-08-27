//
//  PauseController.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 25/08/26.
//

import Foundation

actor PauseController {
    private var isPaused = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func pause() {
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        let conts = continuations
        continuations.removeAll()
        for cont in conts {
            cont.resume()
        }
    }

    func stopAndResumeAll() {
        resume()
    }

    func waitIfPaused() async {
        guard isPaused else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            continuations.append(continuation)
        }
    }

    func currentlyPaused() -> Bool {
        isPaused
    }
}
