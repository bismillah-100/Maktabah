//
//  AnnotationManager.swift
//  maktab
//
//  Created by MacBook on 15/12/25.
//

import Foundation
import SQLite
import AppKit

// MARK: - Notification Names
extension Notification.Name {
    static let annotationDidChange = Notification.Name("annotationDidChange")
    static let annotationDidDeleteFromOutline = Notification.Name("annotationDeletedFromOutlineView")
    static let annotationTreeDidUpdate = Notification.Name("annotationTreeDidUpdate")
}

// MARK: - Notification UserInfo Keys
enum AnnotationChangeType: String {
    case added
    case updated
    case deleted
}

struct AnnotationNotificationKeys {
    static let changeType = "changeType"
    static let annotation = "annotation"
    static let annotationId = "annotationId"
}

final class AnnotationManager {

    // MARK: - Table & columns
    private(set) var annotationsTable = Table("annotations")
    private(set) var annId = Expression<Int64>("id")
    private(set) var annBkId = Expression<Int>("bkId")
    private(set) var annContentId = Expression<Int>("contentId")
    private(set) var annStart = Expression<Int>("startIndex")
    private(set) var annStartDiac = Expression<Int>("startIndexDiac")
    private(set) var annLength = Expression<Int>("length")
    private(set) var annLengthDiac = Expression<Int>("lengthDiac")
    private(set) var annColor = Expression<String>("color")
    private(set) var annType = Expression<Int>("type")
    private(set) var annNote = Expression<String?>("note")
    private(set) var annCreatedAt = Expression<Int64>("createdAt")
    private(set) var annContext = Expression<String>("context")
    private(set) var annPage = Expression<Int>("page")
    private(set) var annPart = Expression<Int>("part")

    private(set) var db: Connection?

    static let shared = AnnotationManager()

    // MARK: - Caches
    private var cacheById: [Int64: Annotation] = [:]
    private var cacheByContent: [ContentKey: [Annotation]] = [:]

    private var _rootNode: AnnotationNode?
    private let treeQueue = DispatchQueue(label: "com.maktab.annotationManager.treeQueue", qos: .userInitiated)

    var rootNode: AnnotationNode? {
        get {
            return treeQueue.sync { _rootNode }
        }
    }

    // Serial queue to protect caches
    private let cacheQueue = DispatchQueue(label: "com.maktab.annotationManager.cacheQueue", qos: .userInitiated)

    private init() {}

