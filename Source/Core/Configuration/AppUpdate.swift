//
//  AppUpdate.swift
//  Maktabah
//
//  Created by MacBook on 21/01/26.
//

import AppKit
#if DIRECT_DISTRIBUTION
import Sparkle

extension AppDelegate {

    @MainActor
    func checkAppUpdates(_ atLaunch: Bool = true) async {
        let isConnected = await NetworkMonitor.shared.checkConnectivity()
        guard isConnected else { return }

        let updater = updaterController.updater

        if atLaunch {
            updater.checkForUpdatesInBackground()
        } else {
            updater.checkForUpdates()
        }
    }
}

extension AppDelegate: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        AppConfig.appcastURL?.absoluteString
    }

    func updaterShouldPromptForPermissionToCheck(
        forUpdates updater: SPUUpdater
    ) -> Bool {
        false
    }
}
#endif
