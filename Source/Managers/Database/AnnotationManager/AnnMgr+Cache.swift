//
//  AnnotationManager+Cache.swift
//  Maktabah
//

import Foundation

extension AnnotationManager {
    // MARK: - Clear

    func clearAllCaches() {
        _cacheQueue.sync {
            _cacheById.removeAll()
            _cacheByContent.removeAll()
            _cacheByBook.removeAll()
            _cacheTagsByAnnotationId.removeAll()
            _cachedAllTagNames = nil
        }
    }

    // MARK: - Post-Write Cache Updates

    func updateCacheAfterAdd(_ annotation: Annotation) {
        _cacheQueue.sync {
            guard let id = annotation.id else { return }
            _cacheById[id] = annotation
            _cacheTagsByAnnotationId[id] = annotation.tags
            let key = ContentKey(bkId: annotation.bkId, contentId: annotation.contentId)
            var arr = _cacheByContent[key] ?? []
            let idx = arr.insertionIndex(for: annotation) { $0.range.location < $1.range.location }
            arr.insert(annotation, at: idx)
            _cacheByContent[key] = arr
            if _cacheByBook[annotation.bkId] != nil {
                _cacheByBook[annotation.bkId]?.append(annotation)
            }
        }
    }

    func updateCacheAfterUpdate(_ annotation: Annotation) {
        _cacheQueue.sync {
            guard let id = annotation.id else { return }
            _cacheById[id] = annotation
            _cacheTagsByAnnotationId[id] = annotation.tags
            let key = ContentKey(bkId: annotation.bkId, contentId: annotation.contentId)
            var arr = _cacheByContent[key] ?? []
            if let idx = arr.firstIndex(where: { $0.id == id }) {
                arr[idx] = annotation
            } else {
                let idx = arr.insertionIndex(for: annotation) { $0.range.location < $1.range.location }
                arr.insert(annotation, at: idx)
            }
            _cacheByContent[key] = arr
            if var bookArr = _cacheByBook[annotation.bkId] {
                if let idx = bookArr.firstIndex(where: { $0.id == id }) {
                    bookArr[idx] = annotation
                } else {
                    bookArr.append(annotation)
                }
                _cacheByBook[annotation.bkId] = bookArr
            }
        }
    }

    func updateCacheAfterDelete(id: Int64, annotation: Annotation?) {
        _cacheQueue.sync {
            _cachedAllTagNames = nil
            _cacheById.removeValue(forKey: id)
            _cacheTagsByAnnotationId.removeValue(forKey: id)
            if let bkId = annotation?.bkId {
                _cacheByBook[bkId] = _cacheByBook[bkId]?.filter { $0.id != id }
            }
            for (key, anns) in _cacheByContent {
                if let idx = anns.firstIndex(where: { $0.id == id }) {
                    var copy = anns
                    copy.remove(at: idx)
                    _cacheByContent[key] = copy
                }
            }
        }
    }

    // MARK: - Batch Tag Update

    func applyBatchTagUpdates(_ annotations: [Annotation], uploadToCloudKit: Bool = true) {
        guard !annotations.isEmpty else { return }

        _cacheQueue.sync {
            _cachedAllTagNames = nil
            for annotation in annotations {
                guard let id = annotation.id else { continue }
                _cacheById[id] = annotation
                _cacheTagsByAnnotationId[id] = annotation.tags

                let key = ContentKey(bkId: annotation.bkId, contentId: annotation.contentId)
                var cachedAnnotations = _cacheByContent[key] ?? []
                if let index = cachedAnnotations.firstIndex(where: { $0.id == id }) {
                    cachedAnnotations[index] = annotation
                } else {
                    let index = cachedAnnotations.insertionIndex(for: annotation) {
                        $0.range.location < $1.range.location
                    }
                    cachedAnnotations.insert(annotation, at: index)
                }
                _cacheByContent[key] = cachedAnnotations

                if var bookArr = _cacheByBook[annotation.bkId] {
                    if let index = bookArr.firstIndex(where: { $0.id == id }) {
                        bookArr[index] = annotation
                    } else {
                        bookArr.append(annotation)
                    }
                    _cacheByBook[annotation.bkId] = bookArr
                }
            }
        }

        _treeQueue.async { [weak self] in
            guard let self else { return }
            if self._groupingMode == .book {
                for annotation in annotations {
                    guard let annotationId = annotation.id,
                          let node = self.findAnnotationNode(by: annotationId)
                    else {
                        self.postChangeNotification(type: .updated, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
                        continue
                    }
                    if let note = annotation.note, !note.isEmpty {
                        node.title = note
                    } else {
                        node.title = annotation.context
                    }
                    node.annotation = annotation
                    self.postChangeNotification(type: .updated, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
                }
            } else {
                self.performBatchTagTreeUpdate(annotations, uploadToCloudKit: uploadToCloudKit)
            }
        }
    }
}
