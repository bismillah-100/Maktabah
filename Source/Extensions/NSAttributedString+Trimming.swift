//
//  NSAttributedString+Trimming.swift
//  Maktabah
//

import Foundation

extension NSAttributedString {
    func trimmingCharacters(in set: CharacterSet) -> NSAttributedString {
        let nsString = string as NSString
        var start = 0
        var length = nsString.length

        while start < length {
            let charCode = nsString.character(at: start)
            guard let scalar = UnicodeScalar(charCode), set.contains(scalar) else {
                break
            }
            start += 1
        }

        while length > start {
            let charCode = nsString.character(at: length - 1)
            guard let scalar = UnicodeScalar(charCode), set.contains(scalar) else {
                break
            }
            length -= 1
        }

        return attributedSubstring(from: NSRange(location: start, length: length - start))
    }

    var contentSortKey: String {
        let plain = string.trimmingCharacters(in: .whitespacesAndNewlines)
        var sentences: [String] = []
        var current = ""
        for char in plain {
            current.append(char)
            if char == "." || char == "!" || char == "?" {
                sentences.append(current)
                current = ""
                if sentences.count == 2 { break }
            }
        }
        return sentences.joined()
    }
}
