# Arsitektur Global Feature-Slice Maktabah

Dokumen ini menjelaskan struktur arsitektur **Feature-Sliced Design** yang diterapkan pada Maktabah (macOS & iOS), hubungan antarlapisan (*layering*), serta bagaimana modul fitur berkomunikasi dengan lapisan inti (*Core*).

---

## 1. Lapisan Arsitektur (*Layering Hierarchy*)

Kode sumber Maktabah dibagi menjadi tiga lapisan utama yang memiliki aturan ketergantungan satu arah (*unidirectional dependency*):

```text
┌─────────────────────────────────────────────────────────┐
│                    UI Shells                            │
│   • macOS: AppKit Windows, SplitVC, Toolbar, NSTextView │
│   • iOS: SwiftUI App, iPadLayout, UIViewControllerBridge│
│   • Extensions: WidgetKit Timeline Providers            │
└────────────────────────────┬────────────────────────────┘
                             │ (mengonsumsi)
┌────────────────────────────▼────────────────────────────┐
│                  Features (Slices)                      │
│   • Annotations  • Bookmarks  • History  • Library      │
│   • Narrator     • Quran      • Reader   • Search       │
│   • Setting                                             │
└────────────────────────────┬────────────────────────────┘
                             │ (bergantung pada)
┌────────────────────────────▼────────────────────────────┐
│                  Core Engine Layer                      │
│   • Database (SQLite wrapper, zstd, BookConnection)     │
│   • SearchEngine (FTS5 Worker Pool, Query Parser)       │
│   • TextProcessing (Arabic typography, harakat mapping) │
│   • CloudKit (Sync Manager, Zone Coordinator)           │
│   • Configuration & Network (AppConfig, ArabicFont)     │
└─────────────────────────────────────────────────────────┘
```

### Aturan Ketergantungan:

1. **Lapisan Core** tidak boleh mengimpor atau bergantung pada modul di lapisan *Features* atau *UI*.
2. **Antar-Fitur (*Cross-Feature*)** tidak boleh saling mengimpor secara langsung. Komunikasi antar-fitur wajib melalui:
    * ***Protocol* / Delegate** (contoh: `AnnotationDelegate` untuk melompat ke pembaca di `Reader`).
    * **Notification / Combine Stream** (contoh: `AnnotationEvent`, `HistoryUpdateEvent`).
    * **Koordinator Sentral** (`AppCoordinator`, `LibraryDataManager`).

---

## 2. Struktur Internal Feature Slice

Setiap folder di dalam `Source/Features/<FeatureName>/` merupakan *slice* modular mandiri yang memiliki struktur seragam:

```text
Source/Features/<FeatureName>/
├── Models/        # Struct data immutable (Sendable), Enum, dan String Catalog (.xcstrings)
├── Protocols/     # Interface kontrak & delegation untuk loose-coupling
├── ViewModel/     # State management, transformasi data, dan Combine bindings
├── Database/      # Logika persistensi lokal, repository, dan kueri spesifik fitur
├── macOS/         # Implementasi view native AppKit (ViewControllers, Outlines, Popovers)
└── iOS/           # Implementasi view SwiftUI dan UIViewControllerRepresentable bridges
```

### Modular String Catalogs (.xcstrings)
Aplikasi memisahkan tabel lokalisasi ke dalam katalog terdistribusi per-fitur guna menjaga skalabilitas dan menghindari bentrokan:
- `Source/Features/Setting/Setting.xcstrings`: Terjemahan preferensi sistem, mode penyimpanan, dan pembaruan (`.Setting.*`).
- `Source/Features/Library/Models/Library.xcstrings`: Terjemahan unduhan buku, metadata, dan dialog impor (`.Library.*`).
- `Source/Features/Annotations/Models/Annotation.xcstrings`: Terjemahan aksi anotasi, penandaan, dan pengelolaan tag (`.Annotation.*`).
- `Source/Features/Widget/Localizable.xcstrings`: Lokalisasi khusus *Widget Extension*.
- `Source/Localizable.xcstrings`: String umum dan navigasi global lintas antarmuka.

---

## 3. Peta Fitur Utama (*Feature Slices Overview*)

