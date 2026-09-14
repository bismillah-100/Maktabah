# Widget

## Ringkasan
Fitur Widget pada Maktabah menyediakan akses cepat ke konten spesifik langsung dari *Home Screen*, *Lock Screen*, atau *Notification Center* perangkat pengguna. Terdapat dua widget utama:

1. **Annotation Widget**: Menampilkan anotasi (sorotan teks dan catatan) terbaru.
2. **History Widget**: Menampilkan buku-buku yang terakhir kali dibaca.

Widget dibangun menggunakan SwiftUI dan WidgetKit, serta mengandalkan sinkronisasi data independen berbasis *Snapshot* (tanpa mengakses basis data utama secara langsung).

## Arsitektur Pipeline

Alur kerja widget melibatkan penyediaan *snapshot* mandiri yang disinkronkan melalui App Group secara lokal dan ditarik dari CloudKit bila tersedia.

```mermaid
flowchart TD
    V["Widget View (SwiftUI / WidgetKit)"]
    
    AP["AnnotationProvider (TimelineProvider)"]
    HP["HistoryProvider (TimelineProvider)"]
    
    V -->|"Render Timeline"| AP
    V -->|"Render Timeline"| HP
    
    AP ~~~ CF
    HP ~~~ CF
    
    CF["CloudKitFetcher"]
    WSR["WidgetSnapshotRecord (Snapshot Resolver)"]
    
    AP -->|"Fetch Snapshot"| CF
    HP -->|"Fetch Snapshot"| CF
    CF -->|"Read / Resolve"| WSR
    
    WSR ~~~ STORES
    
    subgraph STORES ["Data Source & Storage"]
        CK[("CloudKit Database (Remote 6s Timeout)")]
        AG[("App Group JSON (Local Snapshot Cache)")]
    end
    
    WSR -.->|"Remote Fetch"| CK
    WSR -.->|"Fallback / Cache"| AG

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class V ui;
    class AP,HP,CF,WSR store;
    class CK,AG db;
```

## Sub-Komponen Dokumentasi

- **[Data Models & Snapshots](models.md)**: Model *snapshot* terisolasi (`AnnotationSnapshot`, `HistorySnapshot`).
- **[State Management & Coordination](viewmodel.md)**: Mekanisme `WidgetUpdateCoordinator` dan siklus hidup `TimelineProvider`.
- **[Database & App Group Persistence](database.md)**: Penyimpanan berkas JSON App Group dengan `NSFileCoordinator`.
- **[iOS Integration](ios.md)**: Penanganan *deep link* dan penempatan widget di iOS.
- **[macOS Integration](macos.md)**: Adaptasi widget desktop macOS dan delegasi URL *event*.
- **[Protocols & Contracts](protocols.md)**: Kontrak `WidgetSnapshotRecord` dan `AppIntentTimelineProvider`.
