# Library & Catalog Management Architecture

Modul **Library** bertanggung jawab atas manajemen siklus hidup katalog kitab (kategori, pengarang, kitab), pengunduhan berkas `.sqlite` per-kitab, integrasi ke dalam arsip majemuk (`1-20.sqlite`), pembaruan versi kitab (*book updates*), serta koordinasi navigasi katalog lintas platform macOS dan iOS.

---

## 1. Diagram Arsitektur Komponen

```mermaid
flowchart TD
    MAC["LibraryVC (macOS)"] --> LVM["LibraryViewModel (@Observable)"]
    IOS["iOSLibraryView (iOS)"] --> LVM
    
    LVM ~~~ Core
    
    subgraph Core ["Core Engine & Database"]
        DM["LibraryDataManager (Mutex Protected)"]
        BDM["BookDownloadManager (SingleFlight)"]
        BAI["BookArchiveIntegrator (Actor)"]
    end
    
    LVM -->|"Query / Cache"| DM
    LVM -->|"Download Book"| BDM
    LVM -->|"Integrate Archive"| BAI
    
    DM --> SQLite[("main.sqlite (Katalog)")]
    BDM <-->|"Fetch zstd"| GitHub["GitHub Releases"]

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class MAC,IOS ui;
    class LVM vm;
    class DM,BDM,BAI,GitHub store;
    class SQLite db;
```

---

## 2. Struktur Sub-Dokumentasi

Modul Library disusun secara modular ke dalam beberapa sub-dokumen teknis:

* **[Data Models](models.md)**: Model katalog inti (`BooksData`, `CategoryData`, `Muallif`), entitas pembaruan (`BookUpdateModels`), dan enum filter antarmuka pengguna.
* **[Database & Core Persistence](database.md)**: Integrasi `LibraryDataManager` dengan `DatabaseManager` dan arsitektur *caching in-memory* berbasis `Mutex`.
* **[Download & Archive Integration](download-integration.md)**: Mekanisme `BookDownloadManager`, deduplikasi HTTP `SingleFlight`, dan integrasi arsip `BookArchiveIntegrator` berbasis *Actor*.
* **[FTS Indexing & Stemming](stemming.md)**: Proses pembuatan indeks FTS5, dekompresi Zstandard (zstd), normalisasi teks Arab, dan migrasi FTS.
* **[iOS Implementation](ios.md)**: Implementasi SwiftUI (`iOSLibraryView`), jembatan UIKit (`LibraryViewControllerWrapper`), mode *toolbar*, dan impor luring (*offline import*).
* **[macOS Implementation](macos.md)**: Implementasi AppKit (`LibraryVC`), manajemen struktur hierarki multi-kolom (`LibraryViewManager`), dan *batch diffing*.
* **[Protocols & Delegation](protocols.md)**: Kontrak `LibraryDelegate`, `LibraryViewDelegate`, dan `SearchableLibrarySidebar`.
* **[ViewModel, State & Combine](viewmodel.md)**: Arsitektur `@Observable LibraryViewModel`, pengelolaan *state* katalog, *pagination*, mode filter, dan observasi Combine/NotificationCenter.
