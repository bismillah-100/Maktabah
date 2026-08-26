//
//  CloudKitSyncable.swift
//  Maktabah
//

import CloudKit
import Foundation

/// Defines how an entity is mapped to and from a CKRecord
protocol CloudKitSyncable {
    /// CloudKit record identifier
    var ckRecordId: String? { get }

    /// Convert the entity to a CKRecord suitable for uploading to CloudKit
    /// - Parameter zoneID: The zone ID where this record belongs
    /// - Returns: A configured CKRecord
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord?
}

extension CloudKitSyncable {
    func createRecord(type: String, recordName: String, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        return CKRecord(recordType: type, recordID: recordID)
    }
}

extension Array where Element: CloudKitSyncable {
    var pairedWithRecordId: [(String, Element)] {
        compactMap { item in
            guard let ckId = item.ckRecordId else { return nil }
            return (ckId, item)
        }
    }
}

/// Defines a parser capable of reconstructing an entity from a CKRecord
protocol CloudKitRecordParser {
    associatedtype Model

    /// The CloudKit record type this parser handles
    static var recordType: String { get }

    /// Parse a CKRecord into a domain model
    static func parse(from record: CKRecord) -> Model?
}
