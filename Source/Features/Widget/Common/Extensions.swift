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

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") {
            s.removeFirst()
        }
        guard s.count == 6, let hexNum = UInt64(s, radix: 16) else { return nil }

        let r = Double((hexNum & 0xFF0000) >> 16) / 255.0
        let g = Double((hexNum & 0x00FF00) >> 8) / 255.0
        let b = Double(hexNum & 0x0000FF) / 255.0

        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
