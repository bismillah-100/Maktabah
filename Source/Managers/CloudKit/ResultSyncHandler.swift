//
//  ResultSyncHandler.swift
//  Maktabah
//

import CloudKit
import Foundation

final class ResultSyncHandler {
    static let shared = ResultSyncHandler()
    static let folderRecordType = "SearchFolder"
    static let resultRecordType = "SearchResult"

    private init() {}

    static func parseFolder(from record: CKRecord) -> SyncFolder? {
        guard let name = record["name"] as? String else { return nil }
        return SyncFolder(
            id: nil,
            name: name,
            parent: nil,
            ckRecordId: record.recordID.recordName,
            lastModified: record["lastModified"] as? Int64,
            parentCkRecordId: record["parentCkRecordId"] as? String
        )
    }

    static func parseResult(from record: CKRecord) -> SyncResult? {
        guard let name = record["name"] as? String,
              let query = record["query"] as? String,
              let archive = record["archive"] as? Int,
              let bkId = record["bkId"] as? Int,
              let contentId = record["contentId"] as? String
        else { return nil }

        let searchMode = record["searchMode"] as? Int ?? 0
        let nearDistance = record["nearDistance"] as? Int ?? 10

        return SyncResult(
            id: nil,
            folderId: nil,
            name: name,
            query: query,
            searchMode: searchMode,
            nearDistance: nearDistance,
            archive: archive,
            bkId: bkId,
            contentId: contentId,
            ckRecordId: record.recordID.recordName,
            lastModified: record["lastModified"] as? Int64,
            folderCkRecordId: record["folderCkRecordId"] as? String
        )
    }
}

extension SyncFolder: CloudKitSyncable {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord? {
        guard let ckId = self.ckRecordId else { return nil }
        let record = CKRecord(recordType: ResultSyncHandler.folderRecordType, recordID: CKRecord.ID(recordName: ckId, zoneID: zoneID))
        record["name"] = self.name
        record["lastModified"] = self.lastModified ?? Int64(Date().timeIntervalSince1970)
        record["parentCkRecordId"] = self.parentCkRecordId
        return record
    }
}

extension SyncResult: CloudKitSyncable {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord? {
        guard let ckId = self.ckRecordId else { return nil }
        let record = CKRecord(recordType: ResultSyncHandler.resultRecordType, recordID: CKRecord.ID(recordName: ckId, zoneID: zoneID))
        record["name"] = self.name
        record["query"] = self.query
        record["searchMode"] = self.searchMode
        record["nearDistance"] = self.nearDistance
        record["archive"] = self.archive
        record["bkId"] = self.bkId
        record["contentId"] = self.contentId
        record["lastModified"] = self.lastModified ?? Int64(Date().timeIntervalSince1970)
        record["folderCkRecordId"] = self.folderCkRecordId
        return record
    }
}
