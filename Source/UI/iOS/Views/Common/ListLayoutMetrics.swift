//
//  ListLayoutMetrics.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 11/06/26.
//

import UIKit

/// Pusat manajemen dimensi layout untuk list hierarkis.
/// Menghilangkan "magic numbers" agar alignment sel dan separator selalu konsisten secara otomatis.
enum ListLayoutMetrics {
    static let defaultPadding: CGFloat = 16
    static let baseIndentation: CGFloat = 32
    static let imageWidth: CGFloat = 30
    static let imageGap: CGFloat = 8
    static let chevronWidth: CGFloat = 16

    /// Lebar total komponen leading pendukung (icon/checkbox + space)
    static var leadingAccessoryTotalWidth: CGFloat {
        return imageWidth + imageGap
    }

    /// Menghitung offset trailing untuk konten teks di dalam sel
    static func contentTrailingOffset(isRoot: Bool, indentationLevel: Int) -> CGFloat {
        if isRoot && indentationLevel > 0 {
            return -24
        } else if indentationLevel > 1 {
            return -56
        } else {
            return -CGFloat(defaultPadding + (baseIndentation * CGFloat(indentationLevel)))
        }
    }

    /// Menghitung offset trailing untuk separator di tingkat controller.
    /// Menggunakan basis kalkulasi yang sama dengan `contentTrailingOffset` agar presisi 100%.
    static func separatorTrailingOffset(isRoot: Bool, indentationLevel: Int) -> CGFloat {
        let contentOffset = abs(contentTrailingOffset(isRoot: isRoot, indentationLevel: indentationLevel))
        let extraWidth = leadingAccessoryTotalWidth + (isRoot ? chevronWidth + imageGap : 0)
        return contentOffset + extraWidth
    }
}

/// Helper extension untuk standardisasi Font Arab di seluruh aplikasi
extension UIFont {
    static func arabicFont(size: CGFloat) -> UIFont {
        // Menggunakan nama font kustom dengan fallback aman ke font sistem
        return UIFont(name: "kfgqpcUthmanTahaNaskh", size: size) ?? .preferredFont(forTextStyle: .body)
    }
}
