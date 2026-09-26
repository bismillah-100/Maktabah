# TextView Core (macOS & iOS)

Dokumentasi teknis mendalam untuk implementasi *custom TextView* pada Maktabah (macOS & iOS), yang bertugas me-*render* teks Arab kompleks, menangani tasykil (harakat), mengelola sinkronisasi anotasi, dan mengoordinasikan *rendering* dengan antrean *task* mandiri.

---

## Alur Arsitektur (*Architecture Pipeline*)

Alur perenderan pada `TextView` melibatkan ViewModel, *cache* halaman, pemroses teks (*Core Engine*), penyimpanan lokal, dan pembungkus spesifik platform (AppKit / UIKit).

```mermaid
flowchart TD
    subgraph Core ["Core Text Processing & State"]
        VM["ReaderViewModel"] -->|"Fetch Page"| Cache[("BookPageCache (LRU)")]
        VM -->|"Fetch Anotasi"| AnnStore[("AnnotationStore")]
        VM -->|"Raw Content"| TR["ArabicTextRenderer"]
        State["TextViewState<br/>(Font, Harakat, LineHeight)"] -->|"Konfigurasi Style"| TR
        Calc["ArabicRangeCalculator<br/>(Display ↔ Source Mapping)"]
    end

    Core ~~~ Mac_Platform

    subgraph Mac_Platform ["macOS Platform (AppKit)"]
        MTV["IbarotTextView (NSTextView)"]
        CALFMac["CachedArabicLayoutFragment<br/>(CGLayer Offscreen Buffer)"]
        MenuMac["NSMenu Custom Context Menu"]
        MTV --> CALFMac
        MenuMac -.->|"Remap Range"| Calc
    end

    Mac_Platform ~~~ IOS_Platform

    subgraph IOS_Platform ["iOS Platform (UIKit & SwiftUI)"]
        IOSW["iOSIbarotTextView<br/>(SwiftUI UIViewRepresentable)"]
        ITV["iOSCustomIbarotTextView (UITextView)"]
        CALFIOS["CachedArabicLayoutFragment<br/>(TextKit 2 Buffer)"]
        MenuIOS["UIEditMenuInteraction & UIMenu"]
        IOSW -->|"Update UIView"| ITV
        ITV --> CALFIOS
        MenuIOS -.->|"Remap Range"| Calc
    end

    TR -->|"ArabicRenderResult"| MTV
    TR -->|"ArabicRenderResult"| IOSW

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class MTV,CALFMac,MenuMac,IOSW,ITV,CALFIOS,MenuIOS ui;
    class VM vm;
    class TR,Calc,State store;
    class Cache,AnnStore db;
```

---

## Penggunaan SerialTask (SerialTaskQueue) di dalam TextView

Pengelolaan konkurensi di `IbarotTextView` (khusus macOS) dikelola menggunakan `SerialTaskQueue`. *Class* ini memastikan *task-task* berat di *background thread* dieksekusi secara serial dan berurutan, guna menghindari *race condition* saat antarmuka me-*render* atau melompat ke lokasi teks tertentu.

Contoh penggunaan:

1. **Pemuatan Teks (`loadIbarotText`)**:
    Menyusun dan menerapkan teks Arab berukuran panjang memerlukan pemrosesan fonetis dan ligatur. Ketika pengguna berpindah halaman dengan cepat, *task* sebelumnya dapat dibatalkan (`taskQueue.cancelAll()`) dan digantikan oleh *rendering* halaman baru yang berjalan di antrean terpisah sebelum dikembalikan ke `@MainActor`.

2. **Pencarian & Anotasi (`highlightAndScrollToAnns`, `highlightAndScrollToText`)**:
    Operasi ini menunggu proses *layouting* dokumen selesai. Membungkus fungsi perenderan ke antrean serial menjamin bahwa *layoutManager* sudah tuntas menghitung metrik sebelum `scrollRangeToVisible(_:)` dipanggil.

---

## Penjelasan Detail Mengenai CachedArabicLayoutFragment

`CachedArabicLayoutFragment` adalah turunan spesifik dari `NSTextLayoutFragment` pada *framework* TextKit 2, yang difungsikan baik di platform AppKit (`IbarotTextView`) maupun UIKit (`iOSCustomIbarotTextView`).

Alur Kerja Utama:

- Mengambil alih proses `draw(at:in:)` dengan membuat *offscreen* `CGLayer` sebagai memori penyangga (*buffer*).
- Jika *layer* belum ada (karena teks baru di-*scroll* atau baru dimuat), sistem akan membuat konteks grafis mandiri, me-*render* paragraf di *layer* tersebut, kemudian menyimpannya ke memori *cache*.
- Untuk setiap *frame* berulang di lokasi layar yang sama (misalnya saat *scrolling* di paragraf sebelahnya tanpa mengubah paragraf bersangkutan), *fragment* hanya akan melakukan operasi *draw* berkecepatan tinggi dari `CGLayer` yang disimpan tanpa memicu ulang perenderan font/ligatur kompleks (seperti font KFGQPC Uthman Taha).
- Begitu terjadi seleksi (*highlight*), penyuntingan teks, atau perubahan warna, metode `invalidateLayout()` otomatis dipanggil untuk menyetel nilai `cachedLayer = nil`, memaksa siklus pembuatan *cache* diulang.

