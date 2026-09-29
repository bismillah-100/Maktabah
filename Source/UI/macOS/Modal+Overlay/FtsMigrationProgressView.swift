//
//  FtsMigrationProgressView.swift
//  Maktabah
//

import SwiftUI

struct FtsMigrationProgressView: View {
    var ftsManager: FtsMigrationManager = .shared

    var onCancel: (() -> Void)?
    var onUpdate: (() async throws -> Void)?

    @State private var isFinishing = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                    .font(.title2)
                Text(.ftsMigrationTitle)
                    .font(.headline)
                Spacer()
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            if ftsManager.isMigrating || isFinishing {
                FtsMigrationProgressSection(ftsManager: ftsManager)
                    .padding(.vertical, 8)

                if ftsManager.isMigrating {
                    Button(role: .cancel) {
                        ftsManager.cancelMigration()
                        onCancel?()
                    } label: {
                        Text(.ftsMigrationCancelBtn)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(.ftsMigrationDesc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(.ftsMigrationExample)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.1))
                        .multilineTextAlignment(.leading)
                        .cornerRadius(8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button(role: .cancel) {
                        onCancel?()
                    } label: {
                        Text(.ftsMigrationCancelBtn)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        isFinishing = true
                        errorMessage = nil
                        Task {
                            do {
                                if let onUpdate {
                                    try await onUpdate()
                                } else {
                                    try await ftsManager.performMigration()
                                }
                            } catch {
                                await MainActor.run {
                                    isFinishing = false
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                    } label: {
                        Text(.ftsMigrationUpdateBtn)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                }
                .padding(.top, 8)
            }
        }
        .padding(20)
        #if os(iOS)
        .background(Color.appBackground)
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
        .cornerRadius(12)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 450)
    }
}

struct FtsMigrationProgressSection: View {
    var ftsManager: FtsMigrationManager = .shared

    private var statusAreaMinHeight: CGFloat {
        let maxConcurrentLines = min(4, max(1, ftsManager.totalArchivesToMigrate))
        return CGFloat(maxConcurrentLines * 18 + 20)
    }

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: ftsManager.progress, total: 1.0)
                .progressViewStyle(.linear)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(.ftsMigrationProcess))
                .accessibilityValue(Text(.percent(int: Int(ftsManager.progress * 100))))

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if ftsManager.activeArchiveStatuses.isEmpty {
                        Text(ftsManager.progress >= 1.0 ? "Done" : .preparingMigration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        ForEach(ftsManager.activeArchiveStatuses.keys.sorted(), id: \.self) { key in
                            if let status = ftsManager.activeArchiveStatuses[key] {
                                Text(status)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if ftsManager.totalBooksToMigrate > 0 {
                        Text("\(ftsManager.completedBooksCount) / \(ftsManager.totalBooksToMigrate) buku")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minHeight: statusAreaMinHeight, alignment: .topLeading)

                Spacer()

                Text("\(Int(ftsManager.progress * 100))%")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
        }
    }
}

