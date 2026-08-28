//
//  AnnotationView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import SwiftUI

struct AnnotationView: View {
    @Environment(\.widgetFamily) var family
    var entry: AnnotationProvider.Entry

    var maxItems: Int {
        family.maxItemCount
    }

    var displayedAnnotations: [AnnotationWidgetItem] {
        Array(entry.annotations.prefix(maxItems))
    }

    var body: some View {
        WidgetContainerView(family: family) {
            headerView

            if displayedAnnotations.isEmpty {
                WidgetEmptyView(
                    message: String(localized: .noAnnotationsFound)
                )
            } else {
                ForEach(
                    Array(displayedAnnotations.enumerated()),
                    id: \.element.id
                ) { index, annotation in
                    annotationLink(for: annotation, isFirstItem: index == 0)
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }

    private var headerView: some View {
        WidgetHeaderView(
            title: String(localized: .recentAnnotations),
            systemImage: "quote.closing",
            iconColor: .orange,
            family: family
        )
    }

    private func annotationColor(
        for annotation: AnnotationWidgetItem
    ) -> Color {
        annotation.type == 1 ? .gray : .init(hex: annotation.colorHex) ?? .orange
    }

    private func annotationLink(
        for annotation: AnnotationWidgetItem,
        isFirstItem: Bool
    ) -> some View {
        let barColor = annotationColor(for: annotation)
        let destinationURL = WidgetDeepLink.annotation(id: annotation.id).url
        return WidgetCardView(
            barColor: barColor,
            destinationURL: destinationURL,
            title: annotation.context,
            subtitle: annotation.bookTitle ?? "Book: \(annotation.bkId)",
            family: family,
            isFirstItem: isFirstItem
        )
    }
}
