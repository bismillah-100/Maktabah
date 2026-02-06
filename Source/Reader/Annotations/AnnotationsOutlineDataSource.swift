//
//  AnnotationsOutlineDataSource.swift
//  maktab
//
//  Created by MacBook on 15/12/25.
//

import Cocoa

class AnnotationOutlineDataSource: NSObject, NSOutlineViewDataSource {
    weak var delegate: AnnotationDelegate?
    weak var outlineView: NSOutlineView?

    let paragraphStyle = NSMutableParagraphStyle()

    private(set) var filteredRootNode: AnnotationNode?

    private var currentRootNode: AnnotationNode? {
        return filteredRootNode ?? AnnotationManager.shared.rootNode
    }

    private var treeObserver: NSObjectProtocol?

    // Cache Formatter
    private let calendar = Calendar.current

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private lazy var relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var onSelectItem: ((Int) -> Void)?

    // 🔔 Observer untuk notification
    private var annotationObserver: NSObjectProtocol?

    // Simpan search text untuk re-apply filter setelah perubahan
    private var currentSearchText: String?

    let menu = NSMenu()

    lazy var deleteMenuItem: NSMenuItem = {
        let item = NSMenuItem()
        item.title = NSLocalizedString("Delete", comment: "")
        item.image = NSImage(
            systemSymbolName: "trash.slash",
            accessibilityDescription: ""
        )
        return item
    }()

    override init() {
        super.init()
        setupTreeObserver()
        paragraphStyle.alignment = .right
    }

    deinit {
        #if DEBUG
            print("Annotations Data Source deinit")
        #endif
        if let observer = annotationObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        if let treeObserver {
            NotificationCenter.default.removeObserver(treeObserver)
        }
    }

    // MARK: - Setup Notification Observer
    private func setupTreeObserver() {
        treeObserver = NotificationCenter.default.addObserver(
            forName: .annotationTreeDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleTreeUpdate()
        }
    }

    private func handleTreeUpdate() {
        // Re-apply filter jika ada
        if let searchText = currentSearchText, !searchText.isEmpty {
            applySearchFilter(text: searchText)
        }

        // Reload outline view
        outlineView?.reloadData()
    }

    // MARK: - Public Methods
    func reload() {
        // Trigger build tree jika belum ada
        //        if AnnotationManager.shared.rootNode == nil {
        //            AnnotationManager.shared.buildAnnotationTree()
        //        }

        AnnotationManager.shared.buildAnnotationTree()
        filteredRootNode = nil
        menu.delegate = self
        if !menu.items.contains(deleteMenuItem) {
            menu.addItem(deleteMenuItem)
        }
        outlineView?.menu = menu
    }

    // MARK: - Export RTF

    func exportToRTF(nodes: [AnnotationNode]? = nil) -> Data? {
        guard let outlineView else { return nil }

        let row = outlineView.selectedRow

        guard let item = outlineView.item(atRow: row) as? AnnotationNode else {
            return nil
        }

        let items = nodes ?? [item]
        let attr = buildAttributedString(nodes: items)

        do {
            return try attr.data(
                from: NSRange(location: 0, length: attr.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.rtf,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ]
            )
        } catch {
            print("Export RTF Gagal:", error)
            return nil
        }
    }

