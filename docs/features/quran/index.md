# Quran & Tafsir

Fitur **Quran** menyediakan kemampuan membaca mushaf Al-Qur'an beserta kitab-kitab tafsirnya. Fitur ini memanfaatkan `QuranDataManager` untuk memuat data Al-Qur'an (Surah dan Ayat) dari basis data khusus serta mencocokkannya dengan kitab-kitab tafsir yang tersedia di perpustakaan Maktabah.

## Alur Arsitektur (*Architecture Pipeline*)

```mermaid
flowchart TD
    SPLIT["QuranSplitVC (NSSplitViewController)"]
    
    SIDE["QuranSidebarVC (Daftar Surah & Ayat)"]
    NASH["QuranNashVC (Mushaf / Nash Quran)"]
    TAFSEER["QuranTafseerVC (Daftar Kitab Tafsir)"]
    
    SPLIT --> SIDE
    SPLIT --> NASH
    SPLIT --> TAFSEER
    
    SIDE ~~~ DEL
    NASH ~~~ DEL
    
    SIDE -->|"didSelectAya"| DEL["QuranDelegate"]
    DEL --> NASH
    
    TAFSEER -->|"didSelectBook"| SPLIT
    SPLIT -->|"loadTafseer"| NASH

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;

    class SPLIT,SIDE,NASH,TAFSEER ui;
    class DEL store;
```

## Sub-Komponen Dokumentasi

- **[Database Layer](database.md)**: Pengelolaan `special.sqlite` (tabel `Qr` dan `Sora`) serta integrasi kitab tafsir.
- **[Data Models](models.md)**: Struktur data ayat (`Quran`) dan surah (`SurahNode`).
- **[State Management](viewmodel.md)**: Koordinasi *state* berbasis *Data Manager* dan *delegation*.
- **[macOS Implementation](macos.md)**: Implementasi AppKit dengan *three-pane* `NSSplitView`.
- **[iOS Implementation](ios.md)**: Status implementasi pada platform iOS.
- **[Protocols & Contracts](protocols.md)**: Kontrak `QuranDelegate` untuk sinkronisasi antarmuka.
