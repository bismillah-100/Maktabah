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

    // MARK: - Data
    var annotation: Annotation!
    weak var delegate: AnnotationEditorDelegate?

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
            saveButton.borderShape = .circle
            deleteButton.borderShape = .circle
            segmentedControl.borderShape = .circle
        }
        
        setupSegmentLayout()
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
    }

    // MARK: - Actions
    @objc func saveTapped() {
        // update annotation object
        let newNote = noteField.string
        let newColorHex = hexString(from: colorWell.color) ?? "#FFEA00"

        var updated = annotation!
        updated = Annotation(
            id: annotation.id,
            bkId: annotation.bkId,
            contentId: annotation.contentId,
            range: annotation.range, 
            rangeDiacritics: annotation.rangeDiacritics,
            colorHex: newColorHex,
            type: annotation.type,
            note: newNote.isEmpty ? nil : newNote,
            createdAt: annotation.createdAt,
            context: annotation.context,
            page: annotation.page,
            part: annotation.part,
            pageArb: annotation.pageArb,
            partArb: annotation.partArb
        )

        // Persist ke DB
        delegate?.annotationEditorDidSave(updated)
        cancelTapped()
    }

    @objc func deleteTapped() {
        guard let id = annotation.id else { return }

        // Ambil annotation dari cache/DB sebelum dihapus
        guard let annToRemove = AnnotationManager.shared.loadAnnotationById(id) else {
            // fallback: jika tidak ditemukan, tetap coba hapus by id
            do {
                try AnnotationManager.shared.deleteAnnotation(id: id)
                // delegate tidak punya range; kita bisa notify dengan annotation minimal
                if let ann = annotation {
                    delegate?.annotationEditorDidDelete([ann])
                }
                cancelTapped()
            } catch {
                print(error)
            }
            return
        }

        do {
            // Hapus di DB + cache
            try AnnotationManager.shared.deleteAnnotation(id: id)

            // Notify delegate dengan objek annotation yang sudah diambil sebelumnya
            delegate?.annotationEditorDidDelete([annToRemove])

            cancelTapped()
        } catch {
            print(error)
        }
    }

    @objc func cancelTapped() {
        view.window?.performClose(nil)
    }

    @IBAction func underLineTapped(_ sender: NSButton) {
        annotation.type = underLine.state == .on ? .underline : .highlight
        colorWell.isHidden = underLine.state == .on
    }

    // MARK: - Helpers
    private func hexString(from color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}


// Pastikan AppDelegate sudah import Cocoa dan memiliki textView outlet
extension IbarotTextView: AnnotationEditorDelegate {
    // Panggil ini dari textView clickedOnLink (saat user klik annotation://id)
    func presentAnnotationEditor(_ annotation: Annotation, atCharIndex charIndex: Int, in textView: NSTextView) {
        let editor = AnnotationEditorVC()
        editor.annotation = annotation
        editor.delegate = self

        let pop = NSPopover()
        pop.contentViewController = editor
        pop.behavior = .transient

        // simpan popover di property jika perlu (agar tidak dealloc)
        // misal: self.currentPopover = pop

        // Hit lokasi glyph rect untuk charIndex
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
            let containerOrigin = textView.textContainerOrigin
            let screenRect = NSRect(x: glyphRect.origin.x + containerOrigin.x,
                                    y: glyphRect.origin.y + containerOrigin.y,
                                    width: glyphRect.width, height: glyphRect.height)
            pop.show(relativeTo: screenRect, of: textView, preferredEdge: .maxY)
        } else {
            pop.show(relativeTo: textView.bounds, of: textView, preferredEdge: .maxY)
        }
    }

    // MARK: - AnnotationEditorDelegate
    func annotationEditorDidSave(_ annotation: Annotation) {
        // Jika annotation.id == nil → baru, simpan; jika ada id → update
        var annToSave = annotation
        if annToSave.id == nil {
            do {
                let newId = try AnnotationManager.shared.addAnnotation(annToSave)
                annToSave.id = newId
            } catch {
                #if DEBUG
                print("Gagal menyimpan anotasi baru:", error)
                #endif
                return
            }
        } else {
            do {
                try AnnotationManager.shared.updateAnnotation(annToSave)
            } catch {
                #if DEBUG
                print("Gagal update anotasi:", error)
                #endif
                return
            }
        }

        // Apply annotations ulang untuk content terkait (gunakan bkId/contentId)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let ts = textStorage {
                let anns = AnnotationManager.shared.loadAnnotations(bkId: annToSave.bkId, contentId: annToSave.contentId)
                renderer.applyAnnotations(anns, to: ts, showHarakat: state.showHarakat)
                setSelectedRange(NSRange(location: NSNotFound, length: 0))
            }
        }
    }

    func annotationEditorDidDelete(_ deleted: [Annotation]) {
        guard !deleted.isEmpty, let ts = textStorage,
              let key = contentKey() else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            ts.beginEditing()
            for delete in deleted {
                guard delete.bkId == key.bkId,
                      delete.contentId == key.contentId
                else { continue }
                let range = TextViewState.shared.showHarakat ? delete.rangeDiacritics : delete.range
                // 1) Hapus atribut visual pada range yang dihapus
                removeAttributesForRange(range, in: ts)
            }
            setSelectedRange(NSRange(location: NSNotFound, length: 0))
            ts.endEditing()
        }
    }

    func removeAttributesForRange(_ range: NSRange, in textStorage: NSTextStorage) {
        guard range.location >= 0, range.length > 0, range.location + range.length <= textStorage.length else { return }
        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        textStorage.removeAttribute(.backgroundColor, range: range)
        textStorage.removeAttribute(.underlineStyle, range: range)
        textStorage.removeAttribute(.link, range: range)
        textStorage.removeAttribute(NSAttributedString.Key("annotationNote"), range: range)
        textStorage.removeAttribute(NSAttributedString.Key("underlineColor"), range: range)
    }
}
