//
//  DonationManager.swift
//  Maktabah
//
//  Created by Antigravity on 20/08/26.
//

import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
final class DonationManager: ObservableObject {
    static let shared = DonationManager()

    let donationURL = URL(string: "https://sociabuzz.com/ghoysmawahib/support")!

    /// Milestones aktivasi: 100, 300, 600, 1000 kali dibuka
    private let milestones: Set<Int> = [100, 300, 600, 1000]
    private let cooldownDays: Double = 30 // 1 bulan cooldown
    private let promptDelayNanoseconds: UInt64 = 2_000_000_000 // 2 detik delay untuk cold start

    @Published var showDonationSheet: Bool = false

    private init() {}

    // MARK: - Properties

    var activationCount: Int {
        UserDefaults.standard.appActivationCount
    }

    @Published var hasDonated: Bool = UserDefaults.standard.hasDonated

    var isInCooldown: Bool {
        let lastDismissed = UserDefaults.standard.donationLastDismissed
        guard lastDismissed > 0 else { return false }
        let elapsed = Date().timeIntervalSince1970 - lastDismissed
        return elapsed < (cooldownDays * 24 * 3600)
    }

    var shouldShowDonation: Bool {
        if hasDonated || isInCooldown { return false }

        let count = activationCount
        if count >= 1000 && count % 1000 == 0 {
            return true
        }

        return milestones.contains(count)
    }

    // MARK: - Actions

    func recordActivation() {
        // Selama masa cooldown atau jika sudah donasi, tracking dibekukan (tidak dihitung)
        guard !hasDonated, !isInCooldown else { return }

        let newCount = activationCount + 1
        UserDefaults.standard.appActivationCount = newCount
    }

    func dismiss() {
        UserDefaults.standard.donationLastDismissed = Date().timeIntervalSince1970
    }

    func markAsDonated() {
        UserDefaults.standard.hasDonated = true
        hasDonated = true
    }

    #if DEBUG
    func resetHasDonated() {
        UserDefaults.standard.hasDonated = false
        hasDonated = false
    }
    #endif

    /// Helper untuk menunda pop-up agar tidak menginterupsi cold start render
    private func executeWithDelay(_ action: @escaping @MainActor () -> Void) {
        guard shouldShowDonation else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: promptDelayNanoseconds)
            guard shouldShowDonation else { return }
            action()
        }
    }

    // MARK: - iOS Specific

    #if os(iOS)
    func checkAndPromptIOSSheet() {
        executeWithDelay { [weak self] in
            self?.showDonationSheet = true
        }
    }
    #endif

    // MARK: - macOS Specific

    #if os(macOS)
    private var donationWindow: NSWindow?

    func checkAndPromptMacOSSheet(on parentWindow: NSWindow?) {
        executeWithDelay { [weak self] in
            self?.presentDonationSheet(on: parentWindow ?? NSApp.keyWindow)
        }
    }

    func closeDonationSheet() {
        guard let window = donationWindow else { return }
        dismiss()
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
            window.close()
            donationWindow = nil
        }
    }

    func presentDonationSheet(on parentWindow: NSWindow?) {
        if let window = donationWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = DonationSheetView(url: donationURL) { [weak self] in
            self?.closeDonationSheet()
        }

        let hosting = NSHostingView(rootView: contentView)
        let window = ReusableFunc.makeTitlelessWindow(
            contentView: hosting,
            size: hosting.fittingSize
        )
        window.isReleasedWhenClosed = false
        donationWindow = window

        if let parent = parentWindow ?? NSApp.keyWindow {
            parent.beginSheet(window) { [weak self] _ in
                window.orderOut(nil)
                self?.donationWindow = nil
            }
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }
    #endif
}
