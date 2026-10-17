//
//  AdaptiveLabeledContent.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 04/09/26.
//

import SwiftUI

struct AdaptiveLabeledContent<Content: View>: View {
    let title: Text
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.content = content()
    }

    init(_ titleResource: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        title = Text(titleResource)
        self.content = content()
    }

    init(_ titleString: String, @ViewBuilder content: () -> Content) {
        title = Text(titleString)
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        LabeledContent {
            content
        } label: {
            title
        }
        #else
        VStack(alignment: .leading) {
            title
                .font(.caption)
                .foregroundColor(.secondary)
            content
        }
        .padding(.vertical, 4)
        #endif
    }
}
