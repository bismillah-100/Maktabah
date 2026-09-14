# Overview & Architecture Pipeline

Dokumentasi ini membedah arsitektur fitur **History & Favorites** pada Maktabah. Fitur ini bertanggung jawab untuk melacak buku yang terakhir dibuka (history bacaan) beserta posisinya (`lastContentId`), serta daftar buku yang ditandai sebagai favorit oleh pengguna. Data ini disinkronkan secara mulus antar perangkat melalui CloudKit dan disimpan ke disk menggunakan SQLite.

## Diagram Arsitektur

Fitur History mengadopsi pola reaktif menggunakan `@Observable` dan memisahkan tanggung jawab antara *State Management*, *Persistensi Database*, dan *Sinkronisasi Cloud*.

```mermaid
graph TD
    %% UI Layer
    subgraph UI ["UI Layer (macOS & iOS)"]
        MAC["LibraryVC (macOS)"]
        IOS["iOSHistoryView (iOS)"]
    end

    %% State Management
    subgraph VM ["ViewModel Layer"]
        HVM["HistoryViewModel<br/>(@Observable)"]
    end

    %% Core Dependencies
    subgraph Core ["Core Engine & Database"]
        DB["HistoryDatabaseManager<br/>(SQLite Database)"]
        SYNC["CloudKitSyncManager<br/>(HistorySyncHandler)"]
        MD["DatabaseManager<br/>(BooksData Metadata)"]
    end

    %% Flow
    MAC -->|Observe & Action| HVM
    IOS -->|Observe & Action| HVM
    
    HVM -->|Upsert / Load| DB
    HVM -->|Sync CloudKit| SYNC
    HVM -->|Join Book Metadata| MD
    
    DB -->|Read/Write| SQLite[(History.sqlite)]
    SYNC <-->|Fetch/Upload| CloudKit((CloudKit Zone))
```

## Prinsip Pemisahan Tanggung Jawab

Modul ini dipecah ke dalam beberapa layer untuk memastikan *Separation of Concerns* (SoC):

1. **State Management (`HistoryViewModel`)**: Bertindak sebagai *single source of truth* di level memori/UI. Memegang status `entriesByBookId` dan menangani *debouncing* untuk mencegah *over-fetching* saat CloudKit melakukan perubahan beruntun.
2. **Storage Layer (`HistoryDatabaseManager`)**: Berkomunikasi langsung dengan SQLite (menggunakan `SQLiteDatabase`). Bertanggung jawab untuk eksekusi CRUD, manajemen koneksi WAL (*Write-Ahead Logging*), dan menampung *queue* sinkronisasi yang tertunda.
3. **Data Model (`ReadingEntry`)**: Membungkus seluruh properti metadata aktivitas bacaan. Dioptimalkan dengan *Codable* dan *Hashable*.
4. **CloudKit Sync (`SyncPendingManaging`)**: Database ini terintegrasi dengan `SyncPendingStore` bawaan Core untuk memastikan *offline-first sync*, di mana perubahan saat luring akan diantrekan dan dikirim saat daring.

## Daftar Dokumen Teknis

Berikut adalah pembedahan mendalam untuk setiap komponen di dalam *feature-slice* History:

* [AppKit Implementation (macOS)](macos.md)
* [Database & Storage (SQLite)](database.md)
* [Data Models & State Types](models.md)
* [Protocols & Contracts](protocols.md)
* [State Management (ViewModel)](viewmodel.md)
* [SwiftUI & UIKit Integration (iOS)](ios.md)
