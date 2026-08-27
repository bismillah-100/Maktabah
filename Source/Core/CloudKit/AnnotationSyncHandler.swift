//
//  AnnotationSyncHandler.swift
//  Maktabah
//

import CloudKit
import Foundation

final class AnnotationSyncHandler: CloudKitRecordParser {
    typealias Model = Annotation

    static let shared = AnnotationSyncHandler()
    static let recordType = "Annotation"

    private init() {}

    static func parse(from record: CKRecord) -> Annotation? {
        guard let bkId = record["bkId"] as? Int,
              bkId >= 0,
              let contentId = record["contentId"] as? Int,
              let rangeLocation = record["rangeLocation"] as? Int,
              let rangeLength = record["rangeLength"] as? Int,
              let rangeDiacLocation = record["rangeDiacLocation"] as? Int,
              let rangeDiacLength = record["rangeDiacLength"] as? Int,
              let colorHex = record["colorHex"] as? String,
              let typeRaw = record["type"] as? Int,
              let createdAt = record["createdAt"] as? Int64,
              let context = record["context"] as? String,
              let page = record["page"] as? Int,
              let part = record["part"] as? Int
        else {
            return nil
        }

        let tags = record["tags"] as? [String] ?? []
        let note = record["note"] as? String
        let lastModified = record["lastModified"] as? Int64

        return Annotation(
            id: nil,
            bkId: bkId,
            contentId: contentId,
            range: NSRange(location: rangeLocation, length: rangeLength),
            rangeDiacritics: NSRange(location: rangeDiacLocation, length: rangeDiacLength),
            colorHex: colorHex,
            type: AnnotationMode.from(int: typeRaw),
            note: note,
            createdAt: createdAt,
            context: context,
            page: page,
            part: part,
            pageArb: String(page).convertToArabicDigits(),
            partArb: String(part).convertToArabicDigits(),
            tags: tags,
            ckRecordId: record.recordID.recordName,
            lastModified: lastModified
        )
    }
}

extension Annotation: CloudKitSyncable {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord? {
        guard let ckRecordIdStr = ckRecordId else { return nil }
        let record = createRecord(type: AnnotationSyncHandler.recordType, recordName: ckRecordIdStr, zoneID: zoneID)

        record["bkId"] = bkId
        record["contentId"] = contentId
        record["rangeLocation"] = range.location
        record["rangeLength"] = range.length
        record["rangeDiacLocation"] = rangeDiacritics.location
        record["rangeDiacLength"] = rangeDiacritics.length
        record["colorHex"] = colorHex
        record["type"] = type.rawValue
        record["note"] = note
        record["createdAt"] = createdAt
        record["context"] = context
        record["page"] = page
        record["part"] = part
        record["lastModified"] = lastModified ?? Int64(Date().timeIntervalSince1970)
        record["tags"] = tags

        return record
    }
}
