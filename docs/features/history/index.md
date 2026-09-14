# Overview & Architecture Pipeline

Dokumentasi ini membedah arsitektur fitur **History & Favorites** pada Maktabah. Fitur ini bertanggung jawab untuk melacak buku yang terakhir dibuka (riwayat bacaan) beserta posisinya (`lastContentId`), serta daftar buku yang ditandai sebagai favorit oleh pengguna. Data ini disinkronkan secara mulus antarperangkat melalui CloudKit dan disimpan ke disk menggunakan SQLite.

## Diagram Arsitektur

Fitur History mengadopsi pola reaktif menggunakan `@Observable` dan memisahkan tanggung jawab antara *State Management*, *Persistensi Database*, dan *Sinkronisasi Cloud*.

```mermaid
flowchart TD
    MAC["LibraryVC (macOS)"] --> HVM["HistoryViewModel (@Observable)"]
    IOS["iOSHistoryView (iOS)"] --> HVM
    
    HVM ~~~ Core
    
    subgraph Core ["Core Engine & Database"]
        DB["HistoryDatabaseManager"]
        SYNC["CloudKitSyncManager (HistorySyncHandler)"]
        MD["DatabaseManager (BooksData Metadata)"]
    end
    
    HVM -->|"Upsert / Load"| DB
    HVM -->|"Sync CloudKit"| SYNC
    HVM -->|"Join Book Metadata"| MD
    
    DB --> SQLite[("History.sqlite (WAL Mode)")]
    SYNC <-->|"Fetch / Upload"| CloudKit[("CloudKit Private Zone")]

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class MAC,IOS ui;
    class HVM vm;
    class DB,SYNC,MD store;
    class SQLite,CloudKit db;
```

## Prinsip Pemisahan Tanggung Jawab

Modul ini dipecah ke dalam beberapa *layer* untuk memastikan *Separation of Concerns* (SoC):

1. **State Management (`HistoryViewModel`)**: Bertindak sebagai *single source of truth* di level memori/UI. Memegang status `entriesByBookId` dan menangani *debouncing* untuk mencegah *over-fetching* saat CloudKit melakukan perubahan beruntun.
2. **Storage Layer (`HistoryDatabaseManager`)**: Berkomunikasi langsung dengan SQLite (menggunakan `SQLiteDatabase`). Bertanggung jawab untuk eksekusi CRUD, manajemen koneksi WAL (*Write-Ahead Logging*), dan menampung *queue* sinkronisasi yang tertunda.
3. **Data Model (`ReadingEntry`)**: Membungkus seluruh properti metadata aktivitas bacaan. Dioptimalkan dengan `Codable` dan `Hashable`.
4. **CloudKit Sync (`SyncPendingManaging`)**: Database ini terintegrasi dengan `SyncPendingStore` bawaan Core untuk memastikan *offline-first sync*, di mana perubahan saat luring (*offline*) akan diantrekan dan dikirim saat daring (*online*).

## Daftar Dokumen Teknis

Berikut adalah pembedahan mendalam untuk setiap komponen di dalam *feature-slice* History:

* [AppKit Implementation (macOS)](macos.md)
* [Database & Storage (SQLite)](database.md)
* [Data Models & State Types](models.md)
* [Protocols & Contracts](protocols.md)
* [State Management (ViewModel)](viewmodel.md)
* [SwiftUI & UIKit Integration (iOS)](ios.md)
