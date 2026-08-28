//
//  AnnotationWidget.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import SwiftUI
import WidgetKit

struct AnnotationWidget: Widget {
    let kind: String = "AnnotationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AnnotationProvider()) { entry in
            AnnotationView(entry: entry)
        }
        .configurationDisplayName(.annotations)
        .description(.quickAccessYourRecentAnnotations)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabledIfAvailable()
    }
}
