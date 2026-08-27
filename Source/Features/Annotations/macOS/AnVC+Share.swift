//
//  AnVC+Share.swift
//  Maktabah
//

import Cocoa

extension AnnotationsVC {
    func setupShareMenu() {
        guard let menu = shareBtn.menu else { return }
        let exportJSONItem = NSMenuItem(
            title: "Export to JSON...".localized,
            action: #selector(exportSelectedJSON(_:)),
            keyEquivalent: ""
        )
        exportJSONItem.target = self
        menu.addItem(exportJSONItem)
    }

    func setupImportMenu() {
        guard let menu = setting.menu, menu.items.count >= 5 else { return }
        menu.insertItem(.separator(), at: 5)
        let importJSONItem = NSMenuItem(
            title: "Import from JSON...".localized,
            action: #selector(importJSON(_:)),
            keyEquivalent: ""
        )
        importJSONItem.target = self
        menu.insertItem(importJSONItem, at: 6)
    }

    func selectedOrEffectiveNodes() -> [AnnotationNode] {
        let selectedIndexes = outlineView.selectedRowIndexes
        if !selectedIndexes.isEmpty {
            return selectedIndexes.compactMap { outlineView.item(atRow: $0) as? AnnotationNode }
        }
        let clickedRow = outlineView.clickedRow
        if clickedRow >= 0, let item = outlineView.item(atRow: clickedRow) as? AnnotationNode {
            return [item]
        }
        return []
    }

    func extractAnnotations(from nodes: [AnnotationNode]) -> [Annotation] {
        var result: [Annotation] = []
        var seenIDs = Set<Int64>()

        func collect(node: AnnotationNode) {
            if let ann = node.annotation, let id = ann.id {
                if seenIDs.insert(id).inserted {
                    result.append(ann)
                }
            }
            for child in node.children {
                collect(node: child)
            }
        }

        nodes.forEach { collect(node: $0) }
        return result
    }

    @IBAction func saveRTFToFile(_ sender: Any?) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.rtf]
        savePanel.nameFieldStringValue = "Exported_Annotations.rtf"

        savePanel.begin { [weak self] response in
            guard let self, response == .OK, let url = savePanel.url else { return }
            guard let data = dataSource.exportToRTF() else { return }
            do {
                try data.write(to: url)
                #if DEBUG
                print("Berhasil ekspor ke: \(url.path)")
                #endif
            } catch {
                ReusableFunc.showAlert(title: "Error", message: error.localizedDescription)
            }
        }
    }

    @IBAction func exportSelectedJSON(_ sender: Any?) {
        let nodes = selectedOrEffectiveNodes()
        let annotations = extractAnnotations(from: nodes)
        guard !annotations.isEmpty else {
            ReusableFunc.showAlert(
                title: "No Selection".localized,
                message: "Please select one or more annotations or books to export.".localized
            )
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "maktabah_annotations.json"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            Task.detached(priority: .userInitiated) {
                guard let jsonString = AnnotationJsonSerializer.encode(annotations: annotations),
                      let jsonData = jsonString.data(using: .utf8)
                else {
                    await MainActor.run {
                        ReusableFunc.showAlert(
                            title: "Error".localized,
                            message: "Failed to encode annotations to JSON.".localized
                        )
                    }
                    return
                }
                do {
                    try jsonData.write(to: url)
                    #if DEBUG
                    print("Exported \(annotations.count) annotations to: \(url.path)")
                    #endif
                } catch {
                    await MainActor.run {
                        ReusableFunc.showAlert(title: "Error".localized, message: error.localizedDescription)
                    }
                }
            }
        }
    }

    @IBAction func importJSON(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        openPanel.begin { response in
            guard response == .OK, let url = openPanel.url else { return }
            Task.detached(priority: .userInitiated) {
                do {
                    let data = try Data(contentsOf: url)
                    let decoded = try AnnotationJsonSerializer.decode(from: data)
                    await MainActor.run {
                        guard !decoded.isEmpty else {
                            ReusableFunc.showAlert(
                                title: "Import Annotations".localized,
                                message: "No annotations found in the selected file.".localized
                            )
                            return
                        }

                        let alert = NSAlert()
                        alert.messageText = "Import Annotations".localized
                        alert.informativeText = "Some annotations may already exist. How would you like to handle duplicates?".localized
                        alert.addButton(withTitle: "Overwrite Existing".localized)
                        alert.addButton(withTitle: "Skip Duplicates".localized)
                        alert.addButton(withTitle: "Cancel".localized)

                        let alertResponse = alert.runModal()
                        guard alertResponse != .alertThirdButtonReturn else { return }

                        let overwrite = (alertResponse == .alertFirstButtonReturn)
                        Task.detached(priority: .userInitiated) {
                            do {
                                let count = try AnnotationManager.shared.importAnnotations(decoded, overwrite: overwrite)
                                await MainActor.run {
                                    let successMsg = String(format: "%d annotations imported successfully".localized, count)
                                    ReusableFunc.showAlert(title: "Import Annotations".localized, message: successMsg)
                                }
                            } catch {
                                await MainActor.run {
                                    ReusableFunc.showAlert(title: "Import Failed".localized, message: error.localizedDescription)
                                }
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        ReusableFunc.showAlert(title: "Import Failed".localized, message: error.localizedDescription)
                    }
                }
            }
        }
    }
}
