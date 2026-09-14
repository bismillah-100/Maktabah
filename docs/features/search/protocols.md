# Protocols & Contracts

Arsitektur pencarian Maktabah menghubungkan antarmuka presentasi (macOS AppKit dan iOS SwiftUI) dengan mesin eksekusi FTS melalui sekumpulan *protocol* delegasi dan kontrak *callback* konkuren berstatus `Sendable`.

---

## 1. Arsitektur Kontrak Delegasi & Callback

Berikut adalah pembagian peran antarmuka antara lapisan UI, ViewModel, dan Search Engine:

```mermaid
graph TD
    subgraph PresentationContracts ["Presentation Delegates (MainActor)"]
        OSD["&laquo;protocol&raquo;<br/>OptionSearchDelegate"]
        IOSCB["iOS Result Callback<br/>(Book, ContentId) -&gt; Void"]
    end

    subgraph CoreEngineContracts ["Core Engine Contracts (Sendable)"]
        SC["SearchControl<br/>(PauseController, stopFlag)"]
        SWCB["SearchWorkerCallbacks<br/>(start, progress, onResult, onComplete)"]
        CR["&laquo;protocol&raquo;<br/>CopyableResult"]
    end

    subgraph ExecutionBridge ["Execution & Coordination"]
        SVM["SearchViewModel"]
        ENGINE["SearchEngine"]
    end

    SVM -->|"Conforms / Implements"| OSD
    SVM -->|"Passes Callbacks"| SWCB
    SVM -->|"Manages Control"| SC
    ENGINE -->|"Streams Results via"| SWCB
    SWCB -->|"Instantiates Items conforming to"| CR
    OSD -.->|"Navigates Reader"| IOSCB

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class OSD,IOSCB ui;
    class SVM vm;
    class SC,SWCB,CR store;
    class ENGINE db;
```

---

## 2. Antarmuka Presentasi

### `OptionSearchDelegate` (Protocol) - macOS
*Protocol* ini diisolasi ke dalam *Main Thread* (`@MainActor`) dan diimplementasikan oleh *controller* pengelola jendela (seperti `SplitVC` atau `SearchSidebarVC`):

```swift
@MainActor
protocol OptionSearchDelegate: AnyObject {
    func didSelectResult(
        for id: Int,
        highlightText: String,
        mode: SearchMode?,
        nearDistance: Int
    ) async
}
```

- **`id`**: Pengenal baris halaman kitab (`contentId`).
- **`highlightText`**: Kueri teks kata kunci yang disorot (*highlighting*) saat pembaca teks (`IbarotTextVC`) dibuka.
- **`mode` & `nearDistance`**: Parameter mode pencarian (`.allWords`, `.anyWord`, `.exactPhrase`, `.near`) yang menentukan kalkulasi toleransi penyorotan kata majemuk atau berjarak dekat.

### Callback Presentasi (iOS)
Pada iOS, navigasi hasil pencarian memanfaatkan *closure* interaksi:
- `onResultTap: (Int, Int) -> Void`: Mentranslasikan ketukan pada baris `SearchResultsListView` menjadi pemanggilan `iOSNavigationManager.openBook(book, initialContentId: contentId)`.

---

## 3. Kontrak Eksekusi Engine (`Sendable`)

Komunikasi antara `SearchEngine` dan *thread* latar belakang diatur melalui *struct* kontrak yang mematuhi batasan model konkurensi Swift:

### `SearchControl` (Struct)
Mengontrol jalannya pencarian secara asinkron tanpa *race condition*:
```swift
struct SearchControl: Sendable {
    let pauseController: PauseController
    let stopFlag: @Sendable () -> Bool
}
```
- **`pauseController`**: Mengelola status jeda/lanjutkan saat pengguna beralih tugas atau membatasi penggunaan CPU.
- **`stopFlag`**: Predikat *thread-safe* untuk menghentikan putaran *worker loop* secara instan ketika pengguna membatalkan pencarian atau mengetik kueri baru.

### `SearchWorkerCallbacks` (Struct)
Pipeline penerima hasil (*streaming pipeline*) dari *worker* FTS:
```swift
struct SearchWorkerCallbacks: Sendable {
    let start: @Sendable (Int) -> Void
    let progress: @Sendable (Int) -> Void
    let onRowProgress: @Sendable (String, Int, Int) -> Void
    let onResult: @Sendable (String, BookContent) -> Void
    let onTableComplete: @Sendable () -> Void
    let onComplete: @Sendable () -> Void
}
```
- **`onResult`**: Dipanggil setiap kali sebaris konten kitab yang cocok selesai didekompresi, memungkinkan UI memperbarui daftar hasil secara progresif tanpa menunggu seluruh basis data selesai dipindai.

---

## 4. Abstraksi Data & Utilitas

### `CopyableResult` (Protocol)
*Protocol* yang menyeragamkan fungsionalitas penyalinan teks (*clipboard copy*) dari berbagai bentuk hasil:
- Memastikan item dapat menghasilkan format sitasi rujukan lengkap (berisi nama kitab, juz, nomor halaman, dan kutipan teks Arab).
- Diadopsi oleh hasil pencarian reguler, hasil pencarian perawi/hadis, maupun riwayat pencarian yang disimpan.
