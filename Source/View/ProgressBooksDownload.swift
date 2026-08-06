//
//  ProgressBooksDownload.swift
//  Maktabah
//
//  Created by MacBook on 02/03/26.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

import Observation

@MainActor
#if os(iOS)
@Observable
#endif
final class BundleArchiveDownloadProgressState: Identifiable {
    let id = UUID()

    enum Mode {
        case confirmation
        case downloading
        case integrating
    }
    enum PendingData {
        case single(book: BooksData, contentId: Int?)
        case bulk(books: [BooksData])
    }

    var pendingData: PendingData?

    #if os(macOS)
    @Published var title: String
    @Published var message: String
    @Published var detail: String
    @Published var progress: Double
    @Published var mode: Mode
    @Published var totalSizeString: String

    #elseif os(iOS)
    var title: String
    var message: String
    var detail: String
    var progress: Double
    var mode: Mode
    var totalSizeString: String
    #endif

    init(
        title: String,
        message: String,
        detail: String = "",
        progress: Double = 0,
        mode: Mode = .confirmation,
        totalSizeString: String = ""
    ) {
        self.title = title
        self.message = message
        self.detail = detail
        self.progress = progress
        self.mode = mode
        self.totalSizeString = totalSizeString
    }
}

struct BundleArchiveDownloadProgressView: View {
    #if os(macOS)
    @ObservedObject
    #endif
    var state: BundleArchiveDownloadProgressState
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with icon, title, and mode badge
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.95),
                                    Color.accentColor.opacity(0.65)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundStyle(.white)
                        .imageScale(.medium)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    let badgeText: String = {
                        switch state.mode {
                        case .confirmation:
                            return NSLocalizedString(
                                "Ready to Download",
                                comment: "Ready to download badge"
                            )
                        case .downloading:
                            return NSLocalizedString(
                                "Downloading",
                                comment: "Downloading badge"
                            )
                        case .integrating:
                            return NSLocalizedString(
                                "Integrating",
                                comment: "Integrating badge"
                            )
                        }
                    }()
                    Text(badgeText)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            // Message / description
            if state.mode == .confirmation && !state.totalSizeString.isEmpty {
                Text("\(state.message) (\(state.totalSizeString))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            } else {
                Text(state.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(state.mode == .confirmation ? nil : 2)
                    .multilineTextAlignment(.leading)
            }

            if state.mode != .confirmation {
                VStack(alignment: .leading, spacing: 8) {
                    if state.mode == .integrating {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                    } else {
                        ProgressView(value: state.progress)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text(state.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Spacer()

                        let percent = max(0, min(1, state.progress))
                        Text("\(Int((percent * 100).rounded()))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                if state.mode != .integrating {
                    HStack {
                        Spacer()
                        Button(
                            NSLocalizedString(
                                "Cancel",
                                comment: "Cancel active archive download button"
                            ),
                            action: onCancel
                        )
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Spacer()
                    Button(
                        NSLocalizedString(
                            "Cancel",
                            comment: "Cancel action button"
                        ),
                        action: onCancel
                    )
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                    Button(
                        String(localized: "Download"),
                        action: onConfirm
                    )
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                #if os(iOS)
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
                #endif
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .frame(maxWidth: 380, minHeight: 200)
        .animation(.easeInOut(duration: 0.2), value: state.mode)
        .animation(.linear(duration: 0.15), value: state.progress)
        .controlSize(.large)
    }
}

struct iOSBookDownloadProgressView: View {
    var state: BundleArchiveDownloadProgressState
    var onConfirm: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text(state.title)
                            .font(.caption)
                            .fontWeight(.bold)
                            .lineLimit(1)
                    }

                    if state.mode == .confirmation {
                        Text(state.message + (state.totalSizeString.isEmpty ? "" : " (\(state.totalSizeString))"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    } else {
                        Text(state.message)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if state.mode == .confirmation {
                    HStack(spacing: 2) {
                        Button(action: { onCancel?() }) {
                            Image(systemName: "xmark")
                        }
                        .buttonBorderShapeCircle()
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button(action: { onConfirm?() }) {
                            Image(systemName: "checkmark")
                        }
                        .buttonBorderShapeCircle()
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                } else {
                    Text(state.detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if state.mode != .confirmation {
                ProgressView(value: state.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

extension View {
    /// Memberikan bentuk lingkaran pada border tombol jika tersedia di sistem operasi.
    /// Jika tidak tersedia, maka tidak akan menerapkan perubahan bentuk (fallback ke default).
    @ViewBuilder
    func buttonBorderShapeCircle() -> some View {
        if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
            self.buttonBorderShape(.circle)
        } else {
            self
        }
    }
}

// MARK: - BookIntegrateModalCenter

#if os(macOS)

extension BundleArchiveDownloadProgressState: ObservableObject {}

/// Modal konfirmasi + progress untuk proses integrasi per-book
/// (download kitab → copy tables → rebuild FTS).
///
/// Alur pemakaian dari `connectBookWithBundleFallback`:
/// ```swift
/// let confirmed = await BookIntegrateModalCenter.shared
///     .presentAndWaitForConfirmation(book: book)
/// guard confirmed else { throw CancellationError() }
///
/// defer { Task { @MainActor in BookIntegrateModalCenter.shared.dismiss() } }
///
/// try await BookArchiveIntegrator.shared.ensureBookIntegrated(
///     book,
///     onIntegrating: {
///         await BookIntegrateModalCenter.shared.showIntegrating()
///     }
/// )
/// ```
@MainActor
final class BookIntegrateModalCenter {
    static let shared = BookIntegrateModalCenter()

    private var sheetWindow: NSWindow?
    private var progressState: BundleArchiveDownloadProgressState?
    private var isModalRunning = false
    private var confirmationContinuation: CheckedContinuation<Bool, Never>?

    private init() {}

    // MARK: - Public API

    /// Tampilkan modal konfirmasi dan tunggu pilihan user.
    /// Mengembalikan `true` jika user tekan "Download", `false` jika Cancel.
    func presentAndWaitForConfirmation(book: BooksData) async -> Bool {
        internalDismiss(cancelContinuation: true)

        let bodyFormat = String(
            localized: "Confirm Download Message"
        )
        let message = String(
            format: bodyFormat,
            locale: Locale.current,
            book.book
        )

        var sizeString = ""
        if let size = book.compressedDownloadSize, size > 0 {
            sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        let state = BundleArchiveDownloadProgressState(
            title: book.book,
            message: message,
            mode: .confirmation,
            totalSizeString: sizeString
        )
        progressState = state

        let hostingView = NSHostingView(
            rootView: BundleArchiveDownloadProgressView(
                state: state,
                onConfirm: { [weak self] in self?.confirmAndStartProgress() },
                onCancel: { [weak self] in self?.cancelDownload() }
            )
        )
        let height = 200
        let width = 380
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.autoresizingMask = [.width, .height]

        let w = ReusableFunc.makeTitlelessWindow(
            contentView: hostingView,
            size: .init(width: width, height: height)
        )
        sheetWindow = w
        w.center()
        w.makeKeyAndOrderFront(nil)

        return await withCheckedContinuation { continuation in
            confirmationContinuation = continuation
            isModalRunning = true
            NSApp.runModal(for: w)
            isModalRunning = false
        }
    }

    /// Transisi ke fase integrasi (copy tables + rebuild FTS).
    /// Progress bar menjadi indeterminate, tombol Cancel hilang.
    func showIntegrating() {
        guard let state = progressState else { return }
        state.mode = .integrating
        state.title = NSLocalizedString(
            "Integrating Book",
            comment: "Book integrate phase title"
        )
        state.message = NSLocalizedString(
            "Copying tables and rebuilding FTS index...",
            comment: "Book integrate phase message"
        )
        state.detail = NSLocalizedString(
            "Please wait, this process cannot be cancelled.",
            comment: "Book integrate phase detail"
        )
        state.progress = 0
        updateWindowSize(height: 180, animated: true)
    }

    func dismiss() {
        internalDismiss(cancelContinuation: true)
    }

    // MARK: - Private helpers

    private func confirmAndStartProgress() {
        guard let state = progressState else { return }

        if isModalRunning {
            NSApp.stopModal()
            isModalRunning = false
        }

        state.mode = .downloading
        state.message = NSLocalizedString(
            "Downloading book file from server...",
            comment: "Book integrate downloading message"
        )
        state.detail = ""
        state.progress = 0

        updateWindowSize(height: 180, animated: true)

        if let continuation = confirmationContinuation {
            confirmationContinuation = nil
            continuation.resume(returning: true)
        }
    }

    private func cancelDownload() {
        if let continuation = confirmationContinuation {
            confirmationContinuation = nil
            continuation.resume(returning: false)
        }
        internalDismiss(cancelContinuation: false)
    }

    private func internalDismiss(cancelContinuation: Bool) {
        if isModalRunning {
            NSApp.stopModal()
            isModalRunning = false
        }

        if let w = sheetWindow {
            w.orderOut(nil)
            w.close()
            sheetWindow = nil
        }

        if cancelContinuation, let continuation = confirmationContinuation {
            confirmationContinuation = nil
            continuation.resume(returning: false)
        }

        progressState = nil
    }

    private func updateWindowSize(height: CGFloat, animated: Bool) {
        guard let w = sheetWindow else { return }
        let newSize = NSSize(width: 380, height: height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                w.animator().setContentSize(newSize)
            }
        } else {
            w.setContentSize(newSize)
        }
    }
}

#endif
