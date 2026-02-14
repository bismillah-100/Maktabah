//
//  AppUpdate.swift
//  Maktabah
//
//  Created by MacBook on 21/01/26.
//

import AppKit

extension AppDelegate {
    func checkAppUpdates(_ atLaunch: Bool = true) async {
        let checkAtStart = UserDefaults.standard.bool(
            forKey: "SuppressUpdateCheck"
        )

        if !checkAtStart, atLaunch {
            return
        }

        guard
            let isConnected =
                try? await ReusableFunc.checkInternetConnectivityDirectly(),
            isConnected
        else { return }

        // Fetch dari GitHub Releases API
        await fetchLatestRelease { release in
            guard let release else { return }

            // Parse current version dari Info.plist
            let currentVersionStr =
                Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                as? String ?? "0.0.0"
            let currentBuildStr =
                Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

            let currentParts = currentVersionStr.split(separator: ".")
                .compactMap { Int($0) }
            let currentMajor = currentParts.count > 0 ? currentParts[0] : 0
            let currentMinor = currentParts.count > 1 ? currentParts[1] : 0
            let currentPatch =
                currentParts.count > 2
                ? currentParts[2] : Int(currentBuildStr) ?? 0

            #if DEBUG
                print(
                    "currentMajor:",
                    currentMajor,
                    "currentMinor:",
                    currentMinor,
                    "currentPatch:",
                    currentPatch
                )
                print(
                    "relase.major:",
                    release.major,
                    "release.minor:",
                    release.minor,
                    "release.patch:",
                    release.patch
                )
            #endif

            // Compare versions
            let needsUpdate: Bool
            if release.major > currentMajor {
                needsUpdate = true
            } else if release.major == currentMajor
                && release.minor > currentMinor
            {
                needsUpdate = true
            } else if release.major == currentMajor
                && release.minor == currentMinor && release.patch > currentPatch
            {
                needsUpdate = true
            } else {
                needsUpdate = false
            }

            DispatchQueue.main.async(qos: .utility) { [needsUpdate, atLaunch] in
                let alert = NSAlert()
                alert.showsSuppressionButton = true
                alert.suppressionButton?.title = NSLocalizedString(
                    "Check at Start",
                    comment: ""
                )
                alert.suppressionButton?.state = checkAtStart ? .on : .off
                if needsUpdate {
                    alert.messageText = NSLocalizedString(
                        "Application Update",
                        comment: ""
                    )
                    alert.informativeText = String(
                        format: NSLocalizedString(
                            "New Version %@ available",
                            comment: ""
                        ),
                        release.versionString
                    )

                    if !release.notes.isEmpty {
                        let preview = String(release.notes.prefix(200))
                        let truncated = release.notes.count > 200 ? "..." : ""
                        alert.informativeText += "\n\n" + preview + truncated
                    }

                    alert.alertStyle = .informational
                    alert.addButton(
                        withTitle: NSLocalizedString(
                            "Download Update",
                            comment: ""
                        )
                    )
                    alert.addButton(
                        withTitle: NSLocalizedString(
                            "View Details",
                            comment: ""
                        )
                    )
                    alert.addButton(
                        withTitle: NSLocalizedString("Later", comment: "")
                    )

                    let response = alert.runModal()

                    UserDefaults.standard.set(
                        alert.suppressionButton?.state == .on,
                        forKey: "SuppressUpdateCheck"
                    )

                    if response == .alertFirstButtonReturn {
                        // Download
                        NSWorkspace.shared.open(release.downloadURL)
                    } else if response == .alertSecondButtonReturn {
                        // View Details
                        if let releaseURL = URL(
                            string:
                                "https://github.com/USERNAME/maktabah/releases/latest"
                        ) {
                            NSWorkspace.shared.open(releaseURL)
                        }
                    }
                } else {
                    if !atLaunch {
                        alert.messageText = NSLocalizedString(
                            "This is the latest version",
                            comment: ""
                        )
                        alert.runModal()
                    }
                }
            }
        }
    }

    // MARK: - GitHub Releases API

    fileprivate struct GitHubRelease: Codable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlUrl: String
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlUrl = "html_url"
            case assets
        }

        struct Asset: Codable {
            let name: String
            let browserDownloadUrl: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }
    }

    fileprivate struct AppRelease {
        let major: Int
        let minor: Int
        let patch: Int
        let notes: String
        let downloadURL: URL

        var versionString: String { "\(major).\(minor).\(patch)" }
    }

    fileprivate func fetchLatestRelease(completion: @escaping (AppRelease?) -> Void) async {
        let urlString =
            "https://api.github.com/repos/bismillah-100/maktabah/releases/latest"

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let release = try JSONDecoder().decode(
                GitHubRelease.self,
                from: data
            )

            // Parse semantic version: v1.2.3
            let tag = release.tagName.lowercased().replacingOccurrences(
                of: "v",
                with: ""
            )
            let parts = tag.split(separator: ".").compactMap { Int($0) }

            guard parts.count >= 3 else {
                completion(nil)
                return
            }

            let downloadURL: URL
            if let asset = release.assets?.first(where: {
                $0.name.hasSuffix(".zip")
            }),
                let url = URL(string: asset.browserDownloadUrl)
            {
                downloadURL = url
            } else {
                downloadURL = URL(string: release.htmlUrl)!
            }

            let appRelease = AppRelease(
                major: parts[0],
                minor: parts[1],
                patch: parts[2],
                notes: release.body ?? "",
                downloadURL: downloadURL
            )

            completion(appRelease)

        } catch {
            print("Error fetching GitHub release: \(error)")
            completion(nil)
        }
    }
}
