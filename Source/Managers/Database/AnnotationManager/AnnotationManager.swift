//
//  AnnotationManager.swift
//  Maktabah
//
//  Created by MacBook on 15/12/25.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation
import Combine
import SQLite3

final class AnnotationManager {
    // MARK: - Table & column names

    let annotationsTable = "annotations"
    let colAnnId = "id"
    let colAnnBkId = "bkId"
    let colAnnContentId = "contentId"
    let colAnnStart = "startIndex"
    let colAnnStartDiac = "startIndexDiac"
    let colAnnLength = "length"
    let colAnnLengthDiac = "lengthDiac"
    let colAnnColor = "color"
    let colAnnType = "type"
    let colAnnNote = "note"
    let colAnnCreatedAt = "createdAt"
    let colAnnContext = "context"
    let colAnnPage = "page"
    let colAnnPart = "part"
    let colAnnCkRecordId = "ckRecordId"
    let colAnnLastModified = "lastModified"

    let tagsTable = "tags"
    let colTagId = "id"
    let colTagName = "name"
    let colTagNormalizedName = "normalizedName"

    let annotationTagsTable = "annotation_tags"
    let colAnnotationTagAnnotationId = "annotationId"
    let colAnnotationTagTagId = "tagId"

    // MARK: - Singleton

    var _db: SQLiteDatabase?
    var db: SQLiteDatabase? { _db }
    static let shared = AnnotationManager()

    // MARK: - Caches

    var _cacheById: [Int64: Annotation] = [:]
    var _cacheByContent: [ContentKey: [Annotation]] = [:]
    var _cacheByBook: [Int: [Annotation]] = [:]
    var _cacheTagsByAnnotationId: [Int64: [String]] = [:]
    var _cachedAllTagNames: [String]?

    // MARK: - Tree

    var _rootNode: AnnotationNode?
    let _treeQueue = DispatchQueue(label: "com.maktab.annotationManager.treeQueue", qos: .userInitiated)

    var rootNode: AnnotationNode? {
        _treeQueue.sync { _rootNode }
    }

    // MARK: - State

    var _sortOption: AnnotationSortOption = .init(field: .createdAt, isAscending: false)
    var _groupingMode: AnnotationGroupingMode = .book

    /// Serial queue to protect caches
    let _cacheQueue = DispatchQueue(label: "com.maktab.annotationManager.cacheQueue", qos: .userInitiated)

    var cancellables = Set<AnyCancellable>()

    var now: Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    var dbURL: URL?

    // MARK: - Init

    private init() {
        UserDefaults.standard.publisher(for: \.hideMissingBookAnnotations)
            .dropFirst()
            .sink { [weak self] _ in
                self?.buildAnnotationTree()
            }
            .store(in: &cancellables)
    }

    // MARK: - Post Notification

    func postChangeNotification(
        type: AnnotationChangeType,
        annotation: Annotation? = nil,
        annotationsToSync: [Annotation]? = nil,
        annotationId: Int64? = nil,
        diff: TagUpdateDiff? = nil,
        oldParentIndex: Int? = nil,
        newParentIndex: Int? = nil,
        uploadToCloudKit: Bool = true
    ) {
        var userInfo: [String: Any] = [AnnotationNotificationKeys.changeType: type.rawValue]

        if let ann = annotation {
            userInfo[AnnotationNotificationKeys.annotation] = ann
            if type != .deleted { pushRecentColor(ann) }
        }

        if uploadToCloudKit {
            if type == .added || type == .updated {
                let toUpload = annotationsToSync ?? (annotation != nil ? [annotation!] : [])
                if !toUpload.isEmpty {
                    CloudKitSyncManager.shared.upload(annotations: toUpload, trackPending: false)
                }
            } else if type == .deleted, let ann = annotation, let ckId = ann.ckRecordId {
                CloudKitSyncManager.shared.delete(ckRecordIds: [ckId], target: .annotation, trackPending: false)
            }
        }

        if let id = annotationId {
            userInfo[AnnotationNotificationKeys.annotationId] = id
        }
        if let diff = diff {
            userInfo[AnnotationNotificationKeys.tagDiff] = diff
        }
        if let oldIdx = oldParentIndex {
            userInfo[AnnotationNotificationKeys.oldParentIndex] = oldIdx
        }
        if let newIdx = newParentIndex {
            userInfo[AnnotationNotificationKeys.newParentIndex] = newIdx
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .annotationDidChange,
                object: self,
                userInfo: userInfo
            )
        }
    }
}
