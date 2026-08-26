//
//  HistorySyncHandler.swift
//  Maktabah
//

import CloudKit
import Foundation

final class HistorySyncHandler: CloudKitRecordParser {
    typealias Model = ReadingEntry

    static let shared = HistorySyncHandler()
    static let recordType = "ReadingEntry"

    private init() {}

    static func parse(from record: CKRecord) -> ReadingEntry? {
        guard let bookId = record["bookId"] as? Int,
              let isFavorite = record["isFavorite"] as? Bool
        else { return nil }

        return ReadingEntry(
            bookId: bookId,
            lastContentId: record["lastContentId"] as? Int,
            lastOpenedAt: record["lastOpenedAt"] as? Date,
            favoritedAt: record["favoritedAt"] as? Date,
            positionUpdatedAt: record["positionUpdatedAt"] as? Date,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(record["lastModified"] as? Int64 ?? 0)),
            isFavorite: isFavorite,
            ckRecordId: record.recordID.recordName
        )
    }
}

extension ReadingEntry: CloudKitSyncable {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord? {
        guard let ckRecordIdStr = ckRecordId else { return nil }
        let record = createRecord(type: HistorySyncHandler.recordType, recordName: ckRecordIdStr, zoneID: zoneID)

        record["bookId"] = bookId
        record["lastContentId"] = lastContentId
        record["lastOpenedAt"] = lastOpenedAt
        record["favoritedAt"] = favoritedAt
        record["positionUpdatedAt"] = positionUpdatedAt
        record["isFavorite"] = isFavorite
        record["lastModified"] = Int64(updatedAt.timeIntervalSince1970)

        return record
    }
}
