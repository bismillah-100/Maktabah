//
//  HistoryProvider.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import Foundation
import WidgetKit

struct HistoryProvider: TimelineProvider {
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

    func getSnapshot(
        in context: Context,
        completion: @escaping (HistoryEntry) -> Void
    ) {
        let items = HistorySnapshot.loadLocal().map(mapHistoryItems) ?? []
        completion(HistoryEntry(date: Date(), history: items))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<HistoryEntry>) -> Void
    ) {
        CloudKitFetcher.shared.fetchActive { (snapshot: HistorySnapshot?) in
            let items = snapshot.map(mapHistoryItems) ?? []
            let entry = HistoryEntry(date: Date(), history: items)
            #if DEBUG
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
            #else
            let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            #endif
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
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
