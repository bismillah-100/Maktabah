//
//  AnnotationProvider.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import AppIntents
import WidgetKit

struct AnnotationConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Annotation Widget"
    static var description = IntentDescription("Displays your recent annotations.")
}

struct AnnotationProvider: AppIntentTimelineProvider {
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

    func snapshot(for configuration: AnnotationConfigurationIntent, in context: Context) async -> AnnotationEntry {
        let snapshot = await AnnotationSnapshot.loadLocal()
        let items = snapshot.map(mapAnnotationItems) ?? []
        return AnnotationEntry(date: Date(), annotations: items)
    }

    func timeline(for configuration: AnnotationConfigurationIntent, in context: Context) async -> Timeline<AnnotationEntry> {
        let snapshot: AnnotationSnapshot? = await CloudKitFetcher.shared.fetchActive()
        let items = snapshot.map(mapAnnotationItems) ?? []
        let entry = AnnotationEntry(date: Date(), annotations: items)
        #if DEBUG
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
        #else
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        #endif
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func mapAnnotationItems(from snapshot: AnnotationSnapshot) -> [AnnotationWidgetItem] {
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
