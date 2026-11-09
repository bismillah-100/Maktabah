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
                makePlaceholderItem(id: 1, title: "Kitab Al-Umm", context: "قال الشافعي رحمه الله تعالى في كتاب الأم...", colorHex: "#FF9300", type: 0),
                makePlaceholderItem(id: 2, title: "Sahih Al-Bukhari", context: "إنما الأعمال بالنيات وإنما لكل امرئ ما نوى...", colorHex: "#34C759", type: 0),
                makePlaceholderItem(id: 3, title: "Al-Majmu' Syarh Al-Muhadzdzab", context: "فرع في بيان المسائل المتعلقة بالنية في الطهارة...", colorHex: "#007AFF", type: 1),
                makePlaceholderItem(id: 4, title: "Tafsir Al-Qurtubi", context: "القول في تأويل قوله تعالى واذكروا نعمة الله عليكم...", colorHex: "#AF52DE", type: 0),
                makePlaceholderItem(id: 5, title: "Riyadhus Shalihin", context: "باب الصبر والمرابطة على الطاعات...", colorHex: "#FF9300", type: 0),
                makePlaceholderItem(id: 6, title: "Sunan Abu Dawud", context: "كتاب الطهارة وما يوجب الوضوء...", colorHex: "#FF2D55", type: 1),
            ]
        )
    }

    private func makePlaceholderItem(
        id: Int64,
        title: String,
        context: String,
        colorHex: String,
        type: Int
    ) -> AnnotationWidgetItem {
        let timeOffset = (id - 1) * 3600
        return AnnotationWidgetItem(
            id: id,
            bkId: Int(id),
            bookTitle: title,
            contentId: 1,
            context: context,
            colorHex: colorHex,
            type: type,
            createdAt: Int64(Date().timeIntervalSince1970) - timeOffset
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