---

## Manipulasi Anotasi

Manipulasi anotasi membutuhkan konversi indeks rentang (*range mapping*) yang tepat antara *string* sumber asli (basis data) dan *string* yang dimodifikasi oleh `ArabicTextRenderer` (yang menghapus tag HTML, membersihkan tasykil, atau merender ligatur).

Proses Manipulasi:

1. **Pemetaan Rentang (Range Mapping)**:
    Saat anotasi diambil dari `AnnotationStore`, model memiliki properti `range` dan `rangeDiacritics`. Bergantung pada status aktif harakat (dari `TextViewState.shared.showHarakat`), rentang yang sesuai dipetakan ulang melalui `ArabicRenderResult.remapDisplayedRange(_:)`.

2. **Penerapan Atribut Dasar**:
    Fungsi internal menerapkan `NSAttributedString.Key.backgroundColor` (untuk *Highlight*) atau `.underlineStyle` (untuk *Underline*) pada ruang indeks yang telah dipetakan tersebut.

3. **Penyematan Metadata Tautan (Link & Annotation ID)**:
    Apabila anotasi dikonfigurasi untuk dapat diklik (berdasarkan preferensi `clickableAnnotation`), rentang anotasi disuntikkan atribut `.link` dengan URL kustom (`annotation://{id}`) serta disematkan atribut khusus `annotationID`.

---

## Menu Kontekstual (iOS / macOS)

Menu interaksi dikustomisasi untuk membatasi opsi bawaan yang tidak relevan dengan pengalaman teks RTL serta menyuntikkan menu pengelolaan *Highlight* dan *Note*.

=== "macOS"
    Di AppKit, menu utama ditangani melalui *override* `menu(for event: NSEvent) -> NSMenu?`.

    - Membuang opsi *Substitution*, *Speaking*, atau operasi mutasi (*Cut*, *Paste*) karena teks bersifat *read-only*.
    - Menambahkan baris menu warna yang direpresentasikan melalui *View* khusus (`AnnotationColorMenuView`).
    - Menu mendeteksi apakah indeks karakter di bawah kursor (dihitung menggunakan koordinat kursor dan `textLayoutManager`) memiliki anotasi (dengan mengambil nilai `annotationID`).
    - Jika ada, menu *Edit Note* dan *Delete* ditambahkan. Jika belum, dimunculkan menu *Add Note*.
    - Menyediakan fitur salin rujukan (*Copy with Reference*) khusus.

=== "iOS"
    Di UIKit (iOS 16+), pembuatan menu berpusat di delegasi `editMenuForTextIn` dari `UITextViewDelegate`.

    - Menu menerima sekumpulan `suggestedActions` dan menambahkan opsi melalui objek `UIMenu`.
    - Daftar warna *highlight* yang terakhir dipakai diambil (sebanyak batas maksimal `maxRecentColors`) lalu diwujudkan sebagai daftar opsi `UIAction`.
    - Menu `UIAction` juga disuntikkan untuk melakukan *Share with Reference* menggunakan antarmuka `UIActivityViewController` dengan mengambil `sourceText` yang telah dipetakan kembali dari komponen layar ke rentang asli basis data.

---

## Bedah Struct, Class, dan Enum

Berikut adalah struktur kode inti untuk manipulasi ViewModel, Status Pembacaan, dan Pemrosesan Teks Arab.

### 1. Annotation (Struct) - Model Anotasi

Menyimpan data penuh anotasi beserta konteksnya untuk diterapkan ke `NSAttributedString`.

```swift
struct Annotation: Sendable {
    var id: Int64? // (1)!
    let bkId: Int // (2)!
    let contentId: Int // (3)!
    var range: NSRange // (4)!
    let rangeDiacritics: NSRange // (5)!
    var colorHex: String // (6)!
    var type: AnnotationMode // (7)!
    var note: String? // (8)!
    let createdAt: Int64
    let context: String
    let page: Int
    let part: Int
    var pageArb: String?
    var partArb: String?
    var tags: [String] = []

    // CloudKit Sync Support
    var ckRecordId: String?
    var lastModified: Int64?
}
```

1. Nilai `nil` menandakan bahwa objek ini baru dan belum pernah disimpan ke database.
2. Menyimpan ID Buku.
3. ID halaman atau baris dari tabel konten (`BookContent`).
4. Rentang *NSRange* berdasarkan teks asli tanpa harakat (Gundul).
5. Rentang *NSRange* berdasarkan teks dengan harakat utuh.
6. Direpresentasikan dalam format HEX, misalnya `#FFCC00`.
7. Jenis anotasi, *highlight* atau *underline*.
8. Teks catatan khusus tambahan dari pengguna (opsional).

