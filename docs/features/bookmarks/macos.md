# macOS AppKit Implementation

Dokumentasi ini menguraikan arsitektur antarmuka *native* macOS untuk modul markah, pengelolaan komponen `NSOutlineView`, orkestrasi pembaruan diferensial (*tree diffing / batch updates*), interaksi seret-dan-lepas (*drag-and-drop*), serta optimasi rendering berbasis AppKit pada direktori `Source/Features/Bookmarks/macOS/`.

---

## 1. Arsitektur Kontroler UI

Antarmuka markah pada macOS dikendalikan oleh koordinasi antara dua komponen utama:

1.  **`SavedResults: NSViewController`**:
    *   Mengatur siklus hidup tampilan (*view lifecycle*), tombol bilah alat (*toolbar buttons* seperti Tambah Folder dan Hapus), kolom pencarian `NSSearchField`, serta pembungkus lembar modal (*sheet presentation*).
2.  **`ResultsViewManager: NSObject`**:
    *   Pengontrol logika presentasi yang bertindak sebagai `NSOutlineViewDataSource` dan `NSOutlineViewDelegate`.
    *   Mengonsumsi mutasi dari `ResultsViewModel` dan menerjemahkannya ke dalam instruksi animasi *batch* AppKit.

```
macOS/
├── SavedResults.swift          # NSViewController utama
├── ResultsViewManager.swift    # DataSource, Delegate & Diffing Engine
├── ResultsViewDrag.swift       # Validasi & penanganan Drag-and-Drop
├── ResultsViewMenu.swift       # Delegasi NSMenu kontekstual
├── ResultsViewTextField.swift  # Penanganan inline rename cell
└── CellViews/
    ├── FolderCellView.xib      # Tata letak sel folder
    ├── ResultCellView.swift    # Subkelas sel hasil kueri
    └── ResultCellView.xib      # Tata letak sel hasil kueri
```

---

## 2. Pendaftaran Komponen Sel & NIB

`ResultsViewManager` mendaftarkan berkas antarmuka `.xib` secara mandiri saat inisialisasi:

```swift
private func setupNibs() {
    ReusableFunc.registerNib(
        tableView: outlineView,
        nibName: .bookmarkChildNib,
        cellIdentifier: .bookmarkChild
    )
    ReusableFunc.registerNib(
        tableView: outlineView,
        nibName: .bookmarkParentNib,
        cellIdentifier: .bookmarkParent
    )
    outlineView.registerForDraggedTypes([.folderNode, .resultNode])
    outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
}
```

*   `bookmarkParent`: Sel yang merepresentasikan `FolderNode`, menampilkan ikon folder sistem dan tombol ekspansi panah segitiga bawaan macOS.
*   `bookmarkChild`: Sel `ResultCellView` yang menampilkan ikon mode pencarian, judul kueri, dan jumlah item halaman yang cocok.

---

## 3. Mekanisme Batch Diffing (`applyTreeChange`)

Untuk menghindarkan pengguna dari kedipan visual (*flickering*) dan kehilangan status baris yang sedang dipilih atau diekspansi saat data berubah, sistem tidak menggunakan `outlineView.reloadData()` untuk mutasi normal, melainkan menerapkan pembaruan diferensial (*tree diffing*):

```swift
func applyTreeChange(_ change: BookmarkTreeChange) {
    guard !isSearching else {
        outlineView.reloadData()
        return
    }

    switch change {
    case .fullReload:
        outlineView.reloadData()
    case .insertFolder, .removeFolder, .updateFolder, .moveFolder:
        applyFolderTreeChange(change)
    case .insertResult, .removeResult, .updateResult, .moveResult:
        applyResultTreeChange(change)
    }
}
```

### Animasi Pembaruan Node Hasil (`applyResultTreeChange`)

Karena node hasil (`ResultNode`) dan subfolder (`FolderNode`) berada di bawah kontainer `children` yang sama pada `NSOutlineView`, indeks hasil pencarian disesuaikan sebesar jumlah subfolder yang ada:

```swift
case let .insertResult(_, parentId, index):
    let parentFolder = parentId.flatMap { vm.findFolder($0) }
    let folderCount = parentFolder?.children.count ?? vm.folderRoots.count
    outlineView.insertItems(
        at: IndexSet(integer: folderCount + index),
        inParent: parentFolder,
        withAnimation: .effectGap
    )
    outlineView.reloadItem(parentFolder)
```

---

## 4. Penanganan Drag & Drop (`ResultsViewDrag.swift`)

Sistem mendukung pemindahan folder dan hasil kueri antardirektori menggunakan *protocol* *drag-and-drop* AppKit.

### Validasi Pencegahan Siklus (*Cycle Detection*)

Saat folder diseret, sistem memvalidasi calon folder tujuan untuk mencegah pengguna memasukkan folder ke dalam dirinya sendiri atau ke dalam rantai keturunannya (*cycle prevention*):

```swift
func outlineView(
    _ outlineView: NSOutlineView,
    validateDrop info: NSDraggingInfo,
    proposedItem item: Any?,
    proposedChildIndex index: Int
) -> NSDragOperation {
    guard index == NSOutlineViewDropOnItemIndex, !(item is ResultNode) else { return [] }
    guard let targetFolder = item as? FolderNode,
          let pbItems = info.draggingPasteboard.pasteboardItems
    else { return .move }

    for pb in pbItems {
        guard let idStr = pb.string(forType: .folderNode),
          let draggedId = Int64(idStr),
          let draggedNode = vm.findFolder(draggedId)
        else { continue }

        if isDescendant(folder: targetFolder, of: draggedNode.id) {
            return [] // Tolak operasi drag (lingkaran tak berujung terdeteksi)
        }
    }

    return .move
}
```

---

## 5. Pencarian Teks dengan Debounce Asinkron

Penyaringan daftar markah pada `NSSearchField` dilindungi oleh penundaan (*debouncing*) sebesar 300 milidetik menggunakan Swift Concurrency `Task`:

```swift
func searchResults(for text: String) {
    searchTask?.cancel()

    if text.isEmpty {
        resetSearchState()
        return
    }

    searchTask = Task { @MainActor in
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return // Task dibatalkan sebelum jeda berakhir
        }

        let query = text.lowercased()
        let matchedFolders = vm.searchFoldersInMemory(query)
        matchingFolderIds = Set(matchedFolders.map(\.id))

        let resultsWithPath = vm.searchResultsWithFolderPath(query)
        buildGroupedSearchResults(from: resultsWithPath)

        isSearching = true
        applySearchUI(resultsWithPath: resultsWithPath)
    }
}
```

!!! note "Pembersihan Status Pencarian"
    Saat kolom pencarian dikosongkan, `isSearching` disetel kembali ke `false`, dan `NSOutlineView` memuat ulang seluruh struktur hierarki dengan status ekspansi folder sebelumnya tetap terjaga berkat properti `autosaveExpandedItems = true`.
