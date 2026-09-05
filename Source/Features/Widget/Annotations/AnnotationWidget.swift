//
//  AnnotationWidget.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import SwiftUI
import WidgetKit

@available(iOS 17.0, macOS 14.0, *)
struct AnnotationWidget: Widget {
    let kind: String = "AnnotationWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: AnnotationConfigurationIntent.self,
            provider: AnnotationProvider()
        ) { entry in
            AnnotationView(entry: entry)
        }
        .configurationDisplayName(.annotations)
        .description(.quickAccessYourRecentAnnotations)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabledIfAvailable()
    }
}
