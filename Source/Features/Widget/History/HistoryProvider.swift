//
//  HistoryProvider.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import AppIntents
import Foundation
import WidgetKit

struct HistoryConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "History Widget"
    static var description = IntentDescription("Displays your recently read books.")
}

struct HistoryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HistoryEntry {
        HistoryEntry(
            date: Date(),
            history: [
                HistoryItem(
                    bkId: 1,
                    bookTitle: "Kitab Al-Umm",
                    lastReadContentId: 1,
                    lastReadTime: Int64(Date().timeIntervalSince1970)
                ),
            ]
        )
    }

    func snapshot(for configuration: HistoryConfigurationIntent, in context: Context) async -> HistoryEntry {
        let snapshot = await HistorySnapshot.loadLocal()
        let items = snapshot.map(mapHistoryItems) ?? []
        return HistoryEntry(date: Date(), history: items)
    }

    func timeline(for configuration: HistoryConfigurationIntent, in context: Context) async -> Timeline<HistoryEntry> {
        let snapshot: HistorySnapshot? = await CloudKitFetcher.shared.fetchActive()
        let items = snapshot.map(mapHistoryItems) ?? []
        let entry = HistoryEntry(date: Date(), history: items)
        #if DEBUG
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
        #else
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        #endif
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func mapHistoryItems(from snapshot: HistorySnapshot) -> [HistoryItem] {
        snapshot.items.map {
            HistoryItem(
                bkId: $0.bookId,
                bookTitle: $0.bookTitle,
                lastReadContentId: $0.contentId,
                lastReadTime: Int64($0.date.timeIntervalSince1970)
            )
        }
    }
}
