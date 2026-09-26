# Maktabah Technical Documentation

Dokumentasi arsitektur dan teknis internal aplikasi **Maktabah** (macOS & iOS).

---

## Gambaran Arsitektur

Maktabah menggunakan arsitektur modular lintas platform berbasis Swift:

* **Platform UI**: macOS (AppKit) & iOS (SwiftUI + UIKit *bridge*)
* **Penyimpanan Lokal**: SQLite (`libsqlite3`) terkompresi Zstandard (`zstd`)
* **Sinkronisasi**: CloudKit Custom Zone (Private Database)
* **Pencarian**: SQLite FTS5 *concurrent worker pool*

### Siklus Hidup Aplikasi (*App Lifecycle & Entry Point*)

Alur inisialisasi (*pipeline*) aplikasi berjalan secara sistematis sebelum antarmuka pengguna ditampilkan:

```mermaid
flowchart TD
    Start(["Launch App"]) --> Mac["macOS: AppDelegate"]
    Start --> IOS["iOS: MaktabahApp (@main)"]
    
    Mac --> CheckDB{"Core SQLite Tersedia?"}
    IOS --> CheckDB
    
    CheckDB -->|"Tidak Ada / Usang"| Download["CoreDatabaseDownloader (Unduh & Ekstrak zstd)"]
    Download --> DB_FILES[("main.sqlite & special.sqlite")]
    
    CheckDB -->|"Tersedia"| DB_FILES
    DB_FILES --> Sync["CloudKitSyncManager (Fetch Data Latar Belakang)"]
    
    Sync ~~~ Split
    Sync ~~~ Main
    
    Split["macOS: SplitVC (Sidebar + Reader)"]
    Main["iOS: iOSMainView (TabView / iPadLayout)"]
    
    Sync --> Split
    Sync --> Main

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class Start event;
    class Mac,IOS,Split,Main ui;
    class CheckDB,Download,Sync store;
    class DB_FILES db;
```

1. **Titik Masuk Aplikasi (*Entry Point*)**: Aplikasi dijalankan melalui delegasi bawaan (*native*) (AppKit `AppDelegate` di macOS, atau SwiftUI `@main` di iOS).
2. **Pemeriksaan Basis Data Utama (*Core Database*)**: Sistem memvalidasi keberadaan berkas `main.sqlite` dan `special.sqlite` pada direktori *Application Support*.
3. **Pengunduhan & Ekstraksi**: Jika arsip belum tersedia (pengguna baru) atau versinya usang, `CoreDatabaseDownloader` akan mengunduh paket `.zst` dari GitHub Releases dan mengekstraknya seketika.
4. **Sinkronisasi CloudKit**: Menarik pembaruan data anotasi, riwayat, serta antrean sinkronisasi tertunda (*pending sync*) secara asinkron agar data tetap konsisten lintas perangkat.
5. **Penyajian Tampilan (*View Presentation*)**: Tahapan akhir berupa rendering antarmuka utama (`SplitVC` di macOS, `iOSMainView` di iOS) yang siap menerima interaksi pengguna.

---

## Struktur Dokumentasi

### 1. Memulai & Persiapan

* [Getting Started](getting-started.md)

### 2. Core Architecture

* [App Configuration](core/configuration.md)
* [CloudKit SyncEngine](core/cloudkit.md)
* [Database Management](core/database.md)
* [Search Engine](core/search-engine.md)
* [Text Processing](core/text-processing.md)
* [UI Core (iOS)](core/ios/mainview.md)
* [UI Core (macOS)](core/macos/splitvc.md)

### 3. Feature Modules

* [Annotations](features/annotations/index.md)
* [Bookmarks](features/bookmarks/index.md)
* [Global Architecture](features/index.md)
* [History](features/history/index.md)
* [Library & Catalog](features/library/index.md)
* [Narrator (Rijal)](features/narrator/index.md)
* [Quran & Tafsir](features/quran/index.md)
* [Reader Engine](features/reader/index.md)
* [Search](features/search/index.md)
* [Widgets](features/widget/index.md)

### 4. Troubleshooting

* [Debugging & Troubleshooting Guide](troubleshooting/index.md)
