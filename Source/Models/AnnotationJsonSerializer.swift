//
//  AnnotationJsonSerializer.swift
//  Maktabah
//
//  Created by Ghoys on 17/08/2026.
//

import Foundation

enum AnnotationJsonSerializer {
    private static let version = 1

    static func encode(annotations: [Annotation]) -> String? {
        guard let data = encodeToData(annotations: annotations) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func encodeToData(annotations: [Annotation]) -> Data? {
        var root: [String: Any] = [:]
        root["version"] = version
        root["exportedAt"] = Int64(Date().timeIntervalSince1970 * 1000)
        root["count"] = annotations.count

        var array: [[String: Any]] = []
        array.reserveCapacity(annotations.count)

        for ann in annotations {
            var obj: [String: Any] = [:]
            obj["bkId"] = ann.bkId
            obj["contentId"] = ann.contentId
            obj["colorHex"] = ann.colorHex
            if let note = ann.note, !note.isEmpty {
                obj["note"] = note
            }
            obj["type"] = ann.type.rawValue
            // Store createdAt in milliseconds for Android consistency
            obj["createdAt"] = ann.createdAt > 9_999_999_999 ? ann.createdAt : ann.createdAt * 1000
            obj["page"] = ann.page
            obj["context"] = ann.context
            obj["rangeLocation"] = ann.range.location
            obj["rangeLength"] = ann.range.length
            obj["rangeDiacLocation"] = ann.rangeDiacritics.location
            obj["rangeDiacLength"] = ann.rangeDiacritics.length
            obj["part"] = ann.part
            obj["tags"] = ann.tags.joined(separator: ",")

            if let ckRecordId = ann.ckRecordId, !ckRecordId.isEmpty {
                obj["ckRecordId"] = ckRecordId
            }
            if let lastModified = ann.lastModified {
                obj["lastModified"] = lastModified > 9_999_999_999 ? lastModified : lastModified * 1000
            }

            array.append(obj)
        }

        root["annotations"] = array

        do {
            return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        } catch {
            print("AnnotationJsonSerializer: failed to encode JSON: \(error)")
            return nil
        }
    }

    static func decode(from data: Data) throws -> [Annotation] {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        let array: [[String: Any]]

        if let dict = jsonObject as? [String: Any] {
            if let items = dict["annotations"] as? [[String: Any]] {
                array = items
            } else if let items = dict["data"] as? [[String: Any]] {
                array = items
            } else {
                array = []
            }
        } else if let items = jsonObject as? [[String: Any]] {
            array = items
        } else {
            return []
        }

        var result: [Annotation] = []
        result.reserveCapacity(array.count)

        for obj in array {
            let bkId = obj["bkId"] as? Int ?? 0
            let contentId = obj["contentId"] as? Int ?? 0
            let colorHex = obj["colorHex"] as? String ?? "#FFFF00"
            let note = obj["note"] as? String
            let typeInt = obj["type"] as? Int ?? 0
            let type = AnnotationMode.from(int: typeInt)

            let createdAtRaw = (obj["createdAt"] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970)
            let createdAt = createdAtRaw > 9_999_999_999 ? createdAtRaw / 1000 : createdAtRaw

            let page = obj["page"] as? Int ?? 0
            let context = obj["context"] as? String ?? ""
            let rangeLocation = obj["rangeLocation"] as? Int ?? 0
            let rangeLength = obj["rangeLength"] as? Int ?? 0
            let rangeDiacLocation = obj["rangeDiacLocation"] as? Int ?? 0
            let rangeDiacLength = obj["rangeDiacLength"] as? Int ?? 0
            let part = obj["part"] as? Int ?? 0

            let tags: [String] = if let tagsStr = obj["tags"] as? String {
                tagsStr
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } else if let tagsArr = obj["tags"] as? [String] {
                tagsArr
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } else {
                []
            }

            let ckRecordId = obj["ckRecordId"] as? String
            let lastModifiedRaw = (obj["lastModified"] as? NSNumber)?.int64Value
            let lastModified = lastModifiedRaw.map { $0 > 9_999_999_999 ? $0 / 1000 : $0 }

            result.append(
                Annotation(
                    id: nil,
                    bkId: bkId,
                    contentId: contentId,
                    range: NSRange(location: rangeLocation, length: rangeLength),
                    rangeDiacritics: NSRange(location: rangeDiacLocation, length: rangeDiacLength),
                    colorHex: colorHex,
                    type: type,
                    note: note,
                    createdAt: createdAt,
                    context: context,
                    page: page,
                    part: part,
                    pageArb: String(page).convertToArabicDigits(),
                    partArb: String(part).convertToArabicDigits(),
                    tags: tags,
                    ckRecordId: ckRecordId,
                    lastModified: lastModified
                )
            )
        }

        return result
    }

    static func decode(from jsonString: String) throws -> [Annotation] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        return try decode(from: data)
    }
}
