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
    static let title: LocalizedStringResource = "History Widget"
    static let description = IntentDescription("Displays your recently read books.")
}

struct HistoryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HistoryEntry {
        HistoryEntry(
            date: Date(),
            history: [
                HistoryItem(
                    id: "1",
                    bkId: 1,
                    bookTitle: "Kitab Al-Umm",
                    lastReadContentId: 1,
                    lastReadTime: Int64(Date().timeIntervalSince1970)
                ),
                HistoryItem(
                    id: "2",
                    bkId: 2,
                    bookTitle: "Sahih Al-Bukhari",
                    lastReadContentId: 1,
                    lastReadTime: Int64(Date().timeIntervalSince1970) - 3600
                ),
                HistoryItem(
                    id: "3",
                    bkId: 3,
                    bookTitle: "Al-Majmu' Syarh Al-Muhadzdzab",
                    lastReadContentId: 1,
                    lastReadTime: Int64(Date().timeIntervalSince1970) - 7200
                ),
                HistoryItem(
                    id: "4",
                    bkId: 4,
                    bookTitle: "Tafsir Ibn Katsir",
                    lastReadContentId: 1,
                    lastReadTime: Int64(Date().timeIntervalSince1970) - 10800
                ),
                HistoryItem(
                    id: "5",
                    bkId: 5,
                    bookTitle: "Riyadhus Shalihin",
                    lastReadContentId: 1,
                    lastReadTime: Int64(Date().timeIntervalSince1970) - 14400
                ),
                HistoryItem(
                    id: "6",
                    bkId: 6,
                    bookTitle: "Sunan At-Tirmidzi",
                    lastReadContentId: 1,
                    lastReadTime: Int64(Date().timeIntervalSince1970) - 18000
                ),
            ]
        )
    }

    func snapshot(for configuration: HistoryConfigurationIntent, in context: Context) async -> HistoryEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        let snapshot = await HistorySnapshot.loadLocal()
        let items = snapshot.map(mapHistoryItems) ?? []
        if items.isEmpty {
            return placeholder(in: context)
        }
        return HistoryEntry(date: Date(), history: items)
    }

    func timeline(for configuration: HistoryConfigurationIntent, in context: Context) async -> Timeline<HistoryEntry> {
        let snapshot: HistorySnapshot? = await CloudKitFetcher.shared.fetchActive()
        let items = snapshot.map(mapHistoryItems) ?? []
        let entry = HistoryEntry(date: Date(), history: items)
        return Timeline(entries: [entry], policy: .nextRefresh)
    }

    private func mapHistoryItems(from snapshot: HistorySnapshot) -> [HistoryItem] {
        snapshot.items.map {
            HistoryItem(
                id: $0.id,
                bkId: $0.bookId,
                bookTitle: $0.bookTitle,
                lastReadContentId: $0.contentId,
                lastReadTime: Int64($0.date.timeIntervalSince1970)
            )
        }
    }
}
