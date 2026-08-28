//
//  TightArabicText.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 30/08/26.
//

import SwiftUI

#if os(macOS)
typealias PlatformFont = NSFont
#else
typealias PlatformFont = UIFont
#endif

// MARK: - Font Line Height Extension

extension PlatformFont {
    var computedLineHeight: CGFloat {
        #if os(macOS)
        ceil(ascender - descender + leading)
        #else
        lineHeight
        #endif
    }
}

// MARK: - ViewModifier

struct TightArabicText: View {
    let text: String
    let fontSize: CGFloat
    var maxLines: Int = 2
    var lineSpacing: CGFloat = -5

    var body: some View {
        let customFont = PlatformFont(name: "NotoNaskhArabic-Medium", size: fontSize) ?? .systemFont(ofSize: fontSize)

        Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(Font(customFont))
            .foregroundStyle(.primary)
            .lineLimit(maxLines)
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
