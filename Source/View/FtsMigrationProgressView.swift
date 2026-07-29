//
//  FtsMigrationProgressView.swift
//  Maktabah
//

import SwiftUI

struct FtsMigrationProgressView: View {
    #if os(iOS)
    var ftsManager: FtsMigrationManager = .shared
    #else
    @ObservedObject var ftsManager: FtsMigrationManager = .shared
    #endif

    var onCancel: (() -> Void)? = nil
    var onUpdate: (() async throws -> Void)? = nil

    @State private var isFinishing = false

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
                        Task {
                            if let onUpdate {
                                try? await onUpdate()
                            } else {
                                try? await ftsManager.performMigration()
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
    #if os(iOS)
    var ftsManager: FtsMigrationManager = .shared
    #else
    @ObservedObject var ftsManager: FtsMigrationManager = .shared
    #endif

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: ftsManager.isMigrating ? ftsManager.progress : 1.0)
                .progressViewStyle(.linear)

            if ftsManager.isMigrating {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ftsManager.activeArchiveStatuses.keys.sorted(), id: \.self) { key in
                            if let status = ftsManager.activeArchiveStatuses[key] {
                                Text(status)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if ftsManager.totalBooksToMigrate > 0 {
                            Text("\(ftsManager.completedBooksCount) / \(ftsManager.totalBooksToMigrate) buku")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(Int(ftsManager.progress * 100))%")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
        }
    }
}
