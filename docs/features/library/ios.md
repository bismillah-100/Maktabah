# iOS Implementation (SwiftUI & UIKit Bridge)

Sumber kode: `Source/Features/Library/iOS/`

---

## 1. Arsitektur Presentasi iOS

Pada platform iOS dan iPadOS, modul Library menggabungkan kekuatan deklaratif SwiftUI dengan efisiensi performa UIKit untuk menangani dataset berukuran besar:

```text
[ iOSLibraryView (SwiftUI Root Container) ]
        │
        ├── [ Toolbar & Sheets ]
        │        ├── OfflineImportFormView (Sheet Impor Kitab Lokal)
        │        └── UpdateView (Sheet Pembaruan Versi Kitab)
        │
        ├── [ AuthorModeView ] ◄── Tampilan Hirarki Pengarang (SwiftUI List)
        │
        └── [ LibraryViewControllerWrapper (UIViewControllerRepresentable) ]
                 │
                 └── [ iOSLibraryViewController (UIKit Table/Collection View) ]
```

---

## 2. Komponen Inti iOS

### A. `iOSLibraryView` (SwiftUI View)
* Kontainer deklaratif yang terikat langsung ke `@Bindable var viewModel = navigationManager.libraryViewModel`.
* Mengelola presentasi berbagai lembar kerja modal (*sheets*) dan dialog konfirmasi (*alerts*):
    * **Import Sheet**: Membuka `OfflineImportFormView` untuk menambahkan berkas kitab eksternal (.sqlite) secara mandiri.
    * **Update Sheet**: Membuka `UpdateView` saat ada kitab yang memiliki versi revisi di server GitHub Releases.
    * **Bulk Delete Alert**: Menampilkan dialog peringatan sebelum menghapus berkas arsip lokal kitab terpilih.
* Menjalankan tugas asinkron saat tampilan muncul: `viewModel.checkBookUpdatesPeriodically()`.

### B. `LibraryViewControllerWrapper` (`UIViewControllerRepresentable`)
Untuk memastikan pengguliran ribuan baris buku tetap berada pada performa 60-120 FPS (terutama di layar ProMotion iPad), controller UIKit `iOSLibraryViewController` dijembatani ke SwiftUI.

Tanggung jawab wrapper:

1. `makeUIViewController`: Menginstansiasi `iOSLibraryViewController` dan memasang delegasi koordinasi.
2. `updateUIViewController`: Meneruskan pembaruan state SwiftUI (seperti filter mode, pencarian, dan status seleksi massal) ke dalam kontroler UIKit tanpa membuat ulang hierarki view.

### C. `AuthorModeView`
Tampilan khusus saat pengguna mengaktifkan mode pengelompokan berdasarkan pengarang (`viewMode == .author`):

* Menampilkan daftar nama pengarang (*muallif*) secara alfabetis atau kronologis tahun wafat.
* Mengadopsi lazy pagination via `PaginationLibrary.swift` untuk memuat buku karya pengarang secara bertahap saat baris digulir.
