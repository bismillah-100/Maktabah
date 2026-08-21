//
//  DonationSheetView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 20/08/26.
//


import SwiftUI

struct DonationSheetView: View {
    var url: URL = URL(string: "https://sociabuzz.com/ghoysmawahib/support")!
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 24) {
            // Header Visual & Judul
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(isPulsing ? 0.2 : 0.08))
                        .frame(width: 68, height: 68)
                        .scaleEffect(isPulsing ? 1.18 : 0.95)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.pink)
                        .scaleEffect(isPulsing ? 1.18 : 1.0)
                }
                .padding(.top, 8)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }

                VStack(spacing: 6) {
                    Text(.Donation.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(.Donation.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Poin-poin Alokasi Dukungan
            VStack(spacing: 12) {
                supportItem(
                    icon: "checkmark.seal.fill",
                    color: .green,
                    title: .Donation.freeTitle,
                    description: .Donation.freeDesc
                )

                supportItem(
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue,
                    title: .Donation.maintTitle,
                    description: .Donation.maintDesc
                )

                supportItem(
                    icon: "book.pages.fill",
                    color: .orange,
                    title: .Donation.researchTitle,
                    description: .Donation.researchDesc
                )
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    #if os(macOS)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    #else
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    #endif
            }

            // Info Pembayaran & Tombol Aksi
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "qrcode")
                        .font(.caption)
                    Text(.Donation.paymentInfo)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 8) {
                        Text(.Donation.donateBtn)
                            .font(.headline)
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(role: .cancel) {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(.Donation.laterBtn)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: 460)
        #if os(macOS)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationDetents([.fraction(0.68), .large])
        .presentationDragIndicator(.visible)
        #endif
        .onDisappear {
            DonationManager.shared.dismiss()
        }
    }


    private func supportItem(icon: String, color: Color, title: LocalizedStringResource, description: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview("Sheet Preview") {
    DonationSheetView()
}
