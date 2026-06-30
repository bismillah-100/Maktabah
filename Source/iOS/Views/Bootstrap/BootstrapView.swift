//
//  BootstrapView.swift
//  Maktabah-iOS
//
//  Created by Ghoys Mawahib on 03/05/26.
//

import SwiftUI

struct iOSBootstrapView: View {
    @State private var bootstrapManager = iOSBootstrapManager()

    var body: some View {
        Group {
            if bootstrapManager.isReady {
                iOSMainView()
            } else {
                ZStack {
                    Color.appBackground
                        .ignoresSafeArea()

                    if bootstrapManager.isChecking {
                        ProgressView("Preparing Library...")
                    } else {
                        CoreDownloadProgressView(
                            state: bootstrapManager.coreDownloadState,
                            onDownload: { bootstrapManager.startDownload() },
                            onChooseFolder: { bootstrapManager.chooseLibraryFolder() },
                            onQuit: { cancellation() }
                        )
                        .padding()
                    }
                }
            }
        }
        .task {
            bootstrapManager.prepareIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .requireCoreDownload)) { notification in
            let isCancellable = notification.userInfo?["isCancellable"] as? Bool ?? false
            bootstrapManager.reloadLibrary(isCancellable: isCancellable)
        }
        .overlay {
            if bootstrapManager.showCoreUpdateAlert {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { }
                        .simultaneousGesture(DragGesture())

                    CoreUpdateAlertView(
                        newVersion: bootstrapManager.availableCoreVersion ?? "",
                        onUpdate: { bootstrapManager.performCoreUpdate() },
                        onDismiss: { bootstrapManager.showCoreUpdateAlert = false }
                    )
                    .zIndex(1)
                }
            }

            if bootstrapManager.isUpdating {
                iOSCoreUpdateProgressOverlayView(
                    state: bootstrapManager.coreDownloadState
                )
            }
        }
    }

    private func cancellation() {
        if bootstrapManager.isCancellable {
            bootstrapManager.cancelDownload()
        } else {
            ReusableFunc.showAlert(
                title: "core.modal.missingFiles.title".localized,
                message: "Database File Needed".localized
            )
        }
    }
}