    private func buildAttributedString(nodes: [AnnotationNode])
        -> NSAttributedString
    {
        let result = NSMutableAttributedString()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.paragraphSpacingBefore = 4
        paragraphStyle.paragraphSpacing = 8

        for node in nodes {

            // =========================
            // HEADER BUKU / FOLDER
            // =========================
            if node.annotation == nil {
                let titleAttr = NSAttributedString(
                    string: "\(node.title)\n",
                    attributes: [
                        .font: NSFont.boldSystemFont(ofSize: 18),
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )

                result.append(titleAttr)

                if !node.children.isEmpty {
                    let childAttr = buildAttributedString(nodes: node.children)
                    result.append(childAttr)
                }
            }

            // =========================
            // ANOTASI
            // =========================
            else if let annotation = node.annotation {
                let color = NSColor(hex: annotation.colorHex) ?? .yellow

                let contextText = "\(annotation.context)\n"
                let attrContext = NSMutableAttributedString(
                    string: contextText,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 14),
                        .paragraphStyle: paragraphStyle,
                    ]
                )

                let fullRg = NSRange(location: 0, length: attrContext.length)

                if annotation.type == .highlight {
                    attrContext.addAttribute(
                        .backgroundColor,
                        value: color.withAlphaComponent(0.3),
                        range: fullRg
                    )
                } else if annotation.type == .underline {
                    attrContext.addAttribute(
                        .underlineStyle,
                        value: NSUnderlineStyle.single.rawValue,
                        range: fullRg
                    )
                    attrContext.addAttribute(
                        .underlineColor,
                        value: color,
                        range: fullRg
                    )
                }

                result.append(attrContext)

                // -------------------------
                // NOTE
                // -------------------------
                if let noteText = annotation.note {
                    let attrNote = NSAttributedString(
                        string: "حَاشِيَة: \(noteText)\n",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 13),
                            .foregroundColor: NSColor.secondaryLabelColor,
                            .paragraphStyle: paragraphStyle,
                        ]
                    )
                    result.append(attrNote)
                }

                // -------------------------
                // METADATA
                // -------------------------
                let targetDate = Date(
                    timeIntervalSince1970: TimeInterval(annotation.createdAt)
                )
                let dateString =
                    calendar.isDateInToday(targetDate)
                    ? relativeFormatter.localizedString(
                        for: targetDate,
                        relativeTo: Date()
                    )
                    : dateFormatter.string(from: targetDate)

                let metaText =
                    "الجزء: \(annotation.partArb ?? "-") • الصفحة: \(annotation.pageArb ?? "-") • \(dateString)\n"

                let attrMeta = NSAttributedString(
                    string: metaText,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                        .paragraphStyle: paragraphStyle,
                    ]
                )

                result.append(attrMeta)
                result.append(NSAttributedString(string: "\n\n\n"))
            }
        }

        return result
    }

    // MARK: - Delete Action

    @objc func deleteItem(_ sender: NSMenuItem) {
        guard let outlineView, let row = sender.representedObject as? Int else {
            return
        }

        // Ambil item dari baris tersebut
        guard let item = outlineView.item(atRow: row) as? AnnotationNode else {
            return
        }

        // =========================================================
        // KONDISI 1: ITEM ADALAH PARENT (BUKU/FOLDER)
        // Ciri: item.annotation == nil (berdasarkan struktur data Anda)
        // =========================================================
        if item.annotation == nil {
            // Opsional: Tambahkan Alert Konfirmasi di sini jika ingin lebih aman

            // 1. Loop semua children dan hapus dari Database
            // Kita gunakan reverse loop atau copy array agar aman saat iterasi
            let childrenToDelete = item.children
            let annotations: [Annotation] = Array(
                childrenToDelete.compactMap { $0.annotation }
            )

            for child in childrenToDelete {
                if let annotation = child.annotation, let id = annotation.id {
                    do {
                        try AnnotationManager.shared.deleteAnnotation(id: id)
                    } catch {
                        print("Gagal menghapus anotasi ID \(id): \(error)")
                    }
                }
            }

            // 2. Hapus Parent Item dari UI (OutlineView)
            // Parent dari item ini (biasanya nil jika ini level teratas/root)
            // let parentGroup = outlineView.parent(forItem: item)
            let index = outlineView.childIndex(forItem: item)

            if index != -1 {
                outlineView.removeItems(
                    at: IndexSet(integer: index),
                    inParent: nil,  // nil tidak masalah untuk top-level item
                    withAnimation: .slideUp
                )
            }

            // 3. Beritahu sistem bahwa tree berubah drastis
            NotificationCenter.default.post(
                name: .annotationDidDeleteFromOutline,
                object: nil,
                userInfo: ["annotations": annotations]
            )
        }

        // =========================================================
        // KONDISI 2: ITEM ADALAH CHILD (SINGLE ANNOTATION)
        // =========================================================
        else {
            // Pastikan punya parent (karena child pasti di dalam folder buku)
            guard let parent = outlineView.parent(forItem: item) else { return }

            guard let annotation = item.annotation,
                let id = annotation.id
            else {
                #if DEBUG
                    print("error node, annotation, id.")
                #endif
                return
            }

            let childIndex = outlineView.childIndex(forItem: item)

            do {
                // Hapus dari Database
                try AnnotationManager.shared.deleteAnnotation(id: id)

                // Hapus dari UI
                outlineView.removeItems(
                    at: IndexSet(integer: childIndex),
                    inParent: parent,
                    withAnimation: .slideUp
                )

                NotificationCenter.default.post(
                    name: .annotationDidDeleteFromOutline,
                    object: nil,
                    userInfo: ["annotations": [annotation]]
                )

                // (Opsional) Cek jika parent menjadi kosong, apakah mau dihapus juga?
                // if parentNode.children.isEmpty { ... remove parent ... }
            } catch {
                #if DEBUG
                    print("error delete single annotation: \(error)")
                #endif
            }
        }
    }

    // MARK: - NSOutlineViewDataSource
    func outlineView(
        _ outlineView: NSOutlineView,
        numberOfChildrenOfItem item: Any?
    ) -> Int {
        if item == nil {
            return currentRootNode?.children.count ?? 0
        }
        if let node = item as? AnnotationNode {
            return node.children.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any)
        -> Bool
    {
        if let node = item as? AnnotationNode {
            return !node.children.isEmpty
        }
        return false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        child index: Int,
        ofItem item: Any?
    ) -> Any {
        if item == nil {
            guard let node = currentRootNode?.children[index] else {
                fatalError("Item not found at root index \(index)")
            }
            return node
        }
        if let node = item as? AnnotationNode {
            return node.children[index]
        }
        fatalError("Invalid item or index.")
    }
}

