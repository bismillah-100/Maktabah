//
//  MaktabahWidgetBundle.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/08/26.
//

import SwiftUI
import WidgetKit

@main
struct MaktabahWidgetBundle: WidgetBundle {
    init() {
        ArabicFont.registerWidgetFonts()
    }

    var body: some Widget {
        AnnotationWidget()
        HistoryWidget()
    }
}
