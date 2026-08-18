//
//  Color+Hex.swift
//  Maktabah
//

import SwiftUI

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let hexNum = UInt64(s, radix: 16) else { return nil }

        let r = Double((hexNum & 0xFF0000) >> 16) / 255.0
        let g = Double((hexNum & 0x00FF00) >> 8) / 255.0
        let b = Double(hexNum & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
