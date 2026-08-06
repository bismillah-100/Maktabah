//
//  CoreUpdateAlert.swift
//  Maktabah
//
//  Core database update alert using SwiftUI (cross-platform: macOS + iOS)
//

import SwiftUI

// MARK: - Core Update Check Result

enum CoreUpdateCheckResult {
    case upToDate
    case updateAvailable(newVersion: String)
    case error(Error)
}

// MARK: - Core Update Checker (version.txt + tabel v based)

struct CoreUpdateChecker {
    /// Cek apakah ada update core database
    /// Logic:
    /// 1. Cek throttle 6 bulan - skip jika belum waktunya
    /// 2. Fetch version.txt dari GitHub
    /// 3. Cek versi lokal dari tabel 'v' di main.sqlite
    /// 4. Bandingkan:
    ///    - Jika tabel 'v' tidak ada → update tersedia
    ///    - Jika versi berbeda → update tersedia
    ///    - Jika sama → up-to-date (simpan timestamp ke UserDefaults)
    /// NOTE: Timestamp hanya disimpan saat up-to-date, bukan saat "Later"
    static func checkAsync() async -> CoreUpdateCheckResult {
        // 1. Cek throttle 6 bulan (hemat bandwidth)
        if !AppConfig.shouldCheckCoreVersion {
            return .upToDate
        }

        // 2. Fetch version.txt dari GitHub
        let remoteVersion: String
        do {
            remoteVersion = try await CoreDatabaseDownloader.fetchLatestCoreVersion()
        } catch {
            return .error(error)
        }

        // 3. Cek versi lokal dari tabel 'v' di main.sqlite
        let localVersion = DatabaseManager.shared.getLocalVersionDisplay()

        // 4. Bandingkan
        // - Jika tabel 'v' tidak ada → update
        // - Jika versi berbeda → update
        if localVersion == nil || localVersion != remoteVersion {
            // Jangan simpan apa-apa - user bisa pilih "Later"
            return .updateAvailable(newVersion: remoteVersion)
        }

        // 5. Up-to-date - baru simpan timestamp setelah bandingkan
        // Ini berarti user sudah punya versi terbaru
        AppConfig.markCoreVersionCheckDone(newVersion: remoteVersion)

        return .upToDate
    }
}

enum CoreUpdateError: LocalizedError {
    case invalidURL
    case networkError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid version URL"
        case .networkError:
            return "Network error while checking for updates"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - Core Update Alert View

struct CoreUpdateAlertView: View {
    let newVersion: String
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
            }

            // Title
            Text("Library Update Available")
                .font(.headline)

