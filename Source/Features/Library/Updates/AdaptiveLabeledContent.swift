//
//  AdaptiveLabeledContent.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 04/09/26.
//

import SwiftUI

struct AdaptiveLabeledContent<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        LabeledContent(title) {
            content
        }
        #else
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content
        }
        .padding(.vertical, 4)
        #endif
    }
}
