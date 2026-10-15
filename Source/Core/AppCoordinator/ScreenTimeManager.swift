//
//  ScreenTimeManager.swift
//  Maktabah
//
//  Created by MacBook on 17/01/26.
//

#if os(macOS)
import AppKit
import Foundation
import IOKit.pwr_mgt
import OSLog
import Synchronization

final class ScreenTimeManager: Sendable {
    private struct State {
        var assertionID: IOPMAssertionID = 0
        var timerTask: Task<Void, Never>?
        var isActive = false
        var durationMinutes: Int = 10
        var lastResetTime: ContinuousClock.Instant = .now
        var eventMonitor: Any?
    }

    private struct CancellationSnapshot {
        let assertionID: IOPMAssertionID
        let timerTask: Task<Void, Never>?
        let eventMonitor: Any?
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

    // Extend screen time dengan monitoring interaksi pengguna
    func extend(minutes: Int = 10) {
        state.withLock { s in
            s.isActive = true
            s.durationMinutes = minutes
        }

        ensureAssertion(minutes: minutes)
        resetTimer(minutes: minutes)
        startMonitoring()
    }

    // Pastikan assertion IOKit aktif untuk mencegah sleep
    private func ensureAssertion(minutes: Int) {
        let needsCreate = state.withLock { $0.assertionID == 0 }
        guard needsCreate else { return }

        let reasonForActivity = "Extend screen time \(minutes) menit" as CFString
        var newAssertionID: IOPMAssertionID = 0

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reasonForActivity,
            &newAssertionID
        )

        guard result == kIOReturnSuccess else {
            Logger.app.error("Gagal membuat IOPMAssertion: \(result)")
            return
        }

        Logger.app.debug("Screen time assertion dibuat untuk \(minutes) menit")

        let oldAssertion = state.withLock { s -> IOPMAssertionID in
            let old = s.assertionID
            s.assertionID = newAssertionID
            return old
        }

        if oldAssertion != 0 {
            IOPMAssertionRelease(oldAssertion)
        }
    }

    // Reset countdown timer (10 menit sejak interaksi terakhir)
    private func resetTimer(minutes: Int) {
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            self?.handleTimeout()
        }

        let oldTask = state.withLock { s -> Task<Void, Never>? in
            let old = s.timerTask
            s.timerTask = task
            s.lastResetTime = .now
            return old
        }

        oldTask?.cancel()
    }

    // Waktu jeda 10 menit tanpa interaksi telah habis -> lepas assertion agar layar bisa tidur sesuai setting sistem
    private func handleTimeout() {
        let assertionToRelease = state.withLock { s -> IOPMAssertionID in
            let assertion = s.assertionID
            s.assertionID = 0
            s.timerTask = nil
            return assertion
        }

        if assertionToRelease != 0 {
            IOPMAssertionRelease(assertionToRelease)
            Logger.app.debug("Screen time idle timeout tercapai; assertion dilepas")
        }
    }

    // Mulai pantau interaksi pengguna di jendela aplikasi
    private func startMonitoring() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.startMonitoring()
            }
            return
        }

        state.withLock { s in
            guard s.isActive, s.eventMonitor == nil else { return }
            s.eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
            ) { [weak self] event in
                self?.userDidInteract()
                return event
            }
        }
    }

    // Callback saat ada interaksi: di-throttle minimal 30 detik antar reset agar tidak membebani sistem
    private func userDidInteract() {
        let now = ContinuousClock.now
        let (shouldRefresh, minutes) = state.withLock { s -> (Bool, Int) in
            guard s.isActive else { return (false, 0) }
            if now - s.lastResetTime >= .seconds(30) {
                s.lastResetTime = now
                return (true, s.durationMinutes)
            }
            return (false, 0)
        }

        if shouldRefresh {
            ensureAssertion(minutes: minutes)
            resetTimer(minutes: minutes)
        }
    }

    // Cancel / matikan dari pengaturan
    func cancel() {
        let snapshot = state.withLock { s -> CancellationSnapshot in
            let snapshot = CancellationSnapshot(
                assertionID: s.assertionID,
                timerTask: s.timerTask,
                eventMonitor: s.eventMonitor
            )

            s.assertionID = 0
            s.isActive = false
            s.timerTask = nil
            s.eventMonitor = nil

            return snapshot
        }

        snapshot.timerTask?.cancel()

        if snapshot.assertionID != 0 {
            IOPMAssertionRelease(snapshot.assertionID)
            Logger.app.debug("Screen time extension dibatalkan")
        }

        if let monitorToRemove = snapshot.eventMonitor {
            if Thread.isMainThread {
                NSEvent.removeMonitor(monitorToRemove)
            } else {
                DispatchQueue.main.async {
                    NSEvent.removeMonitor(monitorToRemove)
                }
            }
        }
    }

    // Cek status aktif
    func isExtended() -> Bool {
        state.withLock { $0.isActive }
    }

    deinit {
        cancel()
    }
}
#else
final class ScreenTimeManager: Sendable {
    static let shared = ScreenTimeManager()
    var isActive: Bool { false }
    func extend(minutes: Int = 10) {}
    func cancel() {}
    func isExtended() -> Bool { false }
}
#endif
