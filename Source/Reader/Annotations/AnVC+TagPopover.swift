//
//  AnVC+TagPopover.swift
//  Maktabah
//

import Cocoa

extension AnnotationsVC {
    func createRootTitlebarStack() {
        if !titlebarRootStack.arrangedSubviews.isEmpty { return }

        titlebarRootStack.addArrangedSubview(headerStackView)

        if #unavailable(macOS 26) {
            let box = NSBox()
            box.boxType = .separator
            box.translatesAutoresizingMaskIntoConstraints = false
            titlebarRootStack.addArrangedSubview(box)
        }

        let filterBar = createTagFilterBar()
        titlebarRootStack.addArrangedSubview(filterBar)

        dataSource.viewModel.onTagsChanged = { [weak self] tags in
            self?.updateChips(allTags: tags)
        }

        updateChips(allTags: dataSource.viewModel.availableTags)
    }

    func presentTagPopover(
        mode: AnnotationTagVC.Mode,
        annotationIDs: [Int64],
        anchorRect: NSRect
    ) {
        tagPopover?.performClose(nil)

        let tagVC = AnnotationTagVC()
        tagVC.mode = mode
        tagVC.annotationIDs = annotationIDs
        tagVC.availableTags = switch mode {
        case .add: AnnotationManager.shared.allTagNames()
        case .remove: commonTags(for: annotationIDs)
        }
        tagVC.onSubmit = { [weak self] mode, tags, annotationIDs in
            self?.applyTags(tags, mode: mode, to: annotationIDs)
        }
        tagVC.onCancel = { [weak self] in
            self?.tagPopover = nil
        }

        let popover = NSPopover()
        popover.contentViewController = tagVC
        popover.behavior = .transient
        popover.show(relativeTo: anchorRect, of: outlineView, preferredEdge: .maxY)
        tagPopover = popover
    }

    func applyTags(_ tags: [String], mode: AnnotationTagVC.Mode, to annotationIDs: [Int64]) {
        guard !annotationIDs.isEmpty else { return }
        do {
            switch mode {
            case .add:
                for tag in tags {
                    try AnnotationManager.shared.addTag(tag, toAnnotationIDs: annotationIDs)
                }
            case .remove:
                for tag in tags {
                    try AnnotationManager.shared.removeTag(tag, fromAnnotationIDs: annotationIDs)
                }
            }
            tagPopover?.performClose(nil)
            updateChips(allTags: dataSource.viewModel.availableTags)
        } catch {
            ReusableFunc.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    func commonTags(for annotationIDs: [Int64]) -> [String] {
        let annotations = annotationIDs.compactMap { AnnotationManager.shared.loadAnnotationById($0) }
        guard let firstAnnotation = annotations.first else { return [] }

        let commonNormalized = annotations.dropFirst().reduce(
            Set(firstAnnotation.tags.map(normalizedTagName))
        ) { partialResult, annotation in
            partialResult.intersection(Set(annotation.tags.map(normalizedTagName)))
        }

        return firstAnnotation.tags.filter { commonNormalized.contains(normalizedTagName($0)) }
    }

    func normalizedTagName(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
