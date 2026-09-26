# macOS Implementation (AppKit)

Implementasi antarmuka Library di macOS berpusat pada hierarki `NSOutlineView` yang dioptimalkan untuk performa tinggi saat menampilkan ribuan kitab dan kategori, dilengkapi bilah segmentasi filter 4-mode di bagian bawah panel *sidebar*.

Sumber kode: `Source/Features/Library/macOS/`

---

## 1. Arsitektur Komponen Visual

Arsitektur antarmuka perpustakaan di macOS memisahkan antara kontainer navigasi, presentasi data, dan bilah segmentasi:

### A. Hierarki Kontainer Library

```mermaid
flowchart TD
    LVC["LibraryVC (NSViewController)"]
    SRC["DSFSearchField (Quick Filter)"]
    SV["NSScrollView"]
    OV["NSOutlineView (Hierarki Kategori & Kitab)"]

    LVC --> SRC
    LVC --> SV
    SV --> OV

    OV ~~~ GLASS

    GLASS["NSGlassEffectView (Capsule Container)"]
    SEG["NSSegmentedControl (Filter 4 Mode)"]
    LVC --> GLASS
    GLASS --> SEG

    SEG ~~~ LVM

    LVM["LibraryViewManager (DataSource & Delegate)"]
    VM["LibraryViewModel"]
    BDL["BulkDownloadVC (Progress Sheet)"]

    LVC --> LVM
    LVM --> VM
    LVC -.->|"Present Sheet"| BDL

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class LVC,SRC,SV,OV,GLASS,SEG,BDL ui;
    class LVM store;
    class VM vm;
```

### B. Taksonomi Bilah Segmentasi Bawah 4-Mode

```mermaid
mindmap
  root((Filter 4 Mode))
    Semua Kitab
      icon["list.bullet"]
      desc["Katalog lengkap kategori & kitab"]
    Favorit
      icon["star.fill"]
      desc["Menyaring kitab bertanda bintang"]
    Histori
      icon["clock.fill"]
      desc["Daftar bacaan terakhir"]
    Terunduh
      icon["arrow.down.circle.fill"]
      desc["Kitab dengan arsip SQLite lokal"]
```

### C. Siklus Transisi Mode Segmentasi

```mermaid
stateDiagram-v2
    [*] --> AllBooks: Default Launch
    AllBooks --> Favorites: Klik Star
    Favorites --> History: Klik Clock
    History --> Downloaded: Klik Downloaded
    Downloaded --> AllBooks: Klik All
    Favorites --> AllBooks: Klik All
    History --> Favorites: Klik Star
    Downloaded --> History: Klik Clock

    state AllBooks {
        [*] --> LoadAllCategories
        LoadAllCategories --> RenderFullTree
    }
    state Favorites {
        [*] --> QueryFavoriteIDs
        QueryFavoriteIDs --> FilterTreeFavorites
    }
    state History {
        [*] --> FetchRecentHistory
        FetchRecentHistory --> SortByLastRead
    }
    state Downloaded {
        [*] --> ScanLocalArchives
        ScanLocalArchives --> FilterLocalOnly
    }
```

---

## 2. Alur Interaksi: Dari Aksi Klik Baris Kitab ke TextView

Ketika pengguna mengklik salah satu baris kitab di `NSOutlineView`, data mengalir melintasi delegasi hingga dirender pada mesin pembaca:

```mermaid
sequenceDiagram
autonumber

actor User as Pengguna
participant Lib as LibraryViewManager
participant VC as IbarotTextVC
participant Hist as HistoryManager

User->>+Lib: Klik baris kitab (NSOutlineView)
Note over Lib: outlineViewSelectionDidChange()<br/>guard !isUpdatingOutline
Lib->>+VC: didSelectBook -> displayBook(book)
VC->>VC: didChangeBook()

opt if viewModel.recordHistory
    VC->>+Hist: addBookToHistory(book.id) (Instan)
    Hist-->>-VC: Perekaman selesai
    Note over Lib,Hist: .historyDidChange diterima Lib dengan debounce 3 detik
end
deactivate VC
deactivate Lib
```

```mermaid
sequenceDiagram
autonumber

participant VC as IbarotTextVC
participant VM as ReaderViewModel
participant DB as BookConnection
participant TV as IbarotTextView

VC->>+VM: loadInitialContent(book)

par Ambil Konten Kitab
    VM->>+DB: getContent(contentId)
    DB-->>-VM: sourceText & harakat
    VM->>VM: ArabicTextRenderer.render()
and Pembaruan Riwayat
    VM->>VM: loadFromHistory(book)
    VM->>VM: updateContentState & HistoryVM.updateLastContentId()
end

VM-->>-VC: closure onPayloadChanged?(payload)
VC->>+TV: textStorage.setAttributedString()
TV->>TV: ensureLayout()
TV->>TV: restoreScrollPosition()
deactivate TV
```

