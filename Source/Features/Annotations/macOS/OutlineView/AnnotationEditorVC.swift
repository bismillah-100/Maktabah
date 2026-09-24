//
//  AnnotationEditorVC.swift
//  annotations
//
//  Created by MacBook on 13/12/25.
//

import Cocoa
import OSLog

class AnnotationEditorVC: NSViewController {
    // MARK: - UI

    @IBOutlet weak var noteField: NSTextView!

    @IBOutlet weak var colorWell: NSColorWell!

    @IBOutlet weak var underLine: NSButton!

    @IBOutlet weak var saveButton: NSButton!

    @IBOutlet weak var deleteButton: NSButton!

    @IBOutlet weak var tagsField: NSTokenField!

    // MARK: - Data

    lazy var currentFont: NSFont = .init(
        name: UserDefaults.standard.textViewFontName,
        size: CGFloat(UserDefaults.standard.textViewFontSize - 4),
    ) ?? .systemFont(ofSize: NSFont.systemFontSize)

    var annotation: Annotation!

    var onSave: ((Annotation) -> Void)?
    var onDelete: ((Int64) -> Void)?
    var onCancel: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        noteField.delegate = self
        noteField.font = currentFont
        populateFields()
        saveButton.action = #selector(saveTapped)
        deleteButton.action = #selector(deleteTapped)

        saveButton.keyEquivalent = "\r"
        saveButton.keyEquivalentModifierMask = .command

        underLine.state = annotation.type == .underline ? .on : .off

        if #available(macOS 26, *) {
            saveButton.borderShape = .capsule
            deleteButton.borderShape = .capsule
        }

        tagsField.delegate = self
        tagsField.completionDelay = 0.5
    }

    private func populateFields() {
        noteField.string = annotation.note ?? ""
        if let color = NSColor(hex: annotation.colorHex) {
            colorWell.color = color
        } else {
            colorWell.color = NSColor.yellow
        }
        tagsField.objectValue = annotation.tags
        updateParagraphAlignments()
    }

    func updateParagraphAlignments() {
        guard let textStorage = noteField.textStorage else { return }

        let selectedRanges = noteField.selectedRanges
        noteField.typingAttributes[.font] = currentFont
        textStorage.applyAutoDirectionAlignments(font: currentFont)
        noteField.selectedRanges = selectedRanges
    }

    // MARK: - Key Handling

    override func cancelOperation(_ sender: Any?) {
        cancelTapped()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            if event.charactersIgnoringModifiers == "s" {
                saveTapped()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Actions

    @objc func saveTapped() {
        let newNote = noteField.string
        let newColorHex = colorWell.color.hexString()

        var updated = annotation!

        updated.colorHex = newColorHex
        updated.note = newNote.isEmpty ? nil : newNote
        updated.tags = normalizedTags()

        if let onSave {
            onSave(updated)
        } else {
            do {
                if updated.id == nil {
                    try AnnotationStore.shared.addAnnotation(updated)
                } else {
                    try AnnotationStore.shared.updateAnnotation(updated)
                }
            } catch {
                Logger.annotations.error("Gagal menyimpan/update anotasi: \(error.localizedDescription, privacy: .public)")
            }
        }

        dismissEditor()
    }

    @objc func deleteTapped() {
        guard let id = annotation.id else { return }

        if let onDelete {
            onDelete(id)
        } else {
            do {
                try AnnotationStore.shared.deleteAnnotation(id: id)
            } catch {
                Logger.annotations.error("Gagal menghapus anotasi: \(error.localizedDescription, privacy: .public)")
            }
        }

        dismissEditor()
    }

    @objc func cancelTapped() {
        onCancel?()
        dismissEditor()
    }

    private func dismissEditor() {
        if let presentingViewController {
            presentingViewController.dismiss(self)
        } else if let sheetParent = view.window?.sheetParent {
            sheetParent.endSheet(view.window!)
        } else {
            view.window?.performClose(nil)
        }
    }

    @IBAction func underLineTapped(_ sender: NSButton) {
        annotation.type = underLine.state == .on ? .underline : .highlight
    }

    // MARK: - Tag Suggestions

    /// Ambil semua tag yang sudah ada di DB, dikecualikan yang sudah dipilih.
    private func existingTagSuggestions(matching substring: String) -> [String] {
        let allTags = AnnotationStore.shared.allTagNames()
        let currentTokens = (tagsField.objectValue as? [String] ?? [])
        let cleanSub = substring.trimmingCharacters(in: .whitespacesAndNewlines)

        return allTags.filter { tag in
            let notAlreadyAdded = !currentTokens.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
            guard notAlreadyAdded else { return false }

            if cleanSub.isEmpty {
                return true
            }
            return tag.localizedCaseInsensitiveContains(cleanSub)
        }
    }

    private func normalizedTags() -> [String] {
        if let tokens = tagsField.objectValue as? [String] {
            return tokens
        }

        return tagsField.stringValue
            .replacingOccurrences(of: "،", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - NSTokenFieldDelegate

extension AnnotationEditorVC: NSTokenFieldDelegate {
    func tokenField(
        _ tokenField: NSTokenField,
        completionsForSubstring substring: String,
        indexOfToken tokenIndex: Int,
        indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?,
    ) -> [Any]? {
        existingTagSuggestions(matching: substring)
    }

    func tokenField(
        _ tokenField: NSTokenField,
        displayStringForRepresentedObject representedObject: Any,
    ) -> String? {
        representedObject as? String
    }

    func tokenField(
        _ tokenField: NSTokenField,
        representedObjectForEditing editingString: String,
    ) -> Any? {
        editingString
    }
}

// MARK: - NSTextViewDelegate

extension AnnotationEditorVC: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        updateParagraphAlignments()
    }
}
