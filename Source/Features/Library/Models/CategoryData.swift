//
//  CategoryData.swift
//  Maktabah
//

import Foundation

class CategoryData {
    let id: Int
    let name: String
    let normalizedName: String
    let level: Int
    let order: Int
    var isChecked: Bool = true
    var children: [Any] = [] // Bisa berisi CategoryData atau BooksData

    init(id: Int, name: String, level: Int, order: Int) {
        self.id = id
        self.name = StringInterner.shared.intern(name)
        normalizedName = name.normalizeArabic(false)
        self.level = level
        self.order = order
    }

    func copy(with zone: NSZone? = nil) -> CategoryData {
        CategoryData(
            id: id,
            name: StringInterner.shared.intern(name),
            level: level,
            order: order
        )
    }

    var allBooks: [BooksData] {
        var result: [BooksData] = []
        collectBooks(into: &result)
        return result
    }

    var allSubcategories: [CategoryData] {
        var result: [CategoryData] = []
        collectSubcategories(into: &result)
        return result
    }

    private func collectBooks(into books: inout [BooksData]) {
        for child in children {
            if let book = child as? BooksData {
                books.append(book)
            } else if let sub = child as? CategoryData {
                sub.collectBooks(into: &books)
            }
        }
    }

    private func collectSubcategories(into categories: inout [CategoryData]) {
        for child in children {
            if let sub = child as? CategoryData {
                categories.append(sub)
                sub.collectSubcategories(into: &categories)
            }
        }
    }
}