---

## 3. Bedah Komponen & Logika Antarmuka

### A. Kontainer Segmentasi Bawah 4-Mode (setupFilterSegment)
Di bagian bawah *sidebar*, `LibraryVC` menyematkan bilah segmentasi mengambang berpenampilan kapsul (`NSGlassEffectView` di macOS 26+):

* **Segment 0 (`list.bullet`)**: Menampilkan seluruh katalog pustaka (*All Categories & Books*).
* **Segment 1 (`star.fill`)**: Menyaring hanya kitab yang telah ditandai sebagai favorit oleh pengguna.
* **Segment 2 (`clock.fill`)**: Menyajikan daftar kitab berdasarkan histori bacaan terakhir.
* **Segment 3 (`arrow.down.circle.fill`)**: Mode khusus unduhan (tersedia saat `AppConfig.isUsingBundleMode` aktif) untuk menyaring hanya kitab yang berkas arsip SQLite-nya telah diunduh secara lokal.
* **Manajemen Inset ScrollView (`updateScrollViewConstraint`)**: Ketinggian kontainer kapsul dihitung secara otomatis untuk menyesuaikan `scrollView.contentInsets.bottom` (atau `scrollViewBottomConstraint`), mencegah baris terbawah tabel tertutup oleh tombol segmentasi.

### B. LibraryVC (NSViewController)

* Mengelola siklus hidup tampilan *sidebar*, kaitan *constraint* pencarian, dan inisialisasi awal dataset secara asinkron (`dataVM.prepareData`).
* Mengamati notifikasi `.libraryFolderChanged` untuk mereset seleksi dan memuat ulang struktur direktori saat folder basis data beralih.

### C. LibraryViewManager (Class) & Render Baris Kustom

* Mengimplementasikan `NSOutlineViewDataSource` dan `NSOutlineViewDelegate`.
* Membedakan *rendering* sel induk (kategori kitab yang dapat diekspansi) dengan *child cell* (judul kitab dengan tipografi Arab, nama pengarang, indikator ketersediaan berkas, dan kapasitas MB).
* Menyediakan *context menu* klik kanan: Hapus unduhan arsip lokal, Buka detail informasi kitab (`BookInfoPopoverVC`), dan Tambah/Hapus dari Favorit.
* **Pencegahan Rekursi Seleksi (`isUpdatingOutline`)**: Menjaga agar pembaruan programatis pada outline view (`beginUpdates`, `selectRowIndexes`, `endUpdates`) tidak memicu *event* ganda pada `outlineViewSelectionDidChange`.
* **Preservasi Seleksi Flat List (`restoreFlatSelection`)**: Pada mode daftar datar (seperti hasil filter pencarian dan riwayat), seleksi dipulihkan menggunakan indeks baris langsung (`selectFlatRow`) untuk mencegah hilangnya fokus item yang aktif.

### D. Animasi Batch Inkremental & Debouncing Histori (`LibraryView+Diffing`)
Untuk mencegah *flickering* visual dan lonjakan tampilan (*content jumping*):

* **Sinkronisasi Filter Pencarian**: Pembaruan daftar datar memvalidasi `searchQuery` aktif dan sinkronisasi `baseCategories = displayedCategories`, menjamin hasil filter tetap utuh saat dataset dimutasi.
* **Debounce Pembaruan Histori (3 Detik)**: Notifikasi `.historyDidChange` di-*debounce* selama 3 detik pada `RunLoop.main` sebelum memicu penataan ulang baris. Hal ini mencegah outline view melompat-lompat (*jitter*) ketika pengguna menavigasi beberapa kitab secara cepat, sementara ID kitab tetap tercatat ke basis data histori secara instan.
* **Mutasi Terarah**: Menjalankan mutasi *native* AppKit secara presisi: `outlineView.insertItems(at:inParent:withAnimation:)` dan `outlineView.removeItems(at:inParent:withAnimation:)`.

### E. BulkDownloadVC (NSViewController)

* Panel *sheet* modal yang menampilkan status antrean unduhan kitab massal.
* Memuat bilah progres menyeluruh (*aggregate progress bar*), kecepatan jaringan aktual, dan kontrol jeda/batalkan.
