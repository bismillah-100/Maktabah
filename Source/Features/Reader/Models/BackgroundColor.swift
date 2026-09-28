//
//  BackgroundColor.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 26/09/26.
//

import Foundation
import SwiftUI

enum BackgroundColor: Int, CaseIterable, Identifiable {
    case white
    case sepia
    case gray
    case darkSepia
    case black

    var id: Int { rawValue }

    var isDark: Bool { rawValue > 1 }

    /// PlatformColor (NSColor / UIColor) yang otomatis menyesuaikan mode terang/gelap sistem
    var nsColor: PlatformColor {
        switch self {
        case .white: .white
        case .sepia: .bgSepia
        case .gray: .bgGray
        case .darkSepia: .bgSepiaDark
        case .black: .bgDark
        }
    }

    /// SwiftUI Color yang otomatis menyesuaikan mode terang/gelap sistem
    var color: Color {
        switch self {
        case .white: .white
        case .sepia: .bgSepia
        case .gray: .bgGray
        case .darkSepia: .bgSepiaDark
        case .black: .bgDark
        }
    }
}