### 2. AnnotationMode (Enum) - Status Mode Anotasi

Mengindikasikan model penerapan grafis untuk anotasi (*Highlight* / *Underline*).

```swift
enum AnnotationMode: Int, Sendable {
    case highlight
    case underline

    static func from(int: Int) -> AnnotationMode {
        switch int {
        case 0: highlight
        case 1: underline
        default: highlight
        }
    }
}
```

### 3. ArabicRenderResult (Struct) - Pengolahan Data Layar

*Struct* yang dikembalikan oleh perender (`ArabicTextRenderer`) kepada TextView. Melalui tipe ini, `TextView` dapat membedakan teks sumber di basis data dan teks grafis yang sudah dibersihkan.

```swift
struct ArabicRenderResult {
    let sourceText: String // (1)!
    let attributedString: NSAttributedString // (2)!
    let replacementEvents: [HonorificReplacementEvent] // (3)!
    let footnoteRanges: [NSRange] // (4)!

    func remapDisplayedRange(_ range: NSRange) -> NSRange { /* ... */ }
    func remapSourceRange(_ range: NSRange) -> NSRange { /* ... */ }
}
```

1. Teks sumber murni (*string* asli sebelum format teks disesuaikan).
2. Objek grafis teks terformat (sudah dibersihkan, diwarnai, dan ligatur ditangani).
3. Daftar *events* penggantian (contoh: teks "رحمه الله" yang disederhanakan menjadi satu glif ligatur font Arab tunggal, mengurangi panjang *string* layar).
4. Pemetaan lokasi catatan kaki jika dokumen memilikinya, untuk format ukuran font yang lebih kecil.

### 4. ViewModelState (Enum)

Didefinisikan dalam modul *Protocols* sebagai standar pengukur aktivitas pemuatan pada seluruh `ViewModel`.

```swift
public enum ViewModelState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}
```

```mermaid
stateDiagram-v2
    [*] --> idle: Inisialisasi
    idle --> loading: Request Load Halaman
    loading --> loaded: Sukses Merender Teks
    loading --> error: Gagal Membaca DB / Cache
    error --> loading: Retry Muat Ulang
    loaded --> loading: Navigasi Halaman Baru
```

### 5. TextViewState (Class) - Status TextView Global

Manajer pusat dari preferensi tipografi pembacaan (*Line Height*, *Font Size*, Mode Gelap, Harakat Aktif) yang menyinkronkan status *UserDefaults* dengan *Observer* (`@Observable`).

```swift
@Observable
class TextViewState: @unchecked Sendable {
    static let shared = TextViewState()

    private(set) var showHarakat: Bool { ... }
    private(set) var lineHeight: Double { ... }
    private(set) var fontSize: CGFloat { ... }
    private(set) var fontName: String { ... }
    private(set) var backgroundColorIndex: Int { ... }
    private(set) var clickableAnnotation: Bool { ... }

    var backgroundColor: BackgroundColor { BackgroundColor(rawValue: backgroundColorIndex) ?? .white }
    var isDarkMode: Bool { backgroundColor.isDark }
    var currentFont: PlatformFont { ... }
    var paragraphStyle: NSParagraphStyle { ... }
    var defaultAttributes: [NSAttributedString.Key: Any] { ... }

    func toggleHarakat() { ... }
    func setLineHeight(_ newHeight: Double) { ... }
    func setBackgroundColorIndex(_ index: Int) { ... }
    func setBackgroundColor(_ color: BackgroundColor) { ... }
    func pushRecentHighlightColor(_ color: PlatformColor) { ... }
}
```

### 6. ReaderViewModel (Class) - Pengelola Data Pembacaan

Penghubung (*Mediator*) utama dalam lapisan UI Maktabah yang menghubungkan basis data dokumen buku yang sedang dibuka dengan antarmuka pembacaan.

```swift
@Observable
class ReaderViewModel: ViewModelBase {
    var currentBook: BooksData?
    var currentPage: Int?
    var currentPart: Int?
    var currentContentId: Int = 0
    var recordHistory: Bool = true

    var contentText: String = ""
    var state: ViewModelState = .idle

    // Dependensi Eksternal
    let bookConnectionMutex = Mutex(BookConnection())
    let historyVM: HistoryViewModel = .shared
    let annotationStore: AnnotationStore = .shared

    // Status Sinkronisasi Eksternal
    var currentBookContent: BookContent? { ... }
    var diacriticsText: String { ... }

    // Fungsi Utama Pembaruan
    func updateContentState(with content: BookContent) {
        // - Menyimpan posisi teks
        // - Merekam riwayat baru (HistoryViewModel)
        // - Memuat Anotasi ke memori (AnnotationStore)
        // - Mengirimkan notifikasi perubahan antar UI Platform (macOS / iOS)
    }
}
```
