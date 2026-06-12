//
//  AnnotationsEditorViewController.swift
//  annotations
//
//  Created by MacBook on 13/12/25.
//

import Cocoa

class AnnotationEditorVC: NSViewController {

    // MARK: - UI

    @IBOutlet weak var noteField: NSTextView!

    @IBOutlet weak var colorWell: NSColorWell!

    @IBOutlet weak var underLine: NSButton!

    @IBOutlet weak var saveButton: NSButton!

    @IBOutlet weak var deleteButton: NSButton!
    
    @IBOutlet weak var segmentedControl: NSSegmentedControl!

    @IBOutlet weak var tagsField: NSTokenField!

    // MARK: - Data
    var annotation: Annotation!

    override func viewDidLoad() {
        super.viewDidLoad()
        noteField.alignment = .right
        noteField.font = NSFont(
            name: UserDefaults.standard.textViewFontName,
            size: CGFloat(UserDefaults.standard.textViewFontSize - 4)
        )
        populateFields()
        saveButton.action = #selector(saveTapped)
        deleteButton.action = #selector(deleteTapped)

        underLine.state = annotation.type == .underline ? .on : .off
        colorWell.isHidden = underLine.state == .on
        
        if #available(macOS 26, *) {
            saveButton.borderShape = .capsule
            deleteButton.borderShape = .capsule
            segmentedControl.borderShape = .capsule
        }
        
        setupSegmentLayout()
        tagsField.delegate = self
        tagsField.completionDelay = 0.5
    }
    
    private func setupSegmentLayout() {
        let userDecision = UserDefaults.standard.integer(forKey: "annotationsLayoutDirection")
        segmentedControl.selectedSegment = userDecision
        alignmentChanged(segmentedControl)
    }

    @IBAction func alignmentChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: noteField.alignment = .left
        case 1: noteField.alignment = .right
        default: break
        }
        UserDefaults.standard.setValue(sender.selectedSegment, forKey: "annotationsLayoutDirection")
    }

    private func populateFields() {
        noteField.string = annotation.note ?? ""
        if let color = NSColor(hex: annotation.colorHex) {
            colorWell.color = color
        } else {
            colorWell.color = NSColor.yellow
        }
        tagsField.objectValue = annotation.tags
    }

    // MARK: - Actions
    @objc func saveTapped() {
        let newNote = noteField.string
        let newColorHex = colorWell.color.hexString()

        var updated = annotation!

        updated.colorHex = newColorHex
        updated.note = newNote.isEmpty ? nil : newNote
        updated.tags = normalizedTags()

        do {
            if updated.id == nil {
                try AnnotationManager.shared.addAnnotation(updated)
            } else {
                try AnnotationManager.shared.updateAnnotation(updated)
            }
        } catch {
            print("Gagal menyimpan/update anotasi:", error)
        }
        
        cancelTapped()
    }

    @objc func deleteTapped() {
        guard let id = annotation.id else { return }

        do {
            // Hapus di DB + cache
            try AnnotationManager.shared.deleteAnnotation(id: id)
            cancelTapped()
        } catch {
            print("Gagal menghapus anotasi:", error)
        }
    }

    @objc func cancelTapped() {
        view.window?.performClose(nil)
    }

    @IBAction func underLineTapped(_ sender: NSButton) {
        annotation.type = underLine.state == .on ? .underline : .highlight
        colorWell.isHidden = underLine.state == .on
    }

    // MARK: - Tag Suggestions

    /// Ambil semua tag yang sudah ada di DB, dikecualikan yang sudah dipilih.
    private func existingTagSuggestions(matching substring: String) -> [String] {
        let allTags = AnnotationManager.shared.allTagNames()
        let currentTokens = (tagsField.objectValue as? [String] ?? [])
        return allTags.filter { tag in
            !currentTokens.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) &&
            tag.range(of: substring, options: [.caseInsensitive, .anchored]) != nil
        }
    }

    private func normalizedTags() -> [String] {
        if let tokens = tagsField.objectValue as? [String] {
            return tokens
        }

        return tagsField.stringValue
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
        indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?
    ) -> [Any]? {
        guard !substring.isEmpty else { return nil }
        return existingTagSuggestions(matching: substring)
    }
}
