//
//  Annotation.swift
//  Maktabah
//

import Foundation

struct Annotation {
    var id: Int64? // nil sebelum disimpan
    let bkId: Int // book id
    let contentId: Int // BookContent.id
    var range: NSRange // NSRange berbasis UTF-16 (NSString)
    let rangeDiacritics: NSRange
    var colorHex: String // "#RRGGBB"
    var type: AnnotationMode // "highlight" atau "underline"
    var note: String? // catatan opsional
    let createdAt: Int64 // timestamp
    let context: String // Konteks yang dianotasi
    let page: Int
    let part: Int
    var pageArb: String?
    var partArb: String?
    var tags: [String] = []

    // CloudKit Sync Support
    var ckRecordId: String?
    var lastModified: Int64?
}

enum AnnotationMode: Int {
    case highlight
    case underline

    static func from(int: Int) -> AnnotationMode {
        return switch int {
        case 0: highlight
        case 1: underline
        default: highlight
        }
    }
}

struct ContentKey: Hashable {
    let bkId: Int
    let contentId: Int
}
