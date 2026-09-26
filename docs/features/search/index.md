# Search

Modul **Search** menangani pencarian *Full-Text Search* (FTS) dalam pustaka kitab yang tersedia. Modul ini terintegrasi erat dengan `SearchEngine` dari *Core* dan mengelola pencarian di ribuan tabel secara konkuren dengan kapabilitas jeda/lanjutkan (*pause/resume*), serta filter kriteria pencarian yang komprehensif (Frasa, Mengandung, OR, dan Jarak Kedekatan / *Near*).

## Arsitektur & Alur Pemrosesan (*Pipeline*)

Modul ini dibangun menggunakan pola arsitektur MVVM (*Model-View-ViewModel*) dengan `SearchViewModel` sebagai pengendali *state* dan konduktor pencarian lintas platform.

```mermaid
flowchart TD
    MAC["OptionSearchVC & SearchSidebarVC (macOS)"] --> SVM["SearchViewModel (@Observable)"]
    IOS["SearchModeView & SearchComponents (iOS)"] --> SVM
    
    SVM ~~~ Core
    
    subgraph Core ["Core Engine & Database"]
        SE["SearchEngine (FTS Engine)"]
        LDM["LibraryDataManager (Book Tracking)"]
        BC[("BookConnection (SQLite Archives)")]
    end
    
    SVM -->|"Kirim Params Scope"| LDM
    SVM -->|"Eksekusi Kueri FTS"| SE
    SVM -->|"Ambil Konten Detail"| BC
    
    SE -->|"Streaming Hasil"| SVM

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class MAC,IOS ui;
    class SVM vm;
    class SE,LDM store;
    class BC db;
```

## Fitur Utama

- **Pencarian Konkuren:** Memanfaatkan `SearchEngine` dengan *multithreading* dan `Task.detached`.
- **Mode Pencarian:** Frasa utuh (*Exact Phrase*), Semua Kata (*AND / All Words*), Salah Satu Kata (*OR / Any Word*), dan Kedekatan (*Near Distance*).
- **Bookmarks (Saved Results):** Memulihkan dan menampilkan kembali hasil pencarian yang disimpan.
- **State Restoration:** Kemampuan memulihkan sesi pencarian terakhir secara otomatis.
