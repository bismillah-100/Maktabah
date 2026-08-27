//
//  iOSCoreUpdateProgressOverlayView.swift
//  Maktabah-iOS
//
//  Created by Ghoys Mawahib on 05/06/26.
//

import SwiftUI

struct iOSCoreUpdateProgressOverlayView: View {
    var state: CoreDownloadProgressState

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Updating Library")
                    .font(.headline)

                VStack(spacing: 8) {
                    ProgressView(value: state.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 260)

                    HStack {
                        Text(state.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int((max(0, min(1, state.progress)) * 100).rounded()))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .frame(width: 260)
                }

                if case .error(let message) = state.phase {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            )
        }
    }
}
