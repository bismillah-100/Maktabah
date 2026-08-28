//
//  HistoryWidgetView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import AppIntents
import SwiftUI
import WidgetKit

struct HistoryView: View {
    @Environment(\.widgetFamily) var family
    var entry: HistoryProvider.Entry

    var maxItems: Int {
        family.maxItemCount
    }

    var displayedHistory: [HistoryItem] {
        Array(entry.history.prefix(maxItems))
    }

    var body: some View {
        WidgetContainerView(family: family) {
            headerView

            if displayedHistory.isEmpty {
                WidgetEmptyView(
                    message: String(localized: .noHistoryFound)
                )
            } else {
                ForEach(
                    Array(displayedHistory.enumerated()),
                    id: \.element.id
                ) { index, item in
                    historyLink(for: item, isFirstItem: index == 0)
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }

    private var headerView: some View {
        WidgetHeaderView(
            title: String(localized: .recentHistory),
            systemImage: "clock.arrow.circlepath",
            iconColor: .orange,
            family: family
        )
    }

    private func historyLink(
        for item: HistoryItem,
        isFirstItem: Bool
    ) -> some View {
        let destinationURL = WidgetDeepLink.history(
            bkId: item.bkId, contentId: item.lastReadContentId
        ).url
        let title = item.bookTitle ?? "Book ID: \(item.bkId)"
        let targetDate = Date(
            timeIntervalSince1970: TimeInterval(item.lastReadTime)
        )
        let subtitle = targetDate.formatted(
            .relative(presentation: .named)
        )

        return WidgetCardView(
            barColor: .orange,
            destinationURL: destinationURL,
            title: title,
            subtitle: subtitle,
            family: family,
            isFirstItem: isFirstItem
        )
    }
}
