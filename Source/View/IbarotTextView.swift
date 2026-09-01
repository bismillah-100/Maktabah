//
//  IbarotTextView.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

import Cocoa

class IbarotTextView: NSTextView {
    let state = TextViewState.shared
    let renderer = ArabicTextRenderer() // ← NEW
    var viewModel: ReaderViewModel?

    var onAddAnnotation: ((NSRange, NSColor, AnnotationMode, String) -> Void)?
    var onUpdateAnnotation: ((Annotation) -> Void)?
    var onDeleteAnnotation: ((Int64) -> Void)?

    var annotations: [Annotation] {
        viewModel?.currentAnnotations ?? []
    }

    var diacriticsText: String? {
        viewModel?.diacriticsText ?? ""
    }

    private(set) var currentRenderResult: ArabicRenderResult?
    private(set) var footnoteRanges: [NSRange] = []
    private var annotationClickSetting: NSObjectProtocol?
    private let taskQueue = SerialTaskQueue()

    override var string: String {
        didSet {
            currentRenderResult = nil
            let attributedString = NSMutableAttributedString(
                string: string,
                attributes: state.defaultAttributes
            )
            textStorage?.setAttributedString(attributedString)
        }
    }

    var bkId: Int? {
        viewModel?.currentBook?.id
    }

    var contentId: Int? {
        viewModel?.currentContentId
    }

    var page: Int? {
        viewModel?.currentPage
    }

    var part: Int? {
        viewModel?.currentPart
    }

    lazy var colorMenuView: AnnotationColorMenuView = {
        let view = AnnotationColorMenuView(target: self)
        let frame = view.frame
        let newFrame = NSRect(x: 16, y: frame.origin.y,
                              width: frame.width,
                              height: frame.height)
        view.frame = newFrame
        view.colorAction = #selector(menuDidSelectColor(_:))
        view.underlineAction = #selector(menuDidSelectUnderline(_:))
        return view
    }()

