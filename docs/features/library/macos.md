# macOS Implementation (AppKit)

Sumber kode: `Source/Features/Library/macOS/`

---

## 1. Arsitektur Presentasi AppKit

Implementasi macOS berpusat pada hierarki `NSOutlineView` yang dirancang untuk menampilkan ribuan kitab dan kategori dengan kinerja 60 FPS:

```text
[ LibraryVC (NSViewController) ]
        │
        ├── [ LibraryViewManager ] ◄── Manajer DataSource & Delegate NSOutlineView
        │        │
        │        ├── [ LibraryView+Diffing ] ◄── Kalkulasi Delta Perubahan Baris
        │        └── [ DSFSearchField ] ◄── Input Pencarian Cepat
        │
        └── [ BulkDownloadVC ] ◄── Panel Modal Pemantau Unduhan Massal
```

---

## 2. Komponen Inti macOS

### A. `LibraryVC` (`NSViewController`)
* Bertanggung jawab atas siklus hidup antarmuka sidebar perpustakaan.
* Mengatur *auto-layout constraints* untuk area pencarian dan scroll view (`scrollViewTopConstraint`).
* Mengamati notifikasi `.libraryFolderChanged` via `NotificationToken` dan memicu `outlineView.deselectAll(nil)` serta reload antarmuka.

### B. `LibraryViewManager`
* Mengimplementasikan protokol `NSOutlineViewDataSource` dan `NSOutlineViewDelegate`.
* Menangani rendering sel kustom untuk baris kategori (header expandable) dan baris kitab (menampilkan judul Arab, pengarang, ikon status download, dan ukuran berkas).
* Mengelola context menu (klik kanan): Opsi hapus unduhan, lihat informasi detail kitab, dan tandai favorit.

### C. `LibraryView+Diffing` (Batch Animation)
Alih-alih memanggil `outlineView.reloadData()` yang mengakibatkan kedipan UI dan hilangnya status seleksi baris saat unduhan selesai, ekstensi ini menghitung perbedaan struktural (*diffing*) dan memicu operasi mutasi native AppKit:

* `outlineView.insertItems(at:inParent:withAnimation:)`
* `outlineView.removeItems(at:inParent:withAnimation:)`

### D. `BulkDownloadVC`
* Menampilkan panel sheet modal untuk pengunduhan massal banyak kitab sekaligus.
* Menampilkan bilah kemajuan (*progress bar*) keseluruhan, kecepatan unduhan jaringan, dan daftar antrean kitab yang sedang diproses.
