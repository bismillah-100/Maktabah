//
//  NSAttributedString+Archiving.swift
//  Maktabah
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

// MARK: - NSAttributedString Secure Coding

extension NSAttributedString {
    static var secureCodingClasses: [AnyClass] {
        #if os(macOS)
        [
            NSAttributedString.self,
            NSMutableAttributedString.self,
            NSColor.self,
            NSFont.self,
            NSDictionary.self,
            NSString.self,
            NSNumber.self,
            NSArray.self,
            NSParagraphStyle.self,
            NSMutableParagraphStyle.self,
            NSShadow.self,
        ]
        #else
        [
            NSAttributedString.self,
            NSMutableAttributedString.self,
            UIColor.self,
            UIFont.self,
            NSDictionary.self,
            NSString.self,
            NSNumber.self,
            NSArray.self,
            NSParagraphStyle.self,
            NSMutableParagraphStyle.self,
            NSShadow.self,
        ]
        #endif
    }

    func archivedData() throws -> Data {
        try NSKeyedArchiver.archivedData(
            withRootObject: self,
            requiringSecureCoding: true
        )
    }

    static func unarchiveSecure(from data: Data) -> NSAttributedString? {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            let decoded = unarchiver.decodeObject(
                of: secureCodingClasses,
                forKey: NSKeyedArchiveRootObjectKey
            ) as? NSAttributedString
            unarchiver.finishDecoding()
            return decoded
        } catch {
            return nil
        }
    }
}

