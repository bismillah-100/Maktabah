//
//  ScreenTimeManager.swift
//  Maktabah
//
//  Created by MacBook on 17/01/26.
//

import Foundation
import IOKit.pwr_mgt
import Synchronization

final class ScreenTimeManager: Sendable {
    private struct State {
        var assertionID: IOPMAssertionID = 0
        var timerTask: Task<Void, Never>?
        var isActive = false
    }

    private let state: Mutex<State>

    static let shared = ScreenTimeManager()

    var isActive: Bool {
        state.withLock(\.isActive)
    }

    private init() {
        state = Mutex(State())
        if UserDefaults.standard.extendScreenTime {
            extend()
        }
    }

    // Extend screen time
    func extend(minutes: Int = 10) {
        cancel()

        let reasonForActivity = "Extend screen time \(minutes) menit" as CFString
        var newAssertionID: IOPMAssertionID = 0

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reasonForActivity,
            &newAssertionID
        )

        guard result == kIOReturnSuccess else { return }

        #if DEBUG
        print("Screen time extended untuk \(minutes) menit")
        #endif

        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            self?.cancel()
        }

        let oldAssertion = state.withLock { s -> IOPMAssertionID in
            let old = s.assertionID
            s.assertionID = newAssertionID
            s.isActive = true
            s.timerTask = task
            return old
        }

        // Lepas assertion lama jika terjadi race condition saat pemanggilan
        if oldAssertion != 0 {
            IOPMAssertionRelease(oldAssertion)
        }
    }

    // Cancel dari pengaturan
    func cancel() {
        // Ambil data yang perlu dibersihkan lalu ubah state secara atomik
        let (assertionToRelease, taskToCancel) = state.withLock { s -> (IOPMAssertionID, Task<Void, Never>?) in
            let assertion = s.assertionID
            let task = s.timerTask

            s.assertionID = 0
            s.isActive = false
            s.timerTask = nil

            return (assertion, task)
        }

        // Eksekusi pelepasan di luar lock untuk mencegah lock contention
        taskToCancel?.cancel()

        if assertionToRelease != 0 {
            IOPMAssertionRelease(assertionToRelease)
            #if DEBUG
            print("Screen time extension dibatalkan")
            #endif
        }
    }

    // Cek status
    func isExtended() -> Bool {
        state.withLock { $0.isActive }
    }

    deinit {
        cancel()
    }
}
