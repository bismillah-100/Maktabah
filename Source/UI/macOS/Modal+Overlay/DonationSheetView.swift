//
//  DonationSheetView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 20/08/26.
//

import SwiftUI

#if os(iOS)
private struct DonationSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
#endif

struct DonationSheetView: View {
    var url: URL = .init(string: "https://sociabuzz.com/ghoysmawahib/support")!
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isPulsing = false
    @State private var showThankYou = false
    @State private var thankYouIconScale: CGFloat = 0.4
    #if os(iOS)
    @State private var contentHeight: CGFloat = 0
    #endif

    @ObservedObject private var donationManager = DonationManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                sheetBackground

                VStack(spacing: 24) {
                    headerSection
                    allocationCard
                    actionSection
                }
                .padding(24)
                .opacity(showThankYou ? 0 : 1)
                .allowsHitTesting(!showThankYou)
                .background {
                    #if os(iOS)
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: DonationSheetHeightKey.self, value: geo.size.height
                        )
                    }
                    #endif
                }

                if showThankYou {
                    thankYouSection
                        .padding(24)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.88).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: showThankYou)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(
                    placement: donationManager.hasDonated
                        ? .confirmationAction
                        : .cancellationAction
                ) {
                    Button(role: .cancel) {
                        dismissSheet()
                    } label: {
                        Text(donationManager.hasDonated
                            ? "Done"
                            : .Donation.laterBtn)
                    }
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    #endif
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 440)
        #else
        .themeTint()
        .presentationBackground(Color.appBackground)
        .onPreferenceChange(DonationSheetHeightKey.self) { measured in
            if measured > 0 {
                contentHeight = measured + 24
            }
        }
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight)] : [.fraction(0.68)])
        .presentationDragIndicator(.visible)
        #endif
        .onDisappear {
            donationManager.dismiss()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var sheetBackground: some View {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
        #else
        Color.appBackground
            .ignoresSafeArea()
        #endif
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .foregroundStyle(.pink.opacity(isPulsing ? 0.2 : 0.08))
                    .frame(width: 68, height: 68)
                    .scaleEffect(isPulsing ? 1.18 : 0.95)
                Image(systemName: "heart.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.pink.opacity(1.0))
                    .scaleEffect(isPulsing ? 1.18 : 1.0)
            }
            .animation(.easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true), value: isPulsing)
            .padding(.top, 4)
            .onAppear {
                isPulsing = true
            }

            VStack(spacing: 6) {
                Text(donationManager.hasDonated
                    ? .Donation.supportThanks
                    : .Donation.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Text(.Donation.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var allocationCard: some View {
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
                .fill(Color.appCellBackground)
            #endif
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "qrcode")
                    .font(.caption)
                Text(.Donation.paymentInfo)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.85)
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
                .padding(.vertical, 10)
            }
            .foregroundStyle(Color.white)
            .tint(.green)
            #if os(iOS)
            .prominentButtonStyleIfAvailable()
            .buttonBorderShape(.capsule)
            #else
            .buttonStyle(.borderedProminent)
            .clipShape(.capsule)
            #endif

            Button {
                handleAlreadyDonated()
            } label: {
                Text(.Donation.alreadyDonated)
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var thankYouSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "heart.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.pink)
            }
            .scaleEffect(thankYouIconScale)

            VStack(spacing: 6) {
                Text(.Donation.supportThanks)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Text(.Donation.wishYouAllTheBest)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSheet()
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                thankYouIconScale = 1.0
            }
        }
    }

    private func handleAlreadyDonated() {
        donationManager.markAsDonated()

        #if os(iOS)
        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.success)
        #endif

        withAnimation {
            showThankYou = true
        }

        Task {
            try? await Task.sleep(for: .seconds(1.8))
            await MainActor.run {
                dismissSheet()
            }
        }
    }

    private func dismissSheet() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func supportItem(
        icon: String,
        color: Color,
        title: LocalizedStringResource,
        description: LocalizedStringResource
    ) -> some View {
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
