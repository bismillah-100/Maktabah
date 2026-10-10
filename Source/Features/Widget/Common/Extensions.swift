//
//  Extensions.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import SwiftUI
import WidgetKit

extension WidgetFamily {
    var maxItemCount: Int {
        self == .systemLarge ? 6 : 3
    }
}

extension TimelineReloadPolicy {
    static var nextRefresh: TimelineReloadPolicy {
        #if DEBUG
        let nextDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())
            ?? Date().addingTimeInterval(60)
        return .after(nextDate)
        #else
        let nextDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            ?? Date().addingTimeInterval(3600)
        return .after(nextDate)
        #endif
    }
}