extension AnnotationOutlineDataSource: NSOutlineViewDelegate,
    NSTableViewDelegate
{
    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? AnnotationNode else { return nil }

        // Node buku (tanpa annotation)
        if node.annotation == nil {
            let cell =
                outlineView.makeView(
                    withIdentifier: NSUserInterfaceItemIdentifier("BooksCell"),
                    owner: self
                ) as? NSTableCellView
            cell?.textField?.stringValue = node.title
            return cell
        }

        // Node anotasi
        guard let annotation = node.annotation,
            let color = NSColor(hex: annotation.colorHex),
            let cell = outlineView.makeView(
                withIdentifier: NSUserInterfaceItemIdentifier("AnnotationCell"),
                owner: self
            ) as? AnnotationCellView
        else {
            return nil
        }

        let text = annotation.context
        let attributedString = NSMutableAttributedString(string: text)

        attributedString.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: text.count)
        )
        let fullRg = NSRange(location: 0, length: attributedString.length)

        switch annotation.type {
        case .highlight:
            attributedString.addAttribute(
                .backgroundColor,
                value: color.withAlphaComponent(0.3),
                range: fullRg
            )
        case .underline:
            attributedString.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: fullRg
            )
        }

        cell.pagePart.stringValue =
            "الجزء: \(annotation.partArb ?? "-") • الصفحة: \(annotation.pageArb ?? "-")"
        cell.context.attributedStringValue = attributedString

        if annotation.note == nil {
            cell.note.isHidden = true
        } else {
            cell.note.isHidden = false
            cell.note.stringValue = annotation.note ?? "-"
        }

        let timestampInt64 = annotation.createdAt
        let targetDate = Date(
            timeIntervalSince1970: TimeInterval(timestampInt64)
        )

        let formattedString: String
        if calendar.isDateInToday(targetDate) {
            formattedString = relativeFormatter.localizedString(
                for: targetDate,
                relativeTo: Date()
            )
        } else {
            formattedString = dateFormatter.string(from: targetDate)
        }

        cell.date.stringValue = formattedString
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any)
        -> CGFloat
    {
        guard let node = item as? AnnotationNode, node.annotation != nil else {
            return 30
        }
        return 70
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else {
            return
        }

        let row = outlineView.selectedRow
        onSelectItem?(row)

        guard let item = outlineView.item(atRow: row) as? AnnotationNode,
            let annotation = item.annotation
        else {
            #if DEBUG
                print("outlineView item not as Annotations")
            #endif
            return
        }

        delegate?.didSelect(annotation: annotation)
    }

    func tableView(
        _ tableView: NSTableView,
        rowActionsForRow row: Int,
        edge: NSTableView.RowActionEdge
    ) -> [NSTableViewRowAction] {

        guard edge == .trailing else { return [] }

        let deleteAction = NSTableViewRowAction(
            style: .destructive,
            title: "Delete"
        ) { [weak self] _, _ in
            guard let self else { return }
            deleteMenuItem.representedObject = row
            deleteItem(deleteMenuItem)
        }

        if let baseImage = NSImage(
            systemSymbolName: "trash.slash.fill",
            accessibilityDescription: nil
        ) {
            // Konfigurasi simbol: pointSize sesuai tinggi row
            let config = NSImage.SymbolConfiguration(
                pointSize: 28,
                weight: .regular,
                scale: .large
            )
            let img = baseImage.withSymbolConfiguration(config)

            deleteAction.image = img
        }

        return [deleteAction]
    }
}

