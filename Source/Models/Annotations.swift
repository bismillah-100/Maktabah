//
//  Annotations.swift
//  annotations
//
//  Created by MacBook on 13/12/25.
//  Granular UI Update
//

import Cocoa

// MARK: - Sortable Protocol & Helpers

/// Sebuah protokol untuk tipe-tipe yang dapat diurutkan secara dinamis menggunakan `NSSortDescriptor`
/// melalui `KeyPath` yang aman-tipe (type-safe).
protocol SortableKey: AnyObject {
    static var keyPathMap: [String: PartialKeyPath<Self>] { get }
    static var secondaryKeyPaths: [PartialKeyPath<Self>] { get }
}

extension SortableKey {
    static func createComparator(for keyPath: PartialKeyPath<Self>, ascending: Bool) -> ((Self, Self) -> ComparisonResult)? {
        func compare<U: Comparable>(_ lhs: U, _ rhs: U, ascending: Bool) -> ComparisonResult {
            if lhs < rhs {
                return ascending ? .orderedAscending : .orderedDescending
            } else if lhs > rhs {
                return ascending ? .orderedDescending : .orderedAscending
            } else {
                return .orderedSame
            }
        }

        func compareOptional<U: Comparable>(_ lhs: U?, _ rhs: U?, defaultValue: U, ascending: Bool) -> ComparisonResult {
            let v1 = lhs ?? defaultValue
            let v2 = rhs ?? defaultValue
            return compare(v1, v2, ascending: ascending)
        }

        switch keyPath {
        case let path as KeyPath<Self, String>:
            return { compare($0[keyPath: path], $1[keyPath: path], ascending: ascending) }
        case let path as KeyPath<Self, String?>:
            return { compareOptional($0[keyPath: path], $1[keyPath: path], defaultValue: "", ascending: ascending) }
        case let path as KeyPath<Self, Int64>:
            return { compare($0[keyPath: path], $1[keyPath: path], ascending: ascending) }
        case let path as KeyPath<Self, Int64?>:
            return { compareOptional($0[keyPath: path], $1[keyPath: path], defaultValue: Int64.min, ascending: ascending) }
        case let path as KeyPath<Self, Date>:
            return { compare($0[keyPath: path], $1[keyPath: path], ascending: ascending) }
        case let path as KeyPath<Self, Date?>:
            return { compareOptional($0[keyPath: path], $1[keyPath: path], defaultValue: .distantPast, ascending: ascending) }
        default:
            return nil
        }
    }

    static func comparator(from sortDescriptor: NSSortDescriptor) -> ((Self, Self) -> Bool)? {
        guard let key = sortDescriptor.key, let path = keyPathMap[key] else { return nil }
        let primaryComparator = createComparator(for: path, ascending: sortDescriptor.ascending)
        let secondaryComparators = secondaryKeyPaths.compactMap { createComparator(for: $0, ascending: true) }

        return { obj1, obj2 -> Bool in
            if let primaryResult = primaryComparator?(obj1, obj2), primaryResult != .orderedSame {
                return primaryResult == .orderedAscending
            }
            for secondaryCmp in secondaryComparators {
                let secondaryResult = secondaryCmp(obj1, obj2)
                if secondaryResult != .orderedSame {
                    return secondaryResult == .orderedAscending
                }
            }
            return ObjectIdentifier(obj1) < ObjectIdentifier(obj2)
        }
    }
}

extension RandomAccessCollection {
    /// Menentukan indeks di mana sebuah elemen harus disisipkan ke dalam koleksi
    /// yang sudah diurutkan agar urutan tetap terjaga. (O(log n))
    func insertionIndex<T>(
        for element: T,
        using areInIncreasingOrder: (Element, T) -> Bool
    ) -> Index {
        var low = startIndex
        var high = endIndex

        while low < high {
            let mid = index(low, offsetBy: distance(from: low, to: high) / 2)
            if areInIncreasingOrder(self[mid], element) {
                low = index(after: mid)
            } else {
                high = mid
            }
        }
        return low
    }
}

// MARK: - Models

enum AnnotationSortField: Int {
    case createdAt
    case context
    case page
    case part
}

struct AnnotationSortOption {
    let field: AnnotationSortField
    let isAscending: Bool
}

struct Annotation {
    var id: Int64?            // nil sebelum disimpan
    let bkId: Int             // book id
    let contentId: Int        // BookContent.id
    var range: NSRange        // NSRange berbasis UTF-16 (NSString)
    let rangeDiacritics: NSRange
    let colorHex: String      // "#RRGGBB"
    var type: AnnotationMode          // "highlight" atau "underline"
    let note: String?         // catatan opsional
    let createdAt: Int64      // timestamp
    let context: String       // Konteks yang dianotasi
    let page: Int
    let part: Int
    var pageArb: String?
    var partArb: String?
}

final class AnnotationNode: SortableKey {
    var title: String
    var children: [AnnotationNode] = []
    var annotation: Annotation? // optional, kalau node ini representasi annotation

    init(title: String, annotation: Annotation? = nil) {
        self.title = title
        self.annotation = annotation
    }

    // Properti pembantu untuk SortableKey mapping
    var createdAt: Int64 { annotation?.createdAt ?? 0 }
    var context: String { annotation?.context ?? "" }
    var page: Int64 { Int64(annotation?.page ?? 0) }
    var part: Int64 { Int64(annotation?.part ?? 0) }

    static var keyPathMap: [String : PartialKeyPath<AnnotationNode>] = [
        "title": \AnnotationNode.title,
        "createdAt": \AnnotationNode.createdAt,
        "context": \AnnotationNode.context,
        "page": \AnnotationNode.page,
        "part": \AnnotationNode.part
    ]

    static var secondaryKeyPaths: [PartialKeyPath<AnnotationNode>] = [
        \AnnotationNode.title,
        \AnnotationNode.createdAt
    ]
}

struct ContentKey: Hashable {
    let bkId: Int
    let contentId: Int
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

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return nil }
        let scanner = Scanner(string: s)
        var hexNum: UInt64 = 0
        guard scanner.scanHexInt64(&hexNum) else { return nil }
        let r = CGFloat((hexNum & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hexNum & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hexNum & 0x0000FF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    func hexString() -> String {
        let defaultColor = "#FF9300"
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return defaultColor }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