```mermaid
flowchart TD
    APP["App Shell (macOS SplitVC / iOS iOSMainView)"]
    
    APP --> LIB["Library Feature"]
    APP --> RDR["Reader Feature"]
    APP --> SRC["Search Feature"]
    APP --> NAR["Narrator Feature"]
    
    LIB ~~~ ANN
    RDR ~~~ BKM
    SRC ~~~ HIS
    NAR ~~~ SET
    
    APP --> ANN["Annotations Feature"]
    APP --> BKM["Bookmarks Feature"]
    APP --> HIS["History Feature"]
    APP --> SET["Setting Feature"]
    APP --> QUR["Quran & Widget"]
    
    ANN ~~~ CORE_DB
    BKM ~~~ CORE_DB
    HIS ~~~ CORE_DB
    
    CORE_DB[("Core SQLite (main / special / archives)")]
    SYNC["CloudKitSyncManager"]
    
    LIB --> CORE_DB
    RDR --> CORE_DB
    SRC --> CORE_DB
    NAR --> CORE_DB
    ANN --> SYNC
    BKM --> SYNC
    HIS --> SYNC

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class APP,LIB,RDR,SRC,NAR,ANN,BKM,HIS,SET,QUR ui;
    class SYNC store;
    class CORE_DB db;
```

| Feature Slice | Domain & Tanggung Jawab Utama | Ketergantungan Core Kunci |
| :--- | :--- | :--- |
| **Annotations** | Sorotan (*highlight*), garis bawah berwarna (*underline*), catatan, dan penandaan label (*tagging*). | `ArabicRangeCalculator`, `CloudKitSyncManager`, `Mutex` |
| **Bookmarks** | Penanda halaman dan pengorganisasian folder hasil pencarian favorit. | `ResultsHandler`, `CloudKitSyncManager` |
| **History** | Pelacakan riwayat bacaan kitab, sesi waktu membaca, dan pembukaan kembali posisi terakhir. | `HistoryDatabaseManager`, `ScreenTimeManager` |
| **Library** | Katalog buku, kategori, manajer pengunduhan, dekompresi arsip, pembaruan buku. | `DatabaseManager`, `ZstdDecompressor`, `BookDownloadManager` |
| **Narrator** | Eksplorasi biografi perawi hadis (*rijalul hadits*) dan relasi sanad. | `RowiDataManager`, `TarjamahDataManager`, `SQLiteDatabase` |
| **Quran** | Penjelajah ayat Al-Qur'an, navigasi surah/juz, dan tafsir terintegrasi. | `QuranDataManager`, `ArabicTextRenderer` |
| **Reader** | Penampil teks kitab, penomoran halaman, pengguliran berkelanjutan, dan tipografi Arab. | `TextProcessing`, `BookConnection`, `BookPageCache` |
| **Search** | Antarmuka pencarian cepat teks penuh lintas puluhan ribu kitab. | `SearchEngine` (FTS5 Pool), `FtsQueryParser` |
| **Setting** | Preferensi aplikasi, pemilihan folder pustaka/anotasi, sakelar CloudKit, dan pemeriksaan pembaruan. | `AppConfig`, `AppUpdate`, `CloudKitSyncManager` |
| **Widget** | Menampilkan kutipan, catatan harian, dan ringkasan bacaan pada Lock Screen / Home Screen. | `WidgetUpdateCoordinator`, Shared App Group Storage |

---

## 4. Alur Komunikasi Antarkomponen

Contoh alur terintegrasi saat pengguna berinteraksi dari **Sidebar Anotasi** menuju ke **Reader**:

```mermaid
sequenceDiagram
    autonumber
    actor User as Pengguna
    participant Sidebar as Annotations Outline
    participant Del as AnnotationDelegate
    participant Reader as IbarotTextVC

    User->>Sidebar: Klik baris anotasi
    Sidebar->>Del: didSelect(annotation: ann)
    Del->>+Reader: Task { openAnnotation(ann) }
    Reader->>Reader: pendingRestoreTask?.cancel()
    Note over Reader: Validasi buku via LibraryDataManager
    opt Jika buku berbeda (currentBook?.id != bkId)
        Reader->>Reader: displayBook(book, loadContent: false)
    end
    opt Jika contentId berbeda
        Reader->>Reader: handleDelegate(contentId)
    end
    Reader->>Reader: textDelegate.highlightAndScrollToAnns(ann)
    deactivate Reader
```

---

## 5. Keuntungan Arsitektur Ini

* **Lintas Platform Bersih**: Logika bisnis (Model, ViewModel, Database) 100% dibagikan antara macOS dan iOS tanpa duplikasi kode.
* **Isolasi Masalah**: Masalah atau perubahan skema pada modul *Narrator* tidak akan berdampak pada modul *Annotations* atau *Reader*.
* **Skalabilitas**: Menambah fitur baru (misalnya modul *Kamus/Mu'jam*) cukup dengan membuat satu folder *slice* baru di `Source/Features/` tanpa merombak modul yang sudah stabil.
