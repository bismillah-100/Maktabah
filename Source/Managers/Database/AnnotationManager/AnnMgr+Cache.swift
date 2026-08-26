//
//  AnnMgr+Cache.swift
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
            updateSingleAnnotationCache(annotation)
        }
    }

    func updateCacheAfterUpdate(_ annotation: Annotation) {
        _cacheQueue.sync {
            updateSingleAnnotationCache(annotation)
        }
    }

    private func updateSingleAnnotationCache(_ annotation: Annotation) {
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
                updateSingleAnnotationCache(annotation)
            }
        }

        _treeQueue.async { [weak self] in
            guard let self else { return }
            updateTreeNodesForBatch(annotations: annotations, uploadToCloudKit: uploadToCloudKit)
        }
    }

    private func updateTreeNodesForBatch(annotations: [Annotation], uploadToCloudKit: Bool) {
        if _groupingMode == .book {
            for annotation in annotations {
                guard let annotationId = annotation.id,
                      let node = findAnnotationNode(by: annotationId)
                else {
                    postChangeNotification(type: .updated, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
                    continue
                }
                node.update(with: annotation)
                postChangeNotification(type: .updated, annotation: annotation, uploadToCloudKit: uploadToCloudKit)
            }
        } else {
            performBatchTagTreeUpdate(annotations, uploadToCloudKit: uploadToCloudKit)
        }
    }
}
