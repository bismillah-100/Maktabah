# Library & Catalog Management Architecture

Modul **Library** bertanggung jawab atas manajemen siklus hidup katalog kitab (kategori, pengarang, kitab), pengunduhan berkas `.sqlite` per-kitab, integrasi mandiri ke dalam arsip majemuk (`1-20.sqlite`), pembaruan versi kitab (*book updates*), serta koordinasi navigasi katalog lintas platform macOS dan iOS.

---

## 1. Diagram Arsitektur Komponen

```mermaid
graph TD
    %% UI Layer
    subgraph UI ["UI Layer (macOS & iOS)"]
        MAC["LibraryVC (macOS)"]
        IOS["iOSLibraryView (iOS)"]
    end

    %% State Management
    subgraph VM ["ViewModel Layer"]
        LVM["LibraryViewModel<br/>(@Observable)"]
    end

    %% Core Dependencies
    subgraph Core ["Core Engine & Database"]
        DM["LibraryDataManager<br/>(Mutex Protected)"]
        BDM["BookDownloadManager<br/>(SingleFlight)"]
        BAI["BookArchiveIntegrator<br/>(Actor)"]
    end

    %% Flow
    MAC -->|Observe & Action| LVM
    IOS -->|Observe & Action| LVM
    
    LVM -->|Query/Cache| DM
    LVM -->|Download Book| BDM
    LVM -->|Integrate Archive| BAI
    
    DM -->|Read/Write| SQLite[(main.sqlite)]
    BDM <-->|Fetch| GitHub((GitHub Releases))
```

---

## 2. Struktur Sub-Dokumentasi

Modul Library disusun secara modular ke dalam beberapa sub-dokumen teknis:

* **[Data Models](models.md)**: Model katalog inti (`BooksData`, `CategoryData`, `Muallif`), entitas pembaruan (`BookUpdateModels`), dan enum filter UI.
* **[Database & Core Persistence](database.md)**: Ketergantungan erat `LibraryDataManager` dengan `DatabaseManager` dan arsitektur caching In-Memory berbasis `Mutex`.
* **[Download & Archive Integration](download-integration.md)**: Mekanisme `BookDownloadManager`, deduplikasi HTTP `SingleFlight`, dan integrasi arsip `BookArchiveIntegrator` berbasis Actor.
* **[FTS Indexing & Stemming](stemming.md)**: Proses pembuatan indeks FTS5, dekompresi Zstd, normalisasi teks Arab, dan migrasi FTS.
* **[iOS Implementation](ios.md)**: Implementasi SwiftUI (`iOSLibraryView`), wrapper UIKit (`LibraryViewControllerWrapper`), toolbar mode, dan offline import.
* **[macOS Implementation](macos.md)**: Implementasi AppKit (`LibraryVC`), manajemen outline multi-kolom (`LibraryViewManager`), dan batch diffing.
* **[Protocols & Delegation](protocols.md)**: Kontrak `LibraryDelegate`, `LibraryViewDelegate`, dan `SearchableLibrarySidebar`.
* **[ViewModel, State & Combine](viewmodel.md)**: Arsitektur `@Observable LibraryViewModel`, pengelolaan state katalog, pagination, filter mode, dan observasi Combine/NotificationCenter.