            // Description
            Text("Version \(newVersion) is available. The core database contains books metadata and categories.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            // Current vs New version
            VStack(spacing: 8) {
                HStack {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusBadge(
                        text: DatabaseManager.shared.getLocalVersionDisplay() ?? "v0.1-core",
                        color: .secondary
                    )
                }

                Divider()

                HStack {
                    Text("New")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusBadge(text: newVersion, color: .blue)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Buttons
            #if os(macOS)
            HStack(spacing: 12) { buttonActions() }
            #else
            VStack(spacing: 8) { buttonActions() }
            #endif
        }
        .padding(24)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func buttonActions() -> some View {
        Button {
            #if os(iOS)
                dismiss()
            #endif
            onDismiss()
        } label: {
            Text("Later")
                #if os(iOS)
                    .frame(maxWidth: .infinity)
                #endif
        }
        .tint(.secondary)
        .buttonStyle(.borderedProminent)

        Button {
            #if os(iOS)
                dismiss()
            #endif
            onUpdate()
        } label: {
            Label("Update Now", systemImage: "arrow.down.circle")
                #if os(iOS)
                    .frame(maxWidth: .infinity)
                #endif
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }
}

// MARK: - SwiftUI Sheet Presentation Wrapper

#if os(macOS)
extension CoreUpdateAlertView {
    /// Tampilkan alert sebagai sheet di macOS
    static func makeAlertWindow(
        newVersion: String,
        onUpdate: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> NSWindow {
        let view = CoreUpdateAlertView(
            newVersion: newVersion,
            onUpdate: onUpdate,
            onDismiss: onDismiss
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 1)
        hosting.layoutSubtreeIfNeeded()
        let fittedSize = hosting.fittingSize

        let window = ReusableFunc.makeTitlelessWindow(
            contentView: hosting, size: fittedSize
        )
        window.center()

        return window
    }
}

extension AppDelegate {
    // MARK: - Core Database Update Layer

    func checkCoreDatabaseUpdate() {
        // Hanya check jika di bundle mode
        guard AppConfig.isUsingBundleMode else { return }

        Task.detached(priority: .low) { [weak self] in

            // Check update
            let result = await CoreUpdateChecker.checkAsync()

            guard case .updateAvailable(let newVersion) = result else { return }

            await MainActor.run { [weak self] in
                self?.showCoreUpdateAlert(newVersion: newVersion)
            }
        }
    }

    private func showCoreUpdateAlert(newVersion: String) {
        coreUpdateAlertWindow = CoreUpdateAlertView.makeAlertWindow(
            newVersion: newVersion,
            onUpdate: { [weak self] in
                guard let self else { return }
                NSApp.stopModal()
                self.coreUpdateAlertWindow?.orderOut(nil)
                self.performCoreDatabaseUpdate(to: newVersion)
            },
            onDismiss: { [weak self] in
                guard let self else { return }
                NSApp.stopModal()
                self.coreUpdateAlertWindow?.orderOut(nil)
                self.coreUpdateAlertWindow = nil
            }
        )

        NSApp.runModal(for: coreUpdateAlertWindow!)
    }

    private func performCoreDatabaseUpdate(to newVersion: String) {
        let downloader = CoreDatabaseDownloader()
        coreDownloader = downloader
        let state = CoreDownloadProgressState()
        state.phase = .downloading
        state.progress = 0
        state.detail = ""
        coreDownloadProgressState = state

        let view = CoreDownloadProgressView(
            state: state,
            onDownload: {},
            onChooseFolder: {},
            onQuit: {}
        )

        coreDownloadProgressView = view

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 1)
        hosting.layoutSubtreeIfNeeded()
        let fittedSize = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: fittedSize)

        let window = ReusableFunc.makeTitlelessWindow(
            contentView: hosting, size: fittedSize
        )

        window.center()

        coreDownloadProgressWindow = window
        NSApp.activate(ignoringOtherApps: true)

        let closeProgressWindow: () -> Void = { [weak self] in
            guard let self, let window = self.coreDownloadProgressWindow else { return }
            if let parent = NSApp.keyWindow, parent.sheets.contains(window) {
                parent.endSheet(window)
            } else {
                window.orderOut(nil)
            }
            window.close()
            cleanUpUpdaterState()
        }

        if let parent = NSApp.keyWindow {
            parent.beginSheet(window)
        } else {
            window.makeKeyAndOrderFront(nil)
        }

        downloader.updateToVersion(
            newVersion,
            onProgress: { [weak self] progress, detail in
                guard let self, let state = coreDownloadProgressState else { return }
                state.phase = .downloading
                state.progress = progress
                state.detail = detail
            },
            onCompletion: { [weak self] error in
                guard let self else { return }
                if let error {
                    coreDownloadProgressState?.phase = .error(error.localizedDescription)
                    closeProgressWindow()
                    ReusableFunc.showAlert(
                        title: "Update Failed",
                        message: error.localizedDescription
                    )
                } else {
                    // Berhasil - reload database
                    DatabaseManager.shared.reloadConnectionAndLibrary()

                    closeProgressWindow()

                    ReusableFunc.showAlert(
                        title: "Update Complete",
                        message: "Core database has been updated to \(newVersion)."
                    )
                }
            }
        )
    }

    private func cleanUpUpdaterState() {
        coreUpdateAlertWindow = nil
        coreDownloadProgressView = nil
        coreDownloadProgressWindow = nil
        coreDownloadProgressState = nil
        coreDownloader = nil
    }
}
#endif

// MARK: - Preview

#Preview {
    CoreUpdateAlertView(
        newVersion: "v1.0-core",
        onUpdate: {},
        onDismiss: {}
    )
}
