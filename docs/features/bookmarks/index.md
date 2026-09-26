# Bookmarks (Saved Results) Architecture

Modul **Bookmarks** (secara internal diimplementasikan sebagai *Saved Results*) mengelola penyimpanan persisten, organisasi hierarkis berbasis folder, dan sinkronisasi CloudKit untuk hasil pencarian kitab di aplikasi Maktabah. Modul ini memungkinkan pengguna menyimpan kueri pencarian beserta referensi kitab dan halaman yang cocok ke dalam struktur direktori hierarkis kustom.

---

## 1. Arsitektur & Diagram Alur (*Architecture & Pipeline*)

Arsitektur modul ini dibangun menggunakan pola MVVM dengan persistensi lokal SQLite dan sinkronisasi CloudKit dua arah:

```mermaid
flowchart TD
    MAC["SavedResults (macOS)"] --> RVM["ResultsViewModel (@Observable)"]
    IOS["iOSSavedResultsView (iOS)"] --> RVM

    DB["ResultsHandler"]
    SYNC["CloudKitSyncManager (ResultSyncHandler)"]
    MD["LibraryDataManager (Book Metadata Lookup)"]

    RVM -->|"Upsert / Load"| DB
    RVM -->|"Sync CloudKit"| SYNC
    RVM -->|"Join Book Metadata"| MD

    DB --> SQLite[("SearchResults.sqlite (WAL Mode)")]
    SYNC <-->|"Fetch / Upload"| CloudKit[("CloudKit Custom Zone")]

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class MAC,IOS ui;
    class RVM vm;
    class DB,SYNC,MD store;
    class SQLite,CloudKit db;
```

---

## 2. Pemisahan Tanggung Jawab (*Separation of Concerns*)

Komponen-komponen dalam modul ini mematuhi batas tanggung jawab yang tegas:

*   **UI Layer (macOS & iOS)**:
    *   Mengatur visualisasi representasi hierarki direktori (folder dan item hasil pencarian).
    *   Platform macOS (`SavedResults`, `ResultsViewManager`) mengonsumsi `BookmarkTreeChange` untuk mengeksekusi animasi *batch* pada `NSOutlineView` (`insertItems`, `removeItems`, `moveItem`).
    *   Platform iOS (`iOSSavedResultsView`, `iOSFolderContentList`) memanfaatkan deklarasi hierarki berbasis `NavigationStack`, *swipe actions*, dan *sheet* navigasi interaktif.

*   **ViewModel Layer (`ResultsViewModel`)**:
    *   Berperan sebagai *single source of truth* untuk antarmuka pengguna pada kedua platform.
    *   Memelihara *cache* struktural dalam memori (`folderById`, `parentById`, `resultById`) untuk *lookup* $O(1)$ selama pembaruan parsial.
    *   Mencegah siklus tak berujung (*circular dependency*) pada operasi pemindahan folder (*drag-and-drop*).

*   **Data Access Layer (`ResultsHandler`)**:
    *   Mengisolasi seluruh kueri SQL, migrasi skema tabel, dan eksekusi transaksi basis data `SearchResults.sqlite`.
    *   Menangani resolusi *orphan records* akibat perbedaan urutan penerimaan data sinkronisasi CloudKit.
    *   Mencatat mutasi luring ke dalam `SyncPendingStore`.

*   **Synchronization Layer (`CloudKitSyncManager`)**:
    *   Menerjemahkan rekaman lokal ke `CKRecord` dengan penamaan ID deterministik.
    *   Menjalankan resolusi konflik *Last-Write-Wins* (LWW) berbasis stempel waktu `lastModified`.

---

## 3. Peta Navigasi Dokumentasi Teknis

*   [Database & CloudKit Persistence](database.md)
    *   Skema SQLite, indeks unik gabungan, isolasi *thread* `SQLiteDatabase`, pemulihan *orphan records*, dan sinkronisasi CloudKit.
*   [Data Models & State Types](models.md)
    *   Struktur data hierarki, *result node*, model sinkronisasi, dan *tree diffing*.
*   [iOS SwiftUI Implementation](ios.md)
    *   Integrasi `NavigationStack`, pencarian global mendatar (*flattened search*), pengelolaan lembar pemindahan (*move sheet*), dan gestur geser (*swipe actions*).
*   [macOS AppKit Implementation](macos.md)
    *   Implementasi `NSOutlineView`, animasi *diffing* presisi tinggi (*batch updates*), *drag-and-drop* antar-hierarki, dan menu kontekstual.
*   [Protocols & Delegation](protocols.md)
    *   Kontrak komunikasi `@MainActor ResultsDelegate` untuk menghubungkan pemilihan markah ke modul Reader/Search.
*   [ViewModel & Reactive Workflows](viewmodel.md)
    *   Manajemen *state* berbasis `@Observable`, *cache lookup* $O(1)$, operasi rekursif hierarki, dan integrasi notifikasi.