    private lazy var colorMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.view = colorMenuView
        return item
    }()

    func contentKey() -> ContentKey? {
        guard let b = bkId, let c = contentId else { return nil }
        return ContentKey(bkId: b, contentId: c)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        setupTextView()

        NotificationCenter.default.addObserver(
            forName: .annotationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleIncrementalAnnotationChange(notification)
        }

        NotificationCenter.default.addObserver(
            forName: .annotationTreeDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAnnotations()
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
                let charRange = NSRange(location: charIndex, length: 1)
                presentAnnotationEditor(ann, displayedRange: charRange)
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
        if let annotationClickSetting {
            NotificationCenter.default.removeObserver(annotationClickSetting)
        }
        annotationClickSetting = nil
    }

    private func setupTextView() {
        // Setup untuk teks Arab
        textLayoutManager?.delegate = self
        alignment = .natural // RTL untuk Arab
        isEditable = false
        isAutomaticLinkDetectionEnabled = false
        linkTextAttributes = [:]
        displaysLinkToolTips = false
        textContainerInset = NSSize(width: 8, height: 4)
        wantsLayer = true
        enclosingScrollView?.autohidesScrollers = true
        enclosingScrollView?.hasVerticalScroller = true
        enclosingScrollView?.hasHorizontalScroller = false

        linkTextAttributes = [
            .cursor: NSCursor.pointingHand,
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

        if enable {
            guard !annotations.isEmpty || !annotationRanges.isEmpty else {
                window?.invalidateCursorRects(for: self)
                return
            }
            refreshAnnotations()
        } else {
            guard !annotationRanges.isEmpty else {
                window?.invalidateCursorRects(for: self)
                return
            }
            ts.beginEditing()
            for annotation in annotationRanges {
                ts.removeAttribute(.link, range: annotation.range)
            }
            ts.endEditing()
        }

        textLayoutManager?.ensureFullDocumentLayout()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func loadText(_ text: String) {
        currentRenderResult = nil
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: state.defaultAttributes
        )
        textStorage?.setAttributedString(attributedString)
    }

    func updateLineHeight() {
        guard let ts = textStorage, let scrollView = enclosingScrollView else { return }
        let visibleRect = scrollView.documentVisibleRect
        let totalHeight = scrollView.documentView?.frame.size.height ?? 0
        let scrollPercentage = totalHeight > 0 ? (visibleRect.origin.y / totalHeight) : 0

        renderer.updateLineHeight(in: ts) // ← simpel!

        textLayoutManager?.ensureFullDocumentLayout()

        let newTotalHeight = scrollView.documentView?.frame.size.height ?? 0
        let targetY = scrollPercentage * newTotalHeight
        scrollView.contentView.scroll(to: NSPoint(x: visibleRect.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager else { return }
        let newFont = fontManager.convert(state.currentFont)
        let fontName = newFont.fontName
        state.setFont(fontName)
    }

    /// Fungsi yang diperbarui: menerima data dari viewModel
    func displayAuthor(_ attributedString: AttributedString) {
        currentRenderResult = nil
        do {
            let ns = try NSAttributedString(attributedString, including: \.appKit)
            textStorage?.setAttributedString(ns)
        } catch {
            print(
                "error converting NSAttributedString on displayAuthor: ",
                error.localizedDescription
            )
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        guard contentKey() != nil, selectedRange().length > 0 else {
            return menu
        }

        let filtered = filterMenuItems(menu)
        let groupA = buildHighlightGroup()
        let editItems = buildNoteItem(event, filtered: filtered)

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
            #selector(NSTextView.pasteAsPlainText(_:)),
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

        let dict = "character.book.closed"
        let char = "character.bubble"

        let iconMap: [(String, String)] = [
            ("Look", dict),
            ("Cari", dict),
            ("بحث", dict),
            ("Translate", char),
            ("Terjemah", char),
            ("ترجمة", char),
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

    var isRtl: Bool {
        superview?.userInterfaceLayoutDirection == .rightToLeft
    }

    lazy var quoteImage: NSImage? = isRtl
        ? .init(
            systemSymbolName: "quote.opening",
            accessibilityDescription: nil
        )
        : NSImage(
            systemSymbolName: "quote.closing",
            accessibilityDescription: nil
        )

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
        guard bkId != nil, contentId != nil else {
            return extraItems
        }
        let pointInView = convert(event.locationInWindow, from: nil)

        if let charIndex = characterIndexForPoint(pointInView),
           let noteId = textStorage?.attribute(NSAttributedString.Key("annotationID"), at: charIndex, effectiveRange: nil) as? Int64,
           let existing = annotations.first(where: { $0.id == noteId })
        {
            extraItems.append(buildEditNoteItem(noteId: noteId, charIndex: charIndex, annotation: existing))
            extraItems.append(buildDeleteItem(existing))
        } else {
            // Jika tidak ada di klik, cek selection dengan logic yang lebih baik
            let displayedSelection = selectedRange()
            let selection = sourceRange(forDisplayedRange: displayedSelection)

            if selection.length > 0 {
                let overlapping = annotations.first {
                    let r = state.showHarakat ? $0.rangeDiacritics : $0.range
                    return NSIntersectionRange(r, selection).length > 0
                }

                if let existing = overlapping {
                    if let noteId = existing.id {
                        extraItems.append(buildEditNoteItem(noteId: noteId, charIndex: displayedSelection.location, annotation: existing))
                    }
                    extraItems.append(buildDeleteItem(existing))
                } else {
                    extraItems.append(noteItem)
                }
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
        for item in filtered {
            if allowedKeywords.contains(where: {
                item.title.localizedStandardContains($0)
            }) {
                extraItems.append(item)
                if item.action == #selector(NSText.copy(_:)) {
                    extraItems.append(.separator())
                    extraItems.append(buildCopyWithReferenceItem())
                }
            }
        }
        return extraItems
    }

    private func buildCopyWithReferenceItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: .copyWithReference),
            action: #selector(IbarotTextVC.copyWith(_:)),
            keyEquivalent: ""
        )
        item.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: nil
        )
        item.target = nil
        return item
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
            $0.title.localizedStandardContains("Share") ||
                $0.title.localizedStandardContains("Bagikan") ||
                $0.title.localizedStandardContains("مشاركة")
        }) {
            shareItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
            menu.addItem(.separator())
            menu.addItem(shareItem)
            menu.addItem(.separator())
        }

        // Add remaining items
        let remaining = filtered.filter { item in
            ![
                "Share", "Bagikan", "مشاركة",
                "Copy", "Salin", "نسخ",
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
        guard let tlm = textLayoutManager else { return nil }

        let containerOrigin = textContainerOrigin
        let pointInTextContainer = NSPoint(
            x: point.x - containerOrigin.x,
            y: point.y - containerOrigin.y
        )

        guard let fragment = tlm.textLayoutFragment(for: pointInTextContainer) else { return nil }
        guard let textElement = fragment.textElement,
              let elementRange = textElement.elementRange else { return nil }

        let startLocation = tlm.documentRange.location
        let rangeStartOffset = tlm.offset(from: startLocation, to: elementRange.location)

        let fragmentFrame = fragment.layoutFragmentFrame
        let pointInFragment = CGPoint(
            x: pointInTextContainer.x - fragmentFrame.minX,
            y: pointInTextContainer.y - fragmentFrame.minY
        )

        for lineFragment in fragment.textLineFragments {
            let lineFrame = lineFragment.typographicBounds

            if pointInFragment.y >= lineFrame.minY, pointInFragment.y <= lineFrame.maxY {
                let pointInLine = CGPoint(
                    x: pointInFragment.x - lineFrame.minX,
                    y: pointInFragment.y - lineFrame.minY
                )

                let relativeCharIndex = lineFragment.characterIndex(for: pointInLine)
                return rangeStartOffset + relativeCharIndex
            }
        }

        return rangeStartOffset
    }

    @objc private func deleteAnnotationMenuItem(_ sender: NSMenuItem) {
        guard let idAny = sender.representedObject else { return }
        let id: Int64? = if let i = idAny as? Int64 {
            i
        } else if let i = idAny as? Int {
            Int64(i)
        } else {
            nil
        }

        guard let annId = id else { return }

        onDeleteAnnotation?(annId)
    }

    // MARK: - applyHighlightWithColor

    private func applyAnnotations(
        in selectedRange: NSRange,
        with color: NSColor,
        mode: AnnotationMode
    ) throws {
        defer {
            if selectedRange.length > 0 {
                setSelectedRange(NSRange(location: selectedRange.location, length: 0))
            }
            colorMenuView.reloadColors()
        }

        guard selectedRange.length > 0 else { return }

        let sourceSelection = sourceRange(forDisplayedRange: selectedRange)

        let overlapping = annotations.first {
            let r = state.showHarakat ? $0.rangeDiacritics : $0.range
            return NSIntersectionRange(r, sourceSelection).length > 0
        }

        if let existing = overlapping {
            let updated = Annotation(
                id: existing.id,
                bkId: existing.bkId,
                contentId: existing.contentId,
                range: existing.range,
                rangeDiacritics: existing.rangeDiacritics,
                colorHex: color.hexString(),
                type: mode,
                note: existing.note,
                createdAt: existing.createdAt,
                context: existing.context,
                page: existing.page,
                part: existing.part,
                pageArb: existing.pageArb,
                partArb: existing.partArb,
                tags: existing.tags
            )
            onUpdateAnnotation?(updated)
        } else {
            onAddAnnotation?(sourceSelection, color, mode, sourceTextForAnnotations())
        }
    }

    /// Highlight seleksi dengan warna dinamis.
    /// Setelah berhasil disimpan, warna di-push ke urutan pertama UserDefaults.
    func applyHighlightWithColor(_ color: NSColor) {
        let sel = selectedRange()
        do {
            try applyAnnotations(in: sel, with: color, mode: .highlight)
        } catch {
            #if DEBUG
            print("Failed to save or update highlight: \(error)")
            #endif
        }
    }

    @IBAction func underlineSelection(_ sender: Any?) {
        let sel = selectedRange()

        do {
            try applyAnnotations(in: sel, with: .black, mode: .underline)
        } catch {
            #if DEBUG
            print("Failed to save highlight: \(error)")
            #endif
        }
    }

    @IBAction func annotateSelection(_ sender: Any?) {
        let displayedSelection = selectedRange()
        let selection = sourceRange(forDisplayedRange: displayedSelection)
        guard selection.length > 0,
              let bkId, let contentId,
              let page, let part
        else { return }

        let overlapping = annotations.first {
            let r = state.showHarakat ? $0.rangeDiacritics : $0.range
            return NSIntersectionRange(r, selection).length > 0
        }

        if let existing = overlapping {
            presentAnnotationEditor(existing, displayedRange: displayedSelection)
            return
        }

        let calculator = ArabicRangeCalculator()

        let ns = sourceTextForAnnotations() as NSString
        let selectedText = ns.substring(with: selection)
        let (rangeWithDiacritics, rangeWithoutDiacritics) =
            calculator.calculateRanges(
                for: selection,
                in: sourceTextForAnnotations(),
                selectedText: selectedText,
                diacriticsText: diacriticsText,
                showHarakat: state.showHarakat
            )

        let ann = Annotation(
            id: nil,
            bkId: bkId,
            contentId: contentId,
            range: rangeWithoutDiacritics,
            rangeDiacritics: rangeWithDiacritics,
            colorHex: state.lastUsedColor(),
            type: .highlight,
            note: nil,
            createdAt: Int64(Date().timeIntervalSince1970),
            context: ns.substring(with: selection),
            page: page,
            part: part,
            tags: []
        )

        presentAnnotationEditor(ann, displayedRange: displayedSelection)
    }

    func refreshAnnotations() {
        guard let ts = textStorage else { return }
        let fullRange = NSRange(location: 0, length: ts.length)
        var rangesToClear: [NSRange] = []

        ts.enumerateAttribute(NSAttributedString.Key("annotationID"), in: fullRange, options: []) { value, range, _ in
            if value != nil {
                rangesToClear.append(range)
            }
        }

        guard !rangesToClear.isEmpty || !annotations.isEmpty else { return }

        ts.beginEditing()
        for range in rangesToClear {
            ts.removeAttribute(.backgroundColor, range: range)
            ts.removeAttribute(.underlineStyle, range: range)
            ts.removeAttribute(.link, range: range)
            ts.removeAttribute(NSAttributedString.Key("annotationID"), range: range)
        }

        renderer.applyAnnotations(
            annotations,
            to: ts,
            showHarakat: state.showHarakat,
            replacementEvents: currentRenderResult?.replacementEvents ?? []
        )
        ts.endEditing()

        textLayoutManager?.ensureFullDocumentLayout()
        needsDisplay = true
    }

    func presentAnnotationEditor(
        _ annotation: Annotation,
        displayedRange: NSRange
    ) {
        let editor = AnnotationEditorVC()
        editor.annotation = annotation

        let pop = NSPopover()
        pop.contentViewController = editor
        pop.behavior = .transient

        // firstRect(forCharacterRange:) returns a rect in screen coordinates —
        // the same API used by the system for autocomplete/tooltip, guaranteed precision.
        var actualRange = displayedRange
        let rectInWindow = firstRect(forCharacterRange: displayedRange, actualRange: &actualRange)
        let anchor: NSRect
        if let window {
            let rectInView = convert(window.convertFromScreen(rectInWindow), from: nil)
            anchor = rectInView == .zero ? bounds : rectInView
        } else {
            anchor = bounds
        }

        pop.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
    }

    @objc private func showNoteFromMenu(_ sender: NSMenuItem) {
        if let (_, charIndex, ann) = sender.representedObject
            as? (Int64, Int, Annotation)
        {
            let charRange = NSRange(location: charIndex, length: 1)
            presentAnnotationEditor(ann, displayedRange: charRange)
        }
    }

    func displayedRange(for annotation: Annotation) -> NSRange {
        let range = state.showHarakat ? annotation.rangeDiacritics : annotation.range
        return displayedRange(forStoredRange: range)
    }

    private func displayedRange(forStoredRange range: NSRange) -> NSRange {
        currentRenderResult?.remapDisplayedRange(range) ?? range
    }

    private func sourceRange(forDisplayedRange range: NSRange) -> NSRange {
        currentRenderResult?.remapSourceRange(range) ?? range
    }

    private func sourceOffset(forDisplayedOffset offset: Int) -> Int {
        currentRenderResult?.sourceOffset(forDisplayedOffset: offset, affinity: .leading) ?? offset
    }

    private func sourceTextForAnnotations() -> String {
        currentRenderResult?.sourceText ?? string
    }

    private func handleIncrementalAnnotationChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeTypeRaw = userInfo[AnnotationNotificationKeys.changeType] as? String,
              let changeType = AnnotationChangeType(rawValue: changeTypeRaw),
              let ts = textStorage
        else { return }

        let annotation = userInfo[AnnotationNotificationKeys.annotation] as? Annotation
        let annotationId = userInfo[AnnotationNotificationKeys.annotationId] as? Int64

        let isCurrentPageAnnotation = (annotation?.bkId == bkId && annotation?.contentId == contentId)

        switch changeType {
        case .added:
            guard isCurrentPageAnnotation, let ann = annotation else { return }
            ts.beginEditing()
            renderer.applyAnnotations(
                [ann],
                to: ts,
                showHarakat: state.showHarakat,
                replacementEvents: currentRenderResult?.replacementEvents ?? []
            )
            ts.endEditing()
        case .updated:
            guard isCurrentPageAnnotation, let ann = annotation, let id = ann.id else { return }
            ts.beginEditing()
            performRemoveAttributes(forAnnotationId: id, in: ts)
            renderer.applyAnnotations(
                [ann],
                to: ts,
                showHarakat: state.showHarakat,
                replacementEvents: currentRenderResult?.replacementEvents ?? []
            )
            ts.endEditing()
        case .deleted:
            guard let id = annotationId else { return }
            ts.beginEditing()
            performRemoveAttributes(forAnnotationId: id, in: ts)
            ts.endEditing()
        }

        needsDisplay = true

        // UI Cleanup
        let sel = selectedRange()
        if sel.length > 0 {
            setSelectedRange(NSRange(location: sel.location, length: 0))
        }
        colorMenuView.reloadColors()
    }

    private func performRemoveAttributes(forAnnotationId id: Int64, in ts: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: ts.length)
        var rangesToClear: [NSRange] = []

        ts.enumerateAttribute(
            NSAttributedString.Key("annotationID"),
            in: fullRange,
            options: []
        ) { value, range, _ in
            if let attrId = value as? Int64, attrId == id {
                rangesToClear.append(range)
            }
        }

        guard !rangesToClear.isEmpty else { return }

        for range in rangesToClear {
            ts.removeAttribute(.backgroundColor, range: range)
            ts.removeAttribute(.underlineStyle, range: range)
            ts.removeAttribute(.link, range: range)
            ts.removeAttribute(NSAttributedString.Key("annotationID"), range: range)
            ts.removeAttribute(NSAttributedString.Key("annotationNote"), range: range)
            ts.removeAttribute(NSAttributedString.Key("underlineColor"), range: range)
        }
    }
}

