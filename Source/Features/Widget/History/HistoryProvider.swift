//
//  HistoryProvider.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import Foundation
import WidgetKit

struct HistoryProvider: SnapshotTimelineProvider {
    typealias Snapshot = HistorySnapshot

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

    func makeEntry(date: Date, items: [HistoryItem]) -> HistoryEntry {
        HistoryEntry(date: date, history: items)
    }

    func mapItems(from snapshot: HistorySnapshot) -> [HistoryItem] {
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
