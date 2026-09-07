//
//  Components.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import SwiftUI
import WidgetKit

struct WidgetHeaderView: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    var family: WidgetFamily

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(family == .systemSmall
                    ? .caption.bold() : .headline)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Image(systemName: systemImage)
                .font(family == .systemSmall
                    ? .caption2.bold() : .subheadline.bold())
                .foregroundColor(iconColor)
        }
    }
}

struct WidgetEmptyView: View {
    let message: String

    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        }
    }
}

struct WidgetCardView: View {
    let barColor: Color
    let destinationURL: URL
    let title: String
    let subtitle: String
    var family: WidgetFamily
    var isFirstItem: Bool = true

    var body: some View {
        Link(destination: destinationURL) {
            HStack(spacing: 4.5) {
                Capsule(style: .circular)
                    .fill(barColor)
                    .frame(width: 3.5)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(barColor.opacity(0.12))
            )
        }
    }

    private var fontSize: CGFloat {
        #if os(iOS)
        family == .systemSmall ? 14 : 15.5
        #else
        family == .systemSmall ? 12 : 13.5
        #endif
    }

    private var customFont: PlatformFont {
        PlatformFont(name: "NotoNaskhArabic-Medium", size: fontSize)
            ?? .systemFont(ofSize: fontSize)
    }

    var content: some View {
        Group {
            if family == .systemLarge {
                largeCardContent
            } else if isFirstItem {
                firstItemContent
            } else {
                subsequentItemContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, family == .systemLarge ? 3 : (isFirstItem ? 3.5 : 2.5))
        .padding(.trailing, 4)
        .multilineTextAlignment(.leading)
    }

    private var cleanTitle: String {
        title
            .replacing("\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Layout Variants

    private var firstItemContent: some View {
        ViewThatFits(in: .horizontal) {
            // Varian 1:
            // Judul muat 1 baris di layar perangkat
            // -> Tampilkan Judul (1 baris) + Subtitle
            VStack(alignment: .leading, spacing: 0) {
                Text(cleanTitle)
                    .font(Font(customFont))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: family == .systemSmall ? 9 : 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            }

            // Varian 2:
            // Judul terlalu panjang untuk 1 baris (menjadi 2 baris) ->
            // Beralih ke 2 baris rapat tanpa subtitle
            TightArabicText(
                text: cleanTitle,
                fontSize: fontSize,
                maxLines: 2,
                lineSpacing: -5
            )
        }
    }

    private var subsequentItemContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(cleanTitle)
                .font(Font(customFont))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    private var largeCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(cleanTitle)
                .font(Font(customFont))
                .foregroundColor(.primary)
                .lineLimit(1)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct WidgetContainerView<Content: View>: View {
    var family: WidgetFamily
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: family == .systemSmall
                ? 5 : (family == .systemLarge ? 5 : 6)
        ) {
            content()
        }
        .padding(family == .systemSmall ? 10 : 12)
        .containerBackground(.thickMaterial, for: .widget)
    }
}
