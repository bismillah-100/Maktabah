//
//  ArabicFont.swift
//  maktab
//
//  Created by MacBook on 16/12/25.
//

import Foundation
import OSLog
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum ArabicFont: String, CaseIterable {
    case kfgqpcUthmanTahaNaskh = "KFGQPC Uthman Taha Naskh"
    case scheherazadeNew = "Scheherazade New"
    case lateef = "Lateef"
    case lateefBold = "Lateef Bold"
    case geezaPro = "Geeza Pro"
    case damascus = "Damascus"
    case alBayan = "Al Bayan Plain"
    case baghdad = "Baghdad"
    case nadeem = "Nadeem"

    static func registerCustomFonts() {
        let fontFiles = [
            "UthmanTN1-Ver10.otf",
            "Lateef-Regular.ttf",
            "Lateef-Bold.ttf",
            "ScheherazadeNew-Regular.ttf",
            "NotoNaskhArabic-Medium.ttf",
        ]

        for fontFile in fontFiles {
            // Buat URL sementara dari String
            let tempURL = URL(fileURLWithPath: fontFile)

            // Ambil nama tanpa ekstensi dan ekstensinya
            let fileNameWithoutExtension = tempURL.deletingPathExtension().lastPathComponent
            let fileExtension = tempURL.pathExtension

            let fontURL = Bundle.main.url(forResource: fileNameWithoutExtension,
                                          withExtension: fileExtension,
                                          subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: fileNameWithoutExtension,
                                   withExtension: fileExtension)

            guard let fontURL else {
                Logger.app.error("Font file tidak ditemukan: \(fontFile, privacy: .public)")
                continue
            }

            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
                if let error = error?.takeRetainedValue() {
                    Logger.app.error("Error registering font \(fontFile, privacy: .public): \(String(describing: error), privacy: .public)")
                } else {
                    Logger.app.error("Error registering font: \(fontFile, privacy: .public)")
                }
            } else {
                Logger.app.debug("Font berhasil diregister: \(fontFile, privacy: .public)")
            }
        }
    }
}
