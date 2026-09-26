# Narrator (Rijāl)

Fitur **Narrator** (*Rijālul Hadīts*) dalam aplikasi Maktabah digunakan untuk menelusuri, mencari, dan membaca biografi para perawi hadis. Fitur ini memungkinkan pengguna untuk melihat detail perawi berdasarkan tingkatan (*Tabaqah*), serta mencari biografi (*Tarjamah*) secara global dari kitab-kitab biografi yang didukung.

## Arsitektur

Fitur Narrator dibangun menggunakan arsitektur MVVM (*Model-View-ViewModel*) yang memisahkan logika antarmuka pengguna dari logika pengelolaan data SQLite (baik untuk data referensi perawi maupun teks biografi di dalam arsip basis data).

```mermaid
flowchart TD
    subgraph UI ["Lapisan Presentasi UI"]
        Mac["macOS (RowiSidebarVC + RowiResultsVC)"]
        IOS["iOS (iOSRowiSidebarView + NarratorDetailView)"]
    end

    subgraph VM ["Lapisan ViewModel"]
        NVM["NarratorViewModel (@Observable)"]
    end

    Mac --> NVM
    IOS --> NVM

    subgraph Core ["Pengelola Data (Core)"]
        RDM["RowiDataManager"]
        TGM["TarjamahGlobalManager"]
    end

    NVM --> RDM
    NVM --> TGM
    
    RDM ~~~ DB_FILES
    TGM ~~~ DB_FILES
    
    subgraph DB_FILES ["Basis Data SQLite"]
        SPEC[("special.sqlite (Tabel rowa)")]
        ARCH[("Archives 1-20.sqlite (Teks Biografi)")]
        FTS[("special_fts.sqlite")]
    end
    
    RDM --> SPEC
    TGM --> SPEC
    TGM --> ARCH
    TGM --> FTS

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class Mac,IOS ui;
    class NVM vm;
    class RDM,TGM store;
    class SPEC,ARCH,FTS db;
```

### Komponen Utama

1. **Core & Database**: 
    - `RowiDataManager` mengelola kueri dari tabel `rowa` (data pokok perawi).
    - `TarjamahGlobalManager` mengelola pencarian teks penuh (FTS) dan biografi (`men_u`, `men_b`) secara konkuren.
2. **ViewModel**: 
    - `NarratorViewModel` bertanggung jawab menjaga status pencarian, status perawi yang dipilih, mode tampilan, dan sinkronisasi data antar-thread.
3. **UI (macOS / iOS)**: 
    - Menampilkan hierarki Tabaqah, hasil pencarian FTS, dan konten teks biografi.

## Daftar Dokumen Teknis

- [Database Layer](database.md): Akses ke `special.sqlite`, pembentukan `special_fts.sqlite`, dan *connection pool*.
- [Data Models](models.md): Model data perawi (`Rowi`), *tabaqah* (`TabaqaGroup`), dan biografi (`TarjamahResult`).
- [State Management (ViewModel)](viewmodel.md): Manajemen *state* reaktif dan *streaming pipeline* FTS perawi.
- [iOS Implementation](ios.md): Antarmuka *hierarchical collection* dan integrasi profil SwiftUI.
- [macOS Implementation](macos.md): Navigasi *sidebar* AppKit dan integrasi tampilan hasil biografi.
- [Protocols & Contracts](protocols.md): Kontrak delegasi antar-*controller*.
