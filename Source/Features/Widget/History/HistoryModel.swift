//
//  HistoryModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import WidgetKit

struct HistoryItem: Identifiable {
    let id: String
    let bkId: Int
    let bookTitle: String?
    let lastReadContentId: Int?
    let lastReadTime: Int64
}

struct HistoryEntry: TimelineEntry {
    let date: Date
    let history: [HistoryItem]
}
