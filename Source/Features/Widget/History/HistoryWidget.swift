//
//  HistoryWidget.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import SwiftUI
import WidgetKit

struct HistoryWidget: Widget {
    let kind: String = "HistoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HistoryProvider()) { entry in
            HistoryView(entry: entry)
        }
        .configurationDisplayName(.history)
        .description(.quickAccessToYourRecentlyReadBooks)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabledIfAvailable()
    }
}
