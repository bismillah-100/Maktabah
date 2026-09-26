# Annotations - Overview & Architecture Pipeline

Dokumentasi ini membedah modul **Annotations** pada aplikasi Maktabah. Fitur ini menangani pembuatan, penyimpanan, dan sinkronisasi anotasi (*highlight*, *underline*, dan *notes*) pada teks kitab.

## Prinsip Pemisahan Tanggung Jawab (*Separation of Concerns*)

Modul Annotations dirancang dengan pemisahan lapisan yang ketat untuk memastikan skalabilitas dan kemudahan pemeliharaan:

1. **Model Layer (`Models/`)**
    Berisi representasi data murni (`Annotation`, `AnnotationNode`) yang mengadopsi `Sendable` dan terbebas dari dependensi UI atau basis data.

2. **Database & Storage Layer (`Database/`)**
    Mengelola persistensi data menggunakan SQLite (`AnnotationRepository`) dengan *caching in-memory* (`AnnotationStore`) yang *thread-safe* menggunakan `Synchronization.Mutex`. Lapisan ini juga mengoordinasikan sinkronisasi luring dan CloudKit.

3. **ViewModel Layer (`ViewModel/`)**
    Bertindak sebagai jembatan reaktif antara Storage dan UI. Menggunakan *framework* `Combine` dan `@Observable` (di `AnnotationViewModel`) untuk menyajikan *state* tampilan, serta menangani *debounce* dan operasi pencarian asinkron.

4. **Coordinator Layer (`Coordinator/`)**
    `AnnotationCoordinator` merangkum logika kalkulasi rentang (*range*) teks Arab (dengan dan tanpa harakat) antara UI Text View dan Core Engine.

5. **UI Layer (`macOS/` dan `iOS/`)**
    Menampilkan data dan menangani interaksi pengguna menggunakan AppKit (`NSViewController`, `NSOutlineView`) untuk macOS serta SwiftUI dan UIKit untuk iOS.

## Diagram Interaksi Komponen

Berikut adalah alur arsitektur dari lapisan antarmuka hingga ke penyimpanan:

```mermaid
flowchart TD
    UI_Mac[AppKit UI<br>AnnotationsVC, OutlineView] --> VM[AnnotationViewModel]
    UI_iOS[SwiftUI & UIKit UI<br>iOSAnnotationViewController] --> VM

    VM --> Tree[AnnotationTreeBuilder<br>Mutasi Hierarki & Diffing]
    Tree -.-> Publish([Publish Annotation Event])
    VM --> Store[AnnotationStore<br>In-Memory Cache & Mutex]

    UI_Mac -.-> Coord[AnnotationCoordinator]
    UI_iOS -.-> Coord

    Coord --> Calc[ArabicRangeCalculator]
    Coord --> Store

    Store --> Repo[AnnotationRepository<br>SQLite Database]
    Store --> Cloud[CloudKitSyncManager]

    Repo --> SQLite[(SQLite Annotations.sqlite)]

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class UI_Mac,UI_iOS ui;
    class VM vm;
    class Store,Tree,Coord store;
    class Repo,SQLite db;
    class Publish event;
```

## Daftar Tautan

- [AppKit Implementation (macOS)](macos.md)
- [Contracts & Loose Coupling](protocols.md)
- [Data Models & State Types](models.md)
- [Diacritics & Range Mapping](range-mapping.md)
- [Persistence, Cache & Concurrency](database.md)
- [State Management, Combine & Async Workflows](viewmodel.md)
- [SwiftUI & UIKit Integration (iOS)](ios.md)
- [Tree Builder & Data Hierarchy](tree-builder.md)
- [UI & Platform Integration](ui-integration.md)