// MARK: - Search Extension
extension AnnotationOutlineDataSource {

    func applySearchFilter(text: String?) {
        currentSearchText = text

        guard let originalRoot = AnnotationManager.shared.rootNode else {
            filteredRootNode = nil
            return
        }

        guard let searchText = text?.lowercased(), !searchText.isEmpty else {
            filteredRootNode = nil
            return
        }

        let newRoot = AnnotationNode(title: originalRoot.title)

        for child in originalRoot.children {
            if let copiedNode = copyMatchingPath(
                sourceNode: child,
                searchText: searchText
            ) {
                newRoot.children.append(copiedNode)
            }
        }

        filteredRootNode = newRoot
    }

    private func copyMatchingPath(
        sourceNode: AnnotationNode,
        searchText: String
    ) -> AnnotationNode? {
        // 1. Cek apakah Title cocok
        let titleMatches = sourceNode.title.removingHarakat().contains(
            searchText
        )

        // 2. Cek apakah Context atau Note di dalam Annotation cocok
        var annotationMatches = false
        if let ann = sourceNode.annotation {
            let contextMatches = ann.context.removingHarakat().contains(
                searchText
            )
            let noteMatches =
                ann.note?.removingHarakat().contains(searchText) ?? false
            annotationMatches = contextMatches || noteMatches
        }

        // Jika node ini sendiri cocok (baik title, context, atau note)
        if titleMatches || annotationMatches {
            let copiedNode = AnnotationNode(
                title: sourceNode.title,
                annotation: sourceNode.annotation
            )
            // Jika node induk cocok, kita biasanya ingin menampilkan semua anaknya
            copiedNode.children = sourceNode.children
            return copiedNode
        }

        // 3. Jika node ini tidak cocok, cek apakah ada anaknya yang cocok (Recursive)
        var matchingChildren: [AnnotationNode] = []
        for child in sourceNode.children {
            if let copiedChild = copyMatchingPath(
                sourceNode: child,
                searchText: searchText
            ) {
                matchingChildren.append(copiedChild)
            }
        }

        // Jika ada anak yang cocok, kita tetap harus mengembalikan node ini (sebagai jalur/path)
        if !matchingChildren.isEmpty {
            let copiedNode = AnnotationNode(
                title: sourceNode.title,
                annotation: sourceNode.annotation
            )
            copiedNode.children = matchingChildren
            return copiedNode
        }

        return nil
    }
}

// MARK: - Menu Delegate
extension AnnotationOutlineDataSource: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let outlineView else { return }
        let clickedRow = outlineView.clickedRow
        deleteMenuItem.isHidden = clickedRow == -1
        deleteMenuItem.representedObject = clickedRow
        deleteMenuItem.target = self
        deleteMenuItem.action = #selector(deleteItem(_:))
    }
}
