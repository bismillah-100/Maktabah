# AppKit Implementation (macOS)

Arsitektur aplikasi pada macOS untuk modul History dirancang secara minimalis. Tidak ada folder khusus `macOS/` di dalam struktur `Source/Features/History/`. Sebagai gantinya, History dan Favorites secara cerdas menumpang atau menggunakan ulang (Re-use) _View Hierarchy_ milik `LibraryVC`.

## Integrasi *Diffable Data Source* pada `LibraryVC`

Komponen macOS `NSCollectionView` pada antarmuka korpus Maktabah (`LibraryVC`) memiliki opsi segmentasi kontrol di bagian *Toolbar* (melalui `NSSegmentedControl`) yang salah satunya memuat opsi *History*.

Ketika pengguna beralih mode ke *History* atau *Favorites*, pengelola (_Manager_) pustaka (`LibraryViewManager`) secara langsung mendengarkan status koleksi array dari `HistoryViewModel`.

```swift
// Di dalam Source/Features/Library/macOS/LibraryView+Diffing.swift
NotificationCenter.default.publisher(for: .historyDidChange)
// ...
let snapshot = createSnapshot(
    for: .history,
    newBooks: historyManager.historyBooks,
    categoryName: String(localized: "History")
)
```

Metode injeksi status ini memastikan performa koleksi mulus. Mengandalkan `NSCollectionViewDiffableDataSource`, perbedaan array yang dihasilkan `historyManager.historyBooks` otomatis dianimasikan menjadi pergeseran atau pemunculan kartu sampul (*Cover Card*) tanpa perlu antarmuka visual baru (`XIB` atau _Storyboard_).

## Aksi Kontekstual Menu (*Contextual Menu*)

Karena dirender di dalam `Library`, _delegate_ dari NSCollectionView merespons aksi klik-kanan dengan menyelipkan opsi interaktif khusus untuk *Favorites* dan *History*.

```swift
// Source/Features/Library/macOS/LibraryViewManager.swift
let isFav = HistoryViewModel.shared.isFavorite(book.id)
let isHistory = HistoryViewModel.shared.historyBookIds.contains(book.id)

if isHistory {
    let historyItem = NSMenuItem(
        title: String(localized: "Remove from History"), 
        action: #selector(removeHistoryAction(_:)), 
        keyEquivalent: ""
    )
    historyItem.target = self
    historyItem.representedObject = book
    menu.addItem(historyItem)
}
```

Aksi `removeHistoryAction` secara langsung melakukan relai pendelegasian balik ke:
`HistoryViewModel.shared.removeHistory(for: book.id)`

## Settings & Overlay App

Selain dari `LibraryVC`, rujukan pada `HistoryViewModel` di level UI macOS dapat ditemukan di dalam jendela `SettingsView.swift` (ditampilkan secara _overlay_), di mana pengguna bisa mengatur preferensi sakelar (*Toggle*) `addBooksOpenedFromSearchResultsToReadingHistory`. Opsi ini menentukan secara longgar apakah membuka buku secara serampangan dari bilah pencarian wajib mendaftarkannya ke deretan rekam riwayat History atau tidak.

Secara teknis, abstraksi arsitektur ini memangkas lebih dari sekian megabita redundansi *view code* karena modul History sekadar merubah bentuk sebagai filter semantik yang meminjam *pipeline renderer* modul Library.
