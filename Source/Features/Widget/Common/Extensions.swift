//
//  Extensions.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import SwiftUI
import WidgetKit

extension View {
    @ViewBuilder
    func widgetBackground(@ViewBuilder _ content: () -> some View) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            containerBackground(for: .widget) {
                content()
            }
        } else {
            background(content())
        }
    }
}

extension WidgetConfiguration {
    func contentMarginsDisabledIfAvailable() -> some WidgetConfiguration {
        if #available(iOS 17.0, macOS 14.0, *) {
            return contentMarginsDisabled()
        } else {
            return self
        }
    }
}

extension WidgetFamily {
    var maxItemCount: Int {
        self == .systemLarge ? 6 : 3
    }
}
