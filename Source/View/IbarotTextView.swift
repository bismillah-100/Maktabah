//
//  StylingTextView.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

import Cocoa

class IbarotTextView: NSTextView {
    let state = TextViewState.shared
    let renderer = ArabicTextRenderer()  // ← NEW
    let annotationCoordinator = AnnotationCoordinator()  // ← NEW

    private var annotationObserver: NSObjectProtocol?
    private var annotationClickSetting: NSObjectProtocol?

    override var string: String {
        didSet {
            let attributedString = NSMutableAttributedString(
                string: string,
                attributes: state.defaultAttributes
            )
            textStorage?.setAttributedString(attributedString)
        }
    }

    var diacriticsIbarot: String? {
        guard let bkId, let contentId else { return nil }
        return BookPageCache.shared.get(bookId: bkId, contentId: contentId)?
            .nash
    }

    var bkId: Int?
    var contentId: Int?
    var page: Int?
    var part: Int?

    func contentKey() -> ContentKey? {
        guard let b = bkId, let c = contentId else { return nil }
        return ContentKey(bkId: b, contentId: c)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        setupTextView()
        annotationObserver = NotificationCenter.default.addObserver(
            forName: .annotationDidDeleteFromOutline,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                let anns = userInfo["annotations"] as? [Annotation]
            else {
                #if DEBUG
                    print("error notification")
                #endif
                return
            }
            self?.annotationEditorDidDelete(anns)
        }

        annotationClickSetting = NotificationCenter.default.addObserver(
            forName: .didChangeClickableAnnotation,
            object: nil,
            queue: .current,
            using: { [weak self] notification in
                guard let userInfo = notification.userInfo,
                    let enable = userInfo["enable"] as? Bool
                else {
                    return
                }
                self?.editAnnotationOnClick(enable)
            }
        )
    }

