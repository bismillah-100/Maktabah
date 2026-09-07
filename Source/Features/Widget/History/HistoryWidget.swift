//
//  HistoryWidget.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import SwiftUI
import WidgetKit

@available(iOS 17.0, macOS 14.0, *)
struct HistoryWidget: Widget {
    let kind: String = "HistoryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HistoryConfigurationIntent.self,
            provider: HistoryProvider()
        ) { entry in
            HistoryView(entry: entry)
        }
        .configurationDisplayName("History")
        .description("Quick access to your recently read books.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
