# AppKit Implementation (macOS)

Arsitektur aplikasi pada macOS untuk modul History dirancang secara minimalis. Tidak ada folder khusus `macOS/` di dalam struktur `Source/Features/History/`. Sebagai gantinya, History dan Favorites memanfaatkan kembali (*re-use*) hierarki tampilan (*View Hierarchy*) milik `LibraryVC`.

## Integrasi *Diffable Data Source* pada `LibraryVC`

Komponen macOS `NSCollectionView` pada antarmuka korpus Maktabah (`LibraryVC`) memiliki opsi segmentasi kontrol di bagian *Toolbar* (melalui `NSSegmentedControl`) yang salah satunya memuat opsi *History*.

Ketika pengguna beralih mode ke *History* atau *Favorites*, pengelola (*Manager*) pustaka (`LibraryViewManager`) secara langsung mendengarkan status koleksi array dari `HistoryViewModel`.

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

Metode injeksi status ini memastikan performa koleksi yang mulus. Mengandalkan `NSCollectionViewDiffableDataSource`, perbedaan array yang dihasilkan `historyManager.historyBooks` otomatis dianimasikan menjadi pergeseran atau pemunculan kartu sampul (*Cover Card*) tanpa perlu antarmuka visual baru (`XIB` atau *Storyboard*).

## Aksi Menu Kontekstual (*Contextual Menu*)

Karena dirender di dalam `Library`, *delegate* dari `NSCollectionView` merespons aksi klik kanan dengan menyisipkan opsi interaktif khusus untuk *Favorites* dan *History*.

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

Selain dari `LibraryVC`, rujukan pada `HistoryViewModel` di level UI macOS dapat ditemukan di dalam jendela `SettingsView.swift` (ditampilkan secara *overlay*), tempat pengguna dapat mengatur preferensi sakelar (*Toggle*) `addBooksOpenedFromSearchResultsToReadingHistory`. Opsi ini menentukan apakah membuka buku dari bilah pencarian otomatis mendaftarkannya ke dalam riwayat bacaan atau tidak.

Secara teknis, abstraksi arsitektur ini mengeliminasi redundansi *view code* karena modul History berfungsi sebagai filter semantik yang meminjam *pipeline renderer* modul Library.