    override func clicked(onLink link: Any, at charIndex: Int) {
        guard state.clickableAnnotation else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // single click → tampilkan popover
            if let urlStr = link as? String,
                let id = Int64(urlStr),
                let ann = AnnotationManager.shared.loadAnnotationById(id)
            {
                presentAnnotationEditor(
                    ann,
                    atCharIndex: charIndex,
                    in: self
                )
            }
        }
    }

    override func printView(_ sender: Any?) {
        let attrString = attributedString()
        // Ambil print info default
        let printInfo = NSPrintInfo.shared
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.scalingFactor = 1.0

        // Buat NSTextView sementara untuk menggambar attributed string
        let tmpTextView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 800)
        )
        tmpTextView.textStorage?.setAttributedString(attrString)
        let fr = NSRange(location: 0, length: attrString.length)
        tmpTextView.layoutManager?.ensureLayout(forCharacterRange: fr)

        // Jalankan print operation
        let op = NSPrintOperation(view: tmpTextView, printInfo: printInfo)

        /* Langsung ekspor ke pdf
         op.showsPrintPanel = false
         op.showsProgressPanel = false
         op.printInfo.dictionary()[NSPrintJobDisposition] = NSPrintJobDispositionSave
         op.printInfo.dictionary()[NSPrintJobSavingURL] = URL(fileURLWithPath: "/path/to/output.pdf")
         op.run()
         */

        if let window {
            op.runModal(
                for: window,
                delegate: nil,
                didRun: nil,
                contextInfo: nil
            )
        }

        op.cleanUp()
    }

    deinit {
        #if DEBUG
            print("deinit IbarotTextView")
        #endif
        if let annotationObserver,
           let annotationClickSetting
        {
            NotificationCenter.default.removeObserver(annotationObserver)
            NotificationCenter.default.removeObserver(annotationClickSetting)
        }
        annotationClickSetting = nil
        annotationObserver = nil
    }

    private func setupTextView() {
        // Setup untuk teks Arab
        alignment = .right  // RTL untuk Arab
        isEditable = false
        isAutomaticLinkDetectionEnabled = false
        linkTextAttributes = [:]
        displaysLinkToolTips = false
        textContainerInset = NSSize(width: 8, height: 4)
        enclosingScrollView?.autohidesScrollers = true
        enclosingScrollView?.hasVerticalScroller = true
        enclosingScrollView?.hasHorizontalScroller = false

        // Layout optimization - DISABLE untuk smooth scroll
        layoutManager?.allowsNonContiguousLayout = false
        linkTextAttributes = [
            .cursor: NSCursor.pointingHand,
            .underlineStyle: 0,
        ]
    }

    func editAnnotationOnClick(_ enable: Bool) {
        guard let ts = textStorage else { return }

        // Collect all annotation ranges first
        var annotationRanges: [(id: Int64, range: NSRange)] = []
        let fullRange = NSRange(location: 0, length: ts.length)

        ts.enumerateAttribute(
            NSAttributedString.Key("annotationID"),
            in: fullRange,
            options: []
        ) { value, range, _ in
            if let id = value as? Int64 {
                annotationRanges.append((id, range))
            }
        }

        // Batch update
        ts.beginEditing()
        if enable {
            refreshAnnotations()
        } else {
            for annotation in annotationRanges {
                ts.removeAttribute(.link, range: annotation.range)
            }
        }
        ts.endEditing()

        window?.invalidateCursorRects(for: self)
    }

    func loadText(_ text: String) {
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: state.defaultAttributes
        )
        textStorage?.setAttributedString(attributedString)
    }

    func loadIbarotText(_ text: String, color: NSColor = .header) {
        let attributedString = renderer.render(
            text: text,
            highlightColor: color,
            showHarakat: state.showHarakat
        )

        guard let ts = textStorage, let lm = layoutManager else { return }

        ts.beginEditing()
        ts.setAttributedString(attributedString)

        if let bkId = self.bkId, let contentId = self.contentId {
            let anns = AnnotationManager.shared.loadAnnotations(
                bkId: bkId,
                contentId: contentId
            )
            renderer.applyAnnotations(
                anns,
                to: ts,
                showHarakat: state.showHarakat
            )
        }

        ts.endEditing()

        let fullRange = NSRange(location: 0, length: ts.length)
        lm.ensureLayout(forCharacterRange: fullRange)
    }

    func updateLineHeight() {
        guard let ts = textStorage else { return }
        renderer.updateLineHeight(in: ts)  // ← simpel!
    }

    // Fungsi yang diperbarui: menerima data rotba
    func displayAuthor(
        _ rotba: String,
        rZahbi: String,
        for rowi: Rowi
    ) {
        let attributedString = NSMutableAttributedString()

        func appendLine(label: String, value: String?) {
            guard let value = value, !value.isEmpty else { return }
            attributedString.append(
                NSAttributedString(
                    string: label,
                    attributes: state.boldAttributes
                )
            )
            attributedString.append(
                NSAttributedString(
                    string: value,
                    attributes: state.defaultAttributes
                )
            )
            attributedString.append(NSAttributedString(string: "\n"))
        }

        // --- Tambahan Informasi Rowi ---
        appendLine(label: "الإسم: ", value: rowi.name)
        appendLine(label: "الطبقة: ", value: rowi.tabaqa?.convertedTabaqa())
        appendLine(label: "الولادة: ", value: rowi.wulida)
        appendLine(label: "الوفاة: ", value: rowi.tuwuffi)
        appendLine(label: "رُوي له: ", value: rowi.who)

        // --- Rotbah Ibnu Hajar ---
        appendLine(label: "رتبة عند ابن حجر: ", value: rotba)

        // --- Rotbah Adz-Dzahabi ---
        appendLine(label: "رتبة عند الذهبي: ", value: rZahbi)

        // Hapus newline terakhir jika ada
        if attributedString.string.hasSuffix("\n") {
            attributedString.deleteCharacters(
                in: NSRange(location: attributedString.length - 1, length: 1)
            )
        }

        textStorage?.setAttributedString(attributedString)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        guard contentKey() != nil, selectedRange().length > 0 else {
            return menu
        }

        let filtered = filterMenuItems(menu)
        let groupA = buildHighlightGroup()
        let (editItems) = buildNoteItem(event, filtered: filtered)

        menu.removeAllItems()
        addItemsToMenu(
            menu,
            groupA: groupA,
            editItems: editItems,
            filtered: filtered
        )

        return menu
    }

    // MARK: - Private Helpers

    private func filterMenuItems(_ menu: NSMenu) -> [NSMenuItem] {
        let actionsToHide: Set<Selector> = [
            #selector(NSText.cut(_:)),
            #selector(NSText.paste(_:)),
            #selector(NSText.selectAll(_:)),
            #selector(NSTextView.startSpeaking(_:)),
            #selector(NSTextView.stopSpeaking(_:)),
            #selector(NSText.showGuessPanel(_:)),
            #selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
        ]

        let identifierKeywords = [
            "cut", "paste", "selectall",
            "speech", "spelling", "substitution",
            "openlink", "copylink", "search",
        ]

        return menu.items.compactMap { item in
            guard !item.isSeparatorItem else { return nil }

            // 1. Action (paling stabil, RTL-safe)
            if let action = item.action, actionsToHide.contains(action) {
                return nil
            }

            // 2. Identifier (stabil, tidak dilokalisasi)
            if let id = item.identifier?.rawValue.lowercased(),
                identifierKeywords.contains(where: id.contains)
            {
                return nil
            }

            // 3. Struktur submenu sistem (Spelling / Speech)
            if item.hasSubmenu {
                return nil
            }

            guard var copy = item.copy() as? NSMenuItem else { return nil }
            updateItemImage(&copy)
            return copy
        }
    }

    private func updateItemImage(_ item: inout NSMenuItem) {
        if item.action == #selector(NSText.copy(_:)) {
            item.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: nil
            )
            return
        }

        let iconMap: [(String, String)] = [
            ("Look", "text.magnifyingglass.rtl"),
            ("Cari", "text.magnifyingglass.rtl"),
            ("بحث", "text.magnifyingglass.rtl"),
            ("Translate", "character.bubble"),
            ("Terjemah", "character.bubble"),
            ("ترجمة", "character.bubble"),
        ]

        // Public selector
        for (key, symbol) in iconMap {
            if item.title.localizedStandardContains(key) {
                item.image = NSImage(
                    systemSymbolName: symbol,
                    accessibilityDescription: nil
                )
                break
            }
        }
    }

    private func buildHighlightGroup() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // Highlight colors
        let colors: [(String, NSColor, Int)] = [
            ("Yellow".localized, .yellow, 1),
            ("Green".localized, .green, 2),
            ("Blue".localized, .highlightBlue, 3),
            ("Pink".localized, .systemPink, 4),
            ("Purple".localized, .purple, 5),
        ]

        for (title, color, tag) in colors {
            items.append(makeColorItem(title: title, color: color, tag: tag))
        }

        // Underline
        let underline = NSMenuItem(
            title: "Underline".localized,
            action: #selector(underlineSelection(_:)),
            keyEquivalent: ""
        )
        underline.image = NSImage(
            systemSymbolName: "underline",
            accessibilityDescription: nil
        )
        underline.target = self
        items.append(underline)
        items.append(.separator())

        return items
    }

    private func makeColorItem(title: String, color: NSColor, tag: Int)
        -> NSMenuItem
    {
        let item = NSMenuItem(
            title: title,
            action: #selector(highlightSelection(_:)),
            keyEquivalent: ""
        )
        item.image = NSImage.coloredCircle(color: color)
        item.tag = tag
        item.target = self
        return item
    }

    var isRtl: Bool {
        superview?.userInterfaceLayoutDirection == .rightToLeft
    }

    lazy var quoteImage: NSImage? = {
        isRtl
            ? .init(
                systemSymbolName: "quote.opening",
                accessibilityDescription: nil
            )
            : NSImage(
                systemSymbolName: "quote.closing",
                accessibilityDescription: nil
            )
    }()

    private func buildNoteItem(_ event: NSEvent, filtered: [NSMenuItem]) -> (
        [NSMenuItem]
    ) {
        let noteItem = NSMenuItem(
            title: "Add Note".localized,
            action: #selector(annotateSelection(_:)),
            keyEquivalent: ""
        )
        noteItem.image = quoteImage
        noteItem.target = self
        var extraItems: [NSMenuItem] = []
        guard let bkId = bkId, let contentId = contentId else {
            return (extraItems)
        }
        let pointInView = convert(event.locationInWindow, from: nil)

        // Check di lokasi klik dulu
        if let charIndex = characterIndexForPoint(pointInView),
            let existing = annotationCoordinator.findAnnotation(
                at: charIndex,
                bkId: bkId,
                contentId: contentId,
                showHarakat: state.showHarakat
            )
        {
            if let note = textStorage?.attribute(
                NSAttributedString.Key("annotationID"),
                at: charIndex,
                effectiveRange: nil
            ) as? Int64 {
                extraItems.append(
                    buildEditNoteItem(
                        noteId: note,
                        charIndex: charIndex,
                        annotation: existing
                    )
                )
            } else {
                extraItems.append(noteItem)
            }
            extraItems.append(buildDeleteItem(existing))
        } else {
            // Jika tidak ada di klik, cek selection dengan logic yang lebih baik
            let sel = self.selectedRange()
            if sel.length > 0,
                let existing = annotationCoordinator.findBestAnnotation(
                    overlapping: sel,
                    bkId: bkId,
                    contentId: contentId,
                    showHarakat: state.showHarakat
                )
            {
                if let note = textStorage?.attribute(
                    NSAttributedString.Key("annotationID"),
                    at: sel.location,
                    effectiveRange: nil
                ) as? Int64 {
                    extraItems.append(
                        buildEditNoteItem(
                            noteId: note,
                            charIndex: sel.location,
                            annotation: existing
                        )
                    )
                }
                extraItems.append(buildDeleteItem(existing))
            } else {
                extraItems.append(noteItem)
            }
        }

        extraItems.append(.separator())
        let allowedKeywords = [
            "Copy", "Salin", "نسخ",
            "Look", "Cari", "بحث",
            "Translate", "Terjemah", "ترجمة",
        ]

        // Copy/Look Up/Translate
        filtered.forEach { item in
            if allowedKeywords.contains(where: {
                item.title.localizedStandardContains($0)
            }) {
                extraItems.append(item)
            }
        }
        return extraItems
    }

    private func buildEditNoteItem(
        noteId: Int64,
        charIndex: Int,
        annotation: Annotation
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: "Edit Note".localized,
            action: #selector(showNoteFromMenu(_:)),
            keyEquivalent: ""
        )
        item.image = NSImage(
            systemSymbolName: "quote.bubble",
            accessibilityDescription: ""
        )
        item.representedObject = (noteId, charIndex, annotation)
        item.target = self
        return item
    }

    private func buildDeleteItem(_ annotation: Annotation) -> NSMenuItem {
        let title =
            annotation.note == nil
            ? "Delete Highlight".localized : "Delete Highlight & Note".localized

        let item = NSMenuItem(
            title: title,
            action: #selector(deleteAnnotationMenuItem(_:)),
            keyEquivalent: ""
        )
        item.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: nil
        )
        item.representedObject = annotation.id as Any
        item.target = self

        return item
    }

    private func addItemsToMenu(
        _ menu: NSMenu,
        groupA: [NSMenuItem],
        editItems: [NSMenuItem],
        filtered: [NSMenuItem]
    ) {
        // Add highlight group
        groupA.forEach { menu.addItem($0) }

        // Add edit note if exists
        if !editItems.isEmpty {
            editItems.forEach { menu.addItem($0) }
        }

        menu.addItem(.separator())

        // Find and add share item
        if let shareItem = filtered.first(where: {
            $0.title.localizedStandardContains("Share")
        }) {
            menu.addItem(.separator())
            menu.addItem(shareItem)
            menu.addItem(.separator())
        }

        // Add remaining items
        let remaining = filtered.filter { item in
            ![
                "Share", "Copy", "Salin", "نسخ",
                "Look", "Cari", "بحث",
                "Translate", "Terjemah", "ترجمة",
            ].contains(where: { item.title.localizedStandardContains($0) })
        }

        if !remaining.isEmpty {
            menu.addItem(.separator())
            remaining.forEach { menu.addItem($0) }
        }
    }

    private func characterIndexForPoint(_ point: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        // Convert point ke koordinat textView (sudah dilakukan di caller)
        // Hit glyph index dari point
        let containerOrigin = textContainerOrigin
        let pointInTextContainer = NSPoint(
            x: point.x - containerOrigin.x,
            y: point.y - containerOrigin.y
        )
        let glyphIndex = lm.glyphIndex(for: pointInTextContainer, in: tc)
        let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
        return charIndex
    }

    @objc private func deleteAnnotationMenuItem(_ sender: NSMenuItem) {
        guard let idAny = sender.representedObject else { return }
        // id mungkin Optional<Int64> atau Int64
        let id: Int64?
        if let i = idAny as? Int64 {
            id = i
        } else if let i = idAny as? Int {
            id = Int64(i)
        } else {
            id = nil
        }

        guard let annId = id,
            let ann = AnnotationManager.shared.loadAnnotationById(annId)
        else { return }

        // Hapus dari manager / database
        try? AnnotationManager.shared.deleteAnnotation(id: annId)

        // Update UI: hapus atribut annotation dari textStorage dan reapply annotations
        if let ts = textStorage {
            ts.beginEditing()

            let range = state.showHarakat ? ann.rangeDiacritics : ann.range
            removeAttributesForRange(range, in: ts)

            ts.endEditing()

            setSelectedRange(NSRange(location: NSNotFound, length: 0))
        }
    }

    @IBAction func highlightSelection(_ sender: NSMenuItem) {
        let sel = selectedRange()
        guard sel.length > 0,
            let bkId = bkId,
            let contentId = contentId,
            let page = page,
            let part = part
        else { return }

        let color: NSColor
        switch sender.tag {
        case 1: color = .yellow
        case 2: color = .green
        case 3: color = .blue
        case 4: color = .systemPink
        case 5: color = .purple
        default: color = .yellow
        }

        do {
            let annotation = try annotationCoordinator.saveHighlight(
                text: string,
                range: sel,
                color: color,
                bkId: bkId,
                contentId: contentId,
                page: page,
                part: part,
                diacriticsText: diacriticsIbarot,
                showHarakat: state.showHarakat
            )

            // Apply to UI
            if state.clickableAnnotation {
                refreshAnnotations()
            } else if let ts = textStorage {
                renderer.applyAnnotations(
                    [annotation],
                    to: ts,
                    showHarakat: state.showHarakat
                )
            }

            setSelectedRange(NSRange(location: NSNotFound, length: 0))
        } catch {
            #if DEBUG
                print("Failed to save highlight: \(error)")
            #endif
        }
    }

    @IBAction func underlineSelection(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length > 0,
            let bkId, let contentId,
            let page, let part
        else { return }

        do {
            let annotation = try annotationCoordinator.saveHighlight(
                text: string,
                range: sel,
                color: .black,
                bkId: bkId,
                contentId: contentId,
                page: page,
                part: part,
                diacriticsText: diacriticsIbarot,
                showHarakat: state.showHarakat,
                mode: .underline
            )

            // Apply to UI
            if state.clickableAnnotation {
                refreshAnnotations()
            } else if let ts = textStorage {
                renderer.applyAnnotations(
                    [annotation],
                    to: ts,
                    showHarakat: state.showHarakat
                )
            }

            setSelectedRange(NSRange(location: NSNotFound, length: 0))
        } catch {
            #if DEBUG
                print("Failed to save highlight: \(error)")
            #endif
        }
    }

    @IBAction func annotateSelection(_ sender: Any?) {
        let sel = self.selectedRange()
        guard sel.length > 0,
            let bkId, let contentId,
            let page, let part
        else { return }

        // Cek dulu apakah ada annotation yang sudah ada di cache untuk bkId/contentId
        // dan yang overlap dengan selection saat ini.
        if let existing = annotationCoordinator.findBestAnnotation(
            overlapping: sel,
            bkId: bkId,
            contentId: contentId,
            showHarakat: state.showHarakat
        ) {
            // Jika ada, buka editor untuk annotation yang sudah ada
            let middleIndex = sel.location + (sel.length / 2)
            presentAnnotationEditorForNewAnnotation(
                existing,
                atCharIndex: middleIndex
            )
            return
        }

        let calculator = ArabicRangeCalculator()

        // Tidak ada annotation existing -> buat baru
        let middleIndex = sel.location + (sel.length / 2)
        let ns = self.string as NSString
        let selectedText = ns.substring(with: sel)
        let (rangeWithDiacritics, rangeWithoutDiacritics) =
            calculator.calculateRanges(
                for: sel,
                in: string,
                selectedText: selectedText,
                diacriticsText: diacriticsIbarot,
                showHarakat: state.showHarakat
            )

        let ann = Annotation(
            id: nil,
            bkId: bkId,
            contentId: contentId,
            range: rangeWithoutDiacritics,
            rangeDiacritics: rangeWithDiacritics,
            colorHex: "#FFEA00",
            type: .highlight,
            note: nil,
            createdAt: Int64(Date().timeIntervalSince1970),
            context: ns.substring(with: sel),
            page: page,
            part: part
        )

        presentAnnotationEditorForNewAnnotation(ann, atCharIndex: middleIndex)
    }

    func refreshAnnotations() {
        guard let bkId = bkId, let contentId = contentId, let ts = textStorage else { return }

        // 1. Ambil data terbaru
        let anns = AnnotationManager.shared.loadAnnotations(
            bkId: bkId,
            contentId: contentId
        )

        ts.beginEditing()

        // ==========================================
        // LANGKAH PENTING: BERSIHKAN ATRIBUT LAMA 🧹
        // ==========================================
        let fullRange = NSRange(location: 0, length: ts.length)

        // Hapus Background (Highlight)
        ts.removeAttribute(.backgroundColor, range: fullRange)

        // Hapus Underline
        ts.removeAttribute(.underlineStyle, range: fullRange)

        // Hapus Link (Agar area klik hilang untuk yang sudah dihapus)
        ts.removeAttribute(.link, range: fullRange)

        // Hapus ID Anotasi custom Anda
        ts.removeAttribute(NSAttributedString.Key("annotationID"), range: fullRange)

        // ==========================================

        // 2. Apply yang baru (Fresh)
        renderer.applyAnnotations(
            anns,
            to: ts,
            showHarakat: state.showHarakat
        )

        ts.endEditing()
    }

    func presentAnnotationEditorForNewAnnotation(
        _ annotation: Annotation,
        atCharIndex charIndex: Int
    ) {
        let editor = AnnotationEditorVC()
        editor.annotation = annotation
        editor.delegate = self

        let pop = NSPopover()
        pop.contentViewController = editor
        pop.behavior = .transient  // atau .transient sesuai preferensi

        // Hit lokasi glyph rect untuk charIndex (safety checks)
        let anchorView = enclosingScrollView?.contentView ?? self
        if let layoutManager = layoutManager,
            let textContainer = textContainer
        {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            let containerOrigin = textContainerOrigin
            let screenRect = NSRect(
                x: glyphRect.origin.x + containerOrigin.x,
                y: glyphRect.origin.y + containerOrigin.y,
                width: glyphRect.width,
                height: glyphRect.height
            )
            pop.show(
                relativeTo: screenRect,
                of: anchorView,
                preferredEdge: .maxY
            )
        } else {
            pop.show(relativeTo: bounds, of: anchorView, preferredEdge: .maxY)
        }
    }

    @objc private func showNoteFromMenu(_ sender: NSMenuItem) {
        if let (_, charIndex, ann) = sender.representedObject
            as? (Int64, Int, Annotation)
        {
            presentAnnotationEditor(ann, atCharIndex: charIndex, in: self)
        }
    }
}

struct CleanedTextResult {
    let text: String
    let coloredRanges: [NSRange]  // Range dalam string 'text'
}