extension IbarotTextView: TextViewRenderable {
    func loadIbarotText(
        _ text: String,
        content: BookContent? = nil,
        color: NSColor?,
        isMultiLanguage: Bool?,
        isImported: Bool?,
        keepScrollPosition: Bool?
    ) {
        guard let scrollView = enclosingScrollView else { return }
        ReusableFunc.showProgressWindow(scrollView.contentView)
        taskQueue.cancelAll()

        var scrollPercentage: CGFloat = 0
        var visibleRect: NSRect = .zero
        if keepScrollPosition == true {
            visibleRect = scrollView.documentVisibleRect
            let totalHeight = scrollView.documentView?.frame.size.height ?? 0
            scrollPercentage = totalHeight > 0 ? (visibleRect.origin.y / totalHeight) : 0
        }

        let targetBkId = content != nil ? bkId : (viewModel?.currentBook?.id ?? bkId)
        let targetContentId = content?.id ?? (viewModel?.currentContentId ?? contentId)

        taskQueue.enqueue { [weak self] in
            guard let self, !Task.isCancelled else { return }

            let renderResult = await renderer.render(
                bookId: targetBkId,
                contentId: targetContentId,
                text: text,
                highlightColor: color ?? .header,
                showHarakat: state.showHarakat,
                isMultiLanguage: isMultiLanguage ?? false,
                isImported: isImported ?? false
            )

            // render() sendiri CPU-bound & nggak preemptible, tapi minimal
            // hasil stale nggak akan dipakai kalau sudah kadung di-cancel
            if Task.isCancelled { return }

            await MainActor.run { [weak self] in
                defer { ReusableFunc.closeProgressWindow(scrollView.contentView) }
                guard let self, !Task.isCancelled,
                      let textStorage, let textLayoutManager
                else { return }

                currentRenderResult = renderResult
                footnoteRanges = renderResult.footnoteRanges
                let finalAttributedString = NSMutableAttributedString(
                    attributedString: renderResult.attributedString
                )

                textStorage.beginEditing()
                textStorage.setAttributedString(finalAttributedString)
                renderer.applyAnnotations(
                    annotations, to: textStorage,
                    showHarakat: state.showHarakat,
                    replacementEvents: renderResult.replacementEvents
                )
                textStorage.endEditing()

                textLayoutManager.ensureFullDocumentLayout()

                if keepScrollPosition == true {
                    let newTotalHeight = scrollView.documentView?.frame.size.height ?? 0
                    let targetY = scrollPercentage * newTotalHeight
                    scrollView.contentView.scroll(to: NSPoint(x: visibleRect.origin.x, y: targetY))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                } else {
                    scrollToBeginningOfDocument(nil)
                }
            }
        }
    }

