//
//  ArabicFont.swift
//  maktab
//
//  Created by MacBook on 16/12/25.
//

import Foundation
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
        ]

        for fontFile in fontFiles {
            // Buat URL sementara dari String
            let tempURL = URL(fileURLWithPath: fontFile)

            // Ambil nama tanpa ekstensi dan ekstensinya
            let fileNameWithoutExtension = tempURL.deletingPathExtension().lastPathComponent
            let fileExtension = tempURL.pathExtension

            guard let fontURL = Bundle.main.url(forResource: fileNameWithoutExtension,
                                                withExtension: fileExtension)
            else {
                print("Font file tidak ditemukan: \(fontFile)")
                continue
            }

            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
                print("Error registering font: \(fontFile)")
                if let error = error?.takeRetainedValue() {
                    print("Error detail: \(error)")
                }
            } else {
                print("Font berhasil diregister: \(fontFile)")
            }
        }
    }
}
