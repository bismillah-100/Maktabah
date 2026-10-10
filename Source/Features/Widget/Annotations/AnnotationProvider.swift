//
//  AnnotationProvider.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import AppIntents
import Foundation
import WidgetKit

struct AnnotationConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Annotation Widget"
    static let description = IntentDescription("Displays your recent annotations.")
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
                    context: "قال الشافعي رحمه الله تعالى في كتاب الأم...",
                    colorHex: "#FF9300",
                    type: 0,
                    createdAt: Int64(Date().timeIntervalSince1970)
                ),
                AnnotationWidgetItem(
                    id: 2,
                    bkId: 2,
                    bookTitle: "Sahih Al-Bukhari",
                    contentId: 1,
                    context: "إنما الأعمال بالنيات وإنما لكل امرئ ما نوى...",
                    colorHex: "#34C759",
                    type: 0,
                    createdAt: Int64(Date().timeIntervalSince1970) - 3600
                ),
                AnnotationWidgetItem(
                    id: 3,
                    bkId: 3,
                    bookTitle: "Al-Majmu' Syarh Al-Muhadzdzab",
                    contentId: 1,
                    context: "فرع في بيان المسائل المتعلقة بالنية في الطهارة...",
                    colorHex: "#007AFF",
                    type: 1,
                    createdAt: Int64(Date().timeIntervalSince1970) - 7200
                ),
                AnnotationWidgetItem(
                    id: 4,
                    bkId: 4,
                    bookTitle: "Tafsir Al-Qurtubi",
                    contentId: 1,
                    context: "القول في تأويل قوله تعالى واذكروا نعمة الله عليكم...",
                    colorHex: "#AF52DE",
                    type: 0,
                    createdAt: Int64(Date().timeIntervalSince1970) - 10800
                ),
                AnnotationWidgetItem(
                    id: 5,
                    bkId: 5,
                    bookTitle: "Riyadhus Shalihin",
                    contentId: 1,
                    context: "باب الصبر والمرابطة على الطاعات...",
                    colorHex: "#FF9300",
                    type: 0,
                    createdAt: Int64(Date().timeIntervalSince1970) - 14400
                ),
                AnnotationWidgetItem(
                    id: 6,
                    bkId: 6,
                    bookTitle: "Sunan Abu Dawud",
                    contentId: 1,
                    context: "كتاب الطهارة وما يوجب الوضوء...",
                    colorHex: "#FF2D55",
                    type: 1,
                    createdAt: Int64(Date().timeIntervalSince1970) - 18000
                ),
            ]
        )
    }

    func snapshot(for configuration: AnnotationConfigurationIntent, in context: Context) async -> AnnotationEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        let snapshot = await AnnotationSnapshot.loadLocal()
        let items = snapshot.map(mapAnnotationItems) ?? []
        if items.isEmpty {
            return placeholder(in: context)
        }
        return AnnotationEntry(date: Date(), annotations: items)
    }

    func timeline(for configuration: AnnotationConfigurationIntent, in context: Context) async -> Timeline<AnnotationEntry> {
        let snapshot: AnnotationSnapshot? = await CloudKitFetcher.shared.fetchActive()
        let items = snapshot.map(mapAnnotationItems) ?? []
        let entry = AnnotationEntry(date: Date(), annotations: items)
        return Timeline(entries: [entry], policy: .nextRefresh)
    }

    private func mapAnnotationItems(from snapshot: AnnotationSnapshot) -> [AnnotationWidgetItem] {
        snapshot.items.map {
            AnnotationWidgetItem(
                id: Int64($0.id) ?? Int64($0.id.hashValue),
                bkId: $0.bookId,
                bookTitle: $0.bookTitle,
                contentId: $0.contentId,
                context: $0.content,
                colorHex: $0.colorHex,
                type: $0.type,
                createdAt: Int64($0.date.timeIntervalSince1970)
            )
        }
    }
}