    @MainActor
    func highlightAndScrollToAnns(_ ann: Annotation) async {
        taskQueue.enqueue { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let r = displayedRange(for: ann)
                textLayoutManager?.ensureFullDocumentLayout()
                needsLayout = true
                scrollRangeToVisible(r)
                enclosingScrollView?.contentView.layoutSubtreeIfNeeded()
                layoutSubtreeIfNeeded()
                showFindIndicator(for: r)
            }
        }
    }

    @MainActor
    func highlightAndScrollToText(_ searchText: String, mode: SearchMode?, nearDistance: Int) async {
        taskQueue.enqueue { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let ranges = textStorage?.highlightSearchText(
                    searchText: searchText,
                    mode: mode,
                    baseColor: .highlightText,
                    nearDistance: nearDistance
                ) ?? []

                guard let firstRange = ranges.first else { return }

                textLayoutManager?.ensureFullDocumentLayout()
                needsLayout = true
                scrollRangeToVisible(firstRange)
                enclosingScrollView?.contentView.layoutSubtreeIfNeeded()
                layoutSubtreeIfNeeded()
                showFindIndicator(for: firstRange)
            }
        }
    }

    func scrollTo(_ scrollPos: CGPoint) async {
        taskQueue.enqueue { [weak self] in
            guard let self, let scrollView = await enclosingScrollView else { return }
            await scrollView.contentView.scroll(to: NSPoint(x: .zero, y: scrollPos.y))
            await scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

extension IbarotTextView {
    // MARK: - buildHighlightGroup (pengganti)

    /// Mengembalikan satu NSMenuItem dengan view horizontal (warna + underline).
    func buildHighlightGroup() -> [NSMenuItem] {
        [colorMenuItem, .separator()]
    }

    // MARK: - Actions dari AnnotationColorMenuView

    /// Dipanggil saat tombol warna ditekan di menu.
    /// sender.tag = index warna di UserDefaults.recentHighlightColors
    @objc func menuDidSelectColor(_ sender: NSButton) {
        // Tutup menu dulu
        dismissMenu(sender)

        let colors = UserDefaults.standard.recentHighlightColors
        guard sender.tag < colors.count else { return }
        let color = colors[sender.tag]

        applyHighlightWithColor(color)
    }

    /// Dipanggil saat tombol underline ditekan di menu.
    @objc func menuDidSelectUnderline(_ sender: NSButton) {
        dismissMenu(sender)
        let colors = UserDefaults.standard.recentHighlightColors
        guard sender.tag < colors.count else { return }

        underlineSelection(sender)
    }

    private func dismissMenu(_ sender: NSView) {
        var current: NSView? = sender
        while let superview = current?.superview {
            if let menuItem = current?.enclosingMenuItem,
               let menu = menuItem.menu
            {
                menu.cancelTracking() // Tutup paksa di sini
                break
            }
            current = superview
        }
    }
}
