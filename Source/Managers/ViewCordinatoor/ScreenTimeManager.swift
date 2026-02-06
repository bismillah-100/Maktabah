//
//  ScreenTimeManager.swift
//  Maktabah
//
//  Created by MacBook on 17/01/26.
//

import Foundation
import IOKit.pwr_mgt

class ScreenTimeManager {
    private var assertionID: IOPMAssertionID = 0
    private var screenTimer: Timer?
    private var isActive = false

    static var shared: ScreenTimeManager = .init()

    private init() {
        if UserDefaults.standard.extendScreenTime {
            extend()
        }
    }

    // Extend screen time
    func extend(minutes: Int = 10) {
        // Cancel yang lama kalau masih aktif
        cancel()

        let reasonForActivity = "Extend screen time \(minutes) menit" as CFString

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reasonForActivity,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isActive = true
            #if DEBUG
            print("Screen time extended untuk \(minutes) menit")
            #endif

            // Auto-release setelah durasi
            screenTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
                self?.cancel()
            }
        }
    }

    // Cancel dari pengaturan
    func cancel() {
        screenTimer?.invalidate()
        screenTimer = nil

        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isActive = false
            #if DEBUG
            print("Screen time extension dibatalkan")
            #endif
        }
    }

    // Cek status
    func isExtended() -> Bool {
        return isActive
    }
}
