//
//  AnnotationModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import WidgetKit

struct AnnotationWidgetItem: Identifiable {
    let id: Int64
    let bkId: Int
    let bookTitle: String?
    let contentId: Int
    let context: String
    let colorHex: String
    let type: Int
    let createdAt: Int64
}

struct AnnotationEntry: TimelineEntry {
    let date: Date
    let annotations: [AnnotationWidgetItem]
}
