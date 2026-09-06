//
//  AnnotationProvider.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import WidgetKit

struct AnnotationProvider: SnapshotTimelineProvider {
    typealias Snapshot = AnnotationSnapshot

    func placeholder(in context: Context) -> AnnotationEntry {
        AnnotationEntry(
            date: Date(),
            annotations: [
                AnnotationWidgetItem(
                    id: 1,
                    bkId: 1,
                    bookTitle: "Kitab Al-Umm",
                    contentId: 1,
                    context: "Contoh teks anotasi...",
                    colorHex: "#FF9300",
                    type: 0,
                    createdAt: Int64(Date().timeIntervalSince1970)
                ),
            ]
        )
    }

    func makeEntry(date: Date, items: [AnnotationWidgetItem]) -> AnnotationEntry {
        AnnotationEntry(date: date, annotations: items)
    }

    func mapItems(from snapshot: AnnotationSnapshot) -> [AnnotationWidgetItem] {
        snapshot.items.map {
            AnnotationWidgetItem(
                id: Int64($0.id) ?? Int64($0.id.hashValue),
                bkId: $0.bookId,
                bookTitle: $0.bookTitle,
                contentId: 1,
                context: $0.content,
                colorHex: $0.colorHex,
                type: $0.type,
                createdAt: Int64($0.date.timeIntervalSince1970)
            )
        }
    }
}