    // MARK: - Private helper to post notification
    private func postChangeNotification(type: AnnotationChangeType, annotation: Annotation? = nil, annotationId: Int64? = nil) {
        var userInfo: [String: Any] = [AnnotationNotificationKeys.changeType: type.rawValue]

        if let ann = annotation {
            userInfo[AnnotationNotificationKeys.annotation] = ann
        }
        if let id = annotationId {
            userInfo[AnnotationNotificationKeys.annotationId] = id
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .annotationDidChange,
                object: self,
                userInfo: userInfo
            )
        }
    }

    private var dbURL: URL?
    
    func setupAnnotations(at folderURL: URL?) throws {
        guard let folderURL else { throw NSError(domain: "maktabah", code: 404) }
        
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: folderURL.path) {
            try fm.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true
            )
        }
        
        dbURL = folderURL.appendingPathComponent("Annotations.sqlite")
        connect()
        clearAllCaches()
        invalidateTree()
        try setupAnnotationsDatabase()
    }

    // MARK: - Setup DB in Application Support
    func setupAnnotationsDatabase() throws {
        try db?.run(annotationsTable.create(ifNotExists: true) { t in
            t.column(annId, primaryKey: .autoincrement)
            t.column(annBkId)
            t.column(annContentId)
            t.column(annStart)
            t.column(annLength)
            t.column(annStartDiac)
            t.column(annLengthDiac)
            t.column(annColor)
            t.column(annType)
            t.column(annNote)
            t.column(annCreatedAt)
            t.column(annContext)
            t.column(annPart)
            t.column(annPage)
        })
        
        try db?.run(annotationsTable.createIndex(
            annBkId, annContentId, ifNotExists: true
        ))
    }
    
    func connect() {
        if let dbURL {
            do {
                db = try Connection(dbURL.path)
            } catch {
                ReusableFunc.showAlert(title: "Error", message: "")
            }
        }
    }

    // MARK: - Add annotation
    @discardableResult
    func addAnnotation(_ annotation: Annotation) throws -> Int64 {
        guard let db = db else { throw NSError(domain: "DBNil", code: 1) }
        let insert = annotationsTable.insert(
            annBkId <- annotation.bkId,
            annContentId <- annotation.contentId,
            annStart <- annotation.range.location,
            annLength <- annotation.range.length,
            annStartDiac <- annotation.rangeDiacritics.location,
            annLengthDiac <- annotation.rangeDiacritics.length,
            annColor <- annotation.colorHex,
            annType <- annotation.type.rawValue,
            annNote <- annotation.note,
            annCreatedAt <- annotation.createdAt,
            annContext <- annotation.context,
            annPart <- annotation.part,
            annPage <- annotation.page
        )
        let rowId = try db.run(insert)

        // Update caches
        var saved = annotation
        saved.id = rowId
        cacheQueue.sync {
            cacheById[rowId] = saved
            let key = ContentKey(bkId: saved.bkId, contentId: saved.contentId)
            var arr = cacheByContent[key] ?? []
            arr.append(saved)
            arr.sort { $0.range.location < $1.range.location }
            cacheByContent[key] = arr
        }

        // 🔔 Post notification
        postChangeNotification(type: .added, annotation: saved)
        addAnnotationToTree(saved)
        return rowId
    }

    // MARK: - Update annotation
    func updateAnnotation(_ annotation: Annotation) throws {
        guard let db = db else { throw NSError(domain: "DBNil", code: 1) }
        guard let id = annotation.id else { throw NSError(domain: "NoID", code: 2) }
        let row = annotationsTable.filter(annId == id)
        try db.run(row.update(
            annColor <- annotation.colorHex,
            annType <- annotation.type.rawValue,
            annNote <- annotation.note
        ))

        // Update caches
        cacheQueue.sync {
            cacheById[id] = annotation
            let key = ContentKey(bkId: annotation.bkId, contentId: annotation.contentId)
            var arr = cacheByContent[key] ?? []
            if let idx = arr.firstIndex(where: { $0.id == id }) {
                arr[idx] = annotation
            } else {
                arr.append(annotation)
            }
            arr.sort { $0.range.location < $1.range.location }
            cacheByContent[key] = arr
        }

        // 🔔 Post notification
        postChangeNotification(type: .updated, annotation: annotation)
        updateAnnotationInTree(annotation)
    }

    // MARK: - Delete annotation
    func deleteAnnotation(id: Int64) throws {
        guard let db = db else { throw NSError(domain: "DBNil", code: 1) }

        // Get annotation before deleting (untuk notification)
        let annotationToDelete = loadAnnotationById(id)

        let row = annotationsTable.filter(annId == id)
        try db.run(row.delete())

        // Update caches
        cacheQueue.sync {
            cacheById.removeValue(forKey: id)
            for (key, anns) in cacheByContent {
                if let idx = anns.firstIndex(where: { $0.id == id }) {
                    var copy = anns
                    copy.remove(at: idx)
                    cacheByContent[key] = copy
                }
            }
        }

        // 🔔 Post notification
        postChangeNotification(type: .deleted, annotation: annotationToDelete, annotationId: id)
        removeAnnotationFromTree(id: id)
    }

    // MARK: - Load annotations for a book content
    func loadAnnotations(bkId: Int, contentId: Int) -> [Annotation] {
        let key = ContentKey(bkId: bkId, contentId: contentId)

        if let cached = cacheQueue.sync(execute: { cacheByContent[key] }) {
            return cached
        }

        guard let db = db else { return [] }
        var result: [Annotation] = []
        do {
            let query = annotationsTable.filter(annBkId == bkId && annContentId == contentId).order(annStart)
            for row in try db.prepare(query) {
                let id = row[annId]
                let start = row[annStart]
                let length = row[annLength]
                let startDiac = row[annStartDiac]
                let lengthDiac = row[annLengthDiac]
                let color = row[annColor]
                let type = row[annType]
                let note = row[annNote]
                let created = row[annCreatedAt]
                let context = row[annContext]
                let page = row[annPage]
                let part = row[annPart]
                let ann = Annotation(
                    id: id,
                    bkId: bkId,
                    contentId: contentId,
                    range: NSRange(location: start, length: length),
                    rangeDiacritics: NSRange(location: startDiac, length: lengthDiac),
                    colorHex: color,
                    type: AnnotationMode.from(int: type),
                    note: note,
                    createdAt: created,
                    context: context,
                    page: page,
                    part: part,
                    pageArb: String(page).convertToArabicDigits(),
                    partArb: String(part).convertToArabicDigits()
                )
                result.append(ann)
            }

            cacheQueue.sync {
                cacheByContent[key] = result
                for ann in result {
                    if let id = ann.id { cacheById[id] = ann }
                }
            }
        } catch {
            print("loadAnnotations error:", error)
        }
        return result
    }

    // MARK: - Load single annotation by id
    func loadAnnotationById(_ id: Int64) -> Annotation? {
        if let cached = cacheQueue.sync(execute: { cacheById[id] }) {
            return cached
        }

        guard let db = db else { return nil }
        do {
            let query = annotationsTable.filter(annId == id)
            if let row = try db.pluck(query) {
                let page = row[annPage]
                let part = row[annPart]
                let ann = Annotation(
                    id: row[annId],
                    bkId: row[annBkId],
                    contentId: row[annContentId],
                    range: NSRange(location: row[annStart], length: row[annLength]),
                    rangeDiacritics: NSRange(location: row[annStartDiac], length: row[annLengthDiac]),
                    colorHex: row[annColor],
                    type: AnnotationMode.from(int: row[annType]),
                    note: row[annNote],
                    createdAt: row[annCreatedAt],
                    context: row[annContext],
                    page: page,
                    part: part,
                    pageArb: String(page).convertToArabicDigits(),
                    partArb: String(part).convertToArabicDigits()
                )
                cacheQueue.sync {
                    cacheById[id] = ann
                    let key = ContentKey(bkId: ann.bkId, contentId: ann.contentId)
                    var arr = cacheByContent[key] ?? []
                    if !arr.contains(where: { $0.id == ann.id }) {
                        arr.append(ann)
                        arr.sort { $0.range.location < $1.range.location }
                        cacheByContent[key] = arr
                    }
                }
                return ann
            }
        } catch {
            print("loadAnnotationById error:", error)
        }
        return nil
    }

    // MARK: - Cache helpers
    func clearAllCaches() {
        cacheQueue.sync {
            cacheById.removeAll()
            cacheByContent.removeAll()
        }
    }

    /*
    func clearCache(for bkId: Int, contentId: Int) {
        let key = ContentKey(bkId: bkId, contentId: contentId)
        cacheQueue.sync {
            if let anns = cacheByContent.removeValue(forKey: key) {
                for a in anns { if let id = a.id { cacheById.removeValue(forKey: id) } }
            }
        }
    }
     */


    // MARK: - DISPLAY ALL ANNOTATIONS
    func loadAnnotations() -> [Annotation] {
        guard let db = db else { return [] }
        var result: [Annotation] = []
        do {
            let query = annotationsTable.order(annStart)
            for row in try db.prepare(query) {
                let id = row[annId]
                let bkId = row[annBkId]
                let start = row[annStart]
                let length = row[annLength]
                let startDiac = row[annStartDiac]
                let lengthDiac = row[annLengthDiac]
                let contentId = row[annContentId]
                let color = row[annColor]
                let type = row[annType]
                let note = row[annNote]
                let created = row[annCreatedAt]
                let page = row[annPage]
                let part = row[annPart]
                let ann = Annotation(
                    id: id,
                    bkId: bkId,
                    contentId: contentId,
                    range: NSRange(location: start, length: length),
                    rangeDiacritics: NSRange(location: startDiac, length: lengthDiac),
                    colorHex: color,
                    type: AnnotationMode.from(int: type),
                    note: note,
                    createdAt: created,
                    context: row[annContext],
                    page: page,
                    part: part,
                    pageArb: String(page).convertToArabicDigits(),
                    partArb: String(part).convertToArabicDigits()
                )
                result.append(ann)
            }
        } catch {
            print("loadAnnotations error:", error)
        }
        return result
    }
    
    /*
    func buildAnnotationTree(for bkId: Int) -> AnnotationNode? {
        guard let book = LibraryDataManager.shared.booksById[bkId] else { return nil }
        let root = AnnotationNode(title: book.book)
        let anns = AnnotationManager.shared.loadAnnotations()
        for ann in anns {
            let displayTitle: String
            if let note = ann.note, !note.isEmpty {
                displayTitle = note
            } else {
                displayTitle = ann.context
            }
            let child = AnnotationNode(title: displayTitle, annotation: ann)
            root.children.append(child)
        }
        return root
    }
     */
     

    // MARK: - Build Tree
    func buildAnnotationTree() {
        treeQueue.async { [weak self] in
            guard let self = self else { return }

            let root = AnnotationNode(title: "All Books")
            let anns = self.loadAnnotations()
            let grouped = Dictionary(grouping: anns, by: { $0.bkId })
            let sortedBooks = grouped.keys
                .compactMap { LibraryDataManager.shared.getBook([$0]).first }
                .sorted { $0.book.localizedCaseInsensitiveCompare($1.book) == .orderedAscending }

            for book in sortedBooks {
                let annsForBook = grouped[book.id] ?? []
                let bookNode = AnnotationNode(title: book.book)

                let sortedAnns = annsForBook.sorted { $0.createdAt > $1.createdAt }

                for ann in sortedAnns {
                    let displayTitle: String
                    if let note = ann.note, !note.isEmpty {
                        displayTitle = note
                    } else {
                        displayTitle = ann.context
                    }
                    let child = AnnotationNode(title: displayTitle, annotation: ann)
                    bookNode.children.append(child)
                }

                root.children.append(bookNode)
            }

            self._rootNode = root

            // Post notification bahwa tree sudah ready
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .annotationTreeDidUpdate,
                    object: self
                )
            }
        }
    }

    // MARK: - Tree Manipulation (dipanggil dari notification handler)
    func addAnnotationToTree(_ annotation: Annotation) {
        treeQueue.async { [weak self] in
            guard let self = self, let root = self._rootNode else { return }

            let bookNode = self.findOrCreateBookNode(for: annotation.bkId, in: root)

            let displayTitle: String
            if let note = annotation.note, !note.isEmpty {
                displayTitle = note
            } else {
                displayTitle = annotation.context
            }

            let annotationNode = AnnotationNode(title: displayTitle, annotation: annotation)
            bookNode.children.append(annotationNode)

            bookNode.children.sort { ann1, ann2 in
                guard let a1 = ann1.annotation, let a2 = ann2.annotation else { return false }
                return a1.createdAt > a2.createdAt
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .annotationTreeDidUpdate,
                    object: self
                )
            }
        }
    }

    func updateAnnotationInTree(_ annotation: Annotation) {
        treeQueue.async { [weak self] in
            guard let self = self,
                  let annotationId = annotation.id,
                  let node = self.findAnnotationNode(by: annotationId) else { return }

            if let note = annotation.note, !note.isEmpty {
                node.title = note
            } else {
                node.title = annotation.context
            }
            node.annotation = annotation

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .annotationTreeDidUpdate,
                    object: self
                )
            }
        }
    }

    func removeAnnotationFromTree(id: Int64) {
        treeQueue.async { [weak self] in
            guard let self = self, let root = self._rootNode else { return }

            for bookNode in root.children {
                if let index = bookNode.children.firstIndex(where: { $0.annotation?.id == id }) {
                    bookNode.children.remove(at: index)
                    
                    if bookNode.children.isEmpty {
                        if let bookIndex = root.children.firstIndex(where: { $0 === bookNode }) {
                            root.children.remove(at: bookIndex)
                        }
                    }
                    break
                }
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .annotationTreeDidUpdate,
                    object: self
                )
            }
        }
    }

    // MARK: - Private Helpers
    private func findOrCreateBookNode(for bkId: Int, in root: AnnotationNode) -> AnnotationNode {
        if let existing = root.children.first(where: { node in
            guard let firstChild = node.children.first,
                  let annotation = firstChild.annotation else { return false }
            return annotation.bkId == bkId
        }) {
            return existing
        }

        guard let book = LibraryDataManager.shared.getBook([bkId]).first else {
            let fallbackNode = AnnotationNode(title: "Unknown Book")
            root.children.append(fallbackNode)
            return fallbackNode
        }

        let bookNode = AnnotationNode(title: book.book)
        root.children.append(bookNode)
        root.children.sort { $0.title < $1.title }

        return bookNode
    }

    private func findAnnotationNode(by id: Int64) -> AnnotationNode? {
        guard let root = _rootNode else { return nil }

        for bookNode in root.children {
            if let found = bookNode.children.first(where: { $0.annotation?.id == id }) {
                return found
            }
        }
        return nil
    }

    // MARK: - Invalidate Cache
    func invalidateTree() {
        treeQueue.async { [weak self] in
            self?._rootNode = nil
        }
    }
}
