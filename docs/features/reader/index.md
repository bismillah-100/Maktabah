## Gambaran Umum (Overview)

Fitur *Reader Engine* merupakan modul inti (*core*) aplikasi Maktabah yang bertugas menangani *rendering* teks Arab berskala besar, proses *pagination*, dan *continuous scroll* secara efisien. Komponen ini disusun dalam arsitektur MVVM (*Model-View-ViewModel*) yang modular untuk mendukung implementasi lintas platform (macOS dan iOS).

```mermaid
flowchart TD
    UI_iOS["iOS: iOSReaderView & iOSIbarotTextView"] --> VM["ReaderViewModel (@Observable)"]
    UI_macOS["macOS: IbarotTextVC & IbarotTextView"] --> VM
    
    VM ~~~ Cache
    
    Cache["BookPageCache (LRU In-Memory)"]
    VM --> Cache
    
    Cache -->|"Cache Miss"| DB[("BookConnection (SQLite b{id})")]
    DB --> LZString["LZString (Decompressor)"]
    LZString --> Renderer["ArabicTextRenderer (Typography)"]
    Renderer --> VM

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class UI_iOS,UI_macOS ui;
    class VM vm;
    class Cache,LZString,Renderer store;
    class DB db;
```

## Struktur Modul

Modul ini dibagi menjadi beberapa subkomponen utama yang didokumentasikan secara terpisah:

- [Cache](cache.md): Mekanisme *caching in-memory* berbasis *LRU cache*.
- [Data Models](models.md): Model konten kitab, tipografi hasil pemrosesan, daftar isi (TOC), dan *state reader*.
- [iOS Implementation](ios.md): Implementasi antarmuka pengguna khusus iOS.
- [macOS Implementation](macos.md): Implementasi antarmuka pengguna khusus macOS.
- [Protocols](protocols.md): Abstraksi antarmuka (*protocols/interfaces*).
- [Selection & Context Menu](menu.md): Pencegatan pembuatan anotasi duplikat dan aksi menu seleksi teks.
- [TextView (macOS & iOS)](textview.md): Implementasi kustom *text view rendering engine*.
- [ViewModel](viewmodel.md): Pengontrol logika bisnis dan alur reaktivitas utama.

## Prasyarat & Dependensi (Prerequisites)

> Modul ini bergantung pada `SQLiteDatabase` untuk akses data dan utilitas kompresi `LZString`.

- **Platform**: macOS 15+ (AppKit), iOS 16+ (SwiftUI + UIKit).
- **Dependensi Internal**: `TextViewState` (pengelolaan preferensi visual font dan harakat), `ArabicRangeCalculator` (sinkronisasi pemetaan rentang teks sumber dan teks tampilan).
