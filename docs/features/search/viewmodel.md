# State Management

Manajemen *state* di modul Search ditangani oleh `SearchViewModel`, yang dioptimalkan dengan makro `@Observable` (Swift 5.9+) untuk integrasi reaktif dengan antarmuka SwiftUI maupun *binding* data ke UIKit dan AppKit (melalui Combine atau Observation).

## Komponen `SearchViewModel`

ViewModel ini mengoordinasikan antrean *multithread* dari `SearchEngine`, menyangga hasil melalui `SearchResultBuffer`, dan menyiapkannya untuk dikonsumsi oleh lapisan presentasi (UI) secara *lazy* menggunakan `SearchHitResolver`.

### State Utama

*   `query`: Teks atau kata kunci yang dicari.
*   `searchMode`: Mode pencarian (Frasa, Mengandung, OR, Jarak/Near).
*   `nearDistance`: Jarak maksimal kata untuk mode *Near*.
*   `results`: Kumpulan data `SearchResultItem` yang dipancarkan ke antarmuka pengguna.
*   `isSearching` & `isPaused`: Indikator status siklus hidup (*lifecycle*) pencarian yang sedang aktif.
*   **Indikator Progress:** Properti `totalTables`, `completedTables`, `totalRowsInTable`, dan `completedRowsInTable` digunakan khusus untuk memandu bilah kemajuan (*progress bar*).

---

## Komponen Penyangga & Resolusi Viewport

### 1. SearchResultBuffer (Class)

Untuk mencegah *freezing* antarmuka pengguna saat kueri FTS menghasilkan ribuan hingga ratusan ribu kecocokan dalam hitungan milidetik, `SearchResultBuffer` bertindak sebagai penyangga (*buffer*) adaptif dengan perlindungan `Mutex`:

```swift
final class SearchResultBuffer: Sendable {
    private let state = Mutex(BufferState())
    private let batchSize: Int // Nilai bawaan: 50 item
    private let flushInterval: Duration // Nilai bawaan: 100ms
    private let onFlush: @Sendable ([SearchResultItem]) -> Void
}
```

- **Mekanisme Adaptive Flush**:
  Item hasil pencarian ditampung di dalam memori penyangga. Pengiriman hasil ke `SearchViewModel` (`onFlush`) dipicu ketika salah satu dari dua kondisi terpenuhi:
  1. Jumlah item yang tertampung mencapai ambang batas `batchSize` (50 item).
  2. Interval waktu `flushInterval` (100 ms) berakhir.
- Pendekatan ini meratakan beban *main-thread render* sehingga antarmuka tetap berjalan mulus pada 60/120 fps.

### 2. SearchHitResolver (Class)

Merupakan *singleton* berstatus `@MainActor` yang bertugas menyelesaikan cuplikan teks berformat (`NSAttributedString`) secara *lazy* (sesuai kebutuhan sel tabel yang sedang terlihat di layar):

```swift
@MainActor
final class SearchHitResolver {
    static let shared = SearchHitResolver()
    private let cache = NSCache<NSString, NSAttributedString>() // Batas kapasitas: 1000 entri
    
    func resolveSnippet(
        for item: SearchResultItem,
        keywords: [String],
        mode: SearchMode,
        nearDistance: Int
    ) async -> NSAttributedString?
}
```

- **Alur Resolusi**:
  1. Memeriksa *cache* `NSCache` menggunakan kunci unik `item.id`.
  2. Jika belum tersedia, membaca baris teks spesifik secara langsung dari basis data arsip melalui `LibraryDataManager.shared.fetchSingleContent`.
  3. Membersihkan teks Arab (`cleaningLineBreaks`, `stripSpanTags`), menormalisasi angka (`convertToArabicDigits`), dan mencari rentang kata kunci.
  4. Menyimpan hasil `NSAttributedString` yang telah disorot warnanya ke dalam *cache* 1000 item.

---

## Sub-Komponen (Ekstensi)

Fungsionalitas `SearchViewModel` didistribusikan ke dalam beberapa berkas ekstensi untuk memelihara prinsip *Separation of Concerns*:

### 1. Execution (`Search+Execution.swift`)

Menangani siklus pencarian seperti eksekusi awal (`startSearch`), jeda/lanjutkan (*pause/resume*), dan penghentian *task* (`stopSearch`). Eksekusi dialihkan ke *background thread* melalui `Task.detached` dengan penguncian `Mutex` pada referensi `Task` untuk mencegah akses konkuren ganda.
Di AppKit (macOS), ekstensi ini memanfaatkan *Combine Publishers* seperti `searchDidInitialize` atau `searchProgressDidUpdate`.

### 2. Library (`Search+Library.swift`)

Bertindak sebagai adapter dan delegator menuju `LibraryDataManager` untuk melacak tabel SQLite (*resolve*) terhadap pustaka kitab terkait.

### 3. Observers (`Search+Observers.swift`)

Memantau siaran internal (*NotificationCenter*). Jika direktori penyimpanan basis data perpustakaan diubah, modul ini mereset dan memuat ulang instrumen pencarian secara mandiri.

### 4. Restoration (`Search+Restoration.swift`)

Membaca dan menyimpan cadangan sesi pencarian (`ReaderState`). Mekanisme ini memulihkan hasil pencarian terakhir ketika pengguna membuka kembali kotak dialog tanpa harus melakukan komputasi ulang.

### 5. Saved Results (`Search+SavedResults.swift`)

Menyediakan utilitas pemrosesan teks sorotan (cuplikan rentang kata kunci `NSAttributedString`). Ketika riwayat hasil tersimpan (*Saved Results*) diakses, modul memanfaatkan `ResultBuffer` (*batching*) untuk memuat fragmen secara efisien.

### 6. Ekstensi Spesifik Platform

Memuat abstraksi terisolasi bagi masing-masing platform:

*   **iOS (`Search+iOS.swift`)**: Penerapan *debounce filter* (melalui Combine), pencatatan histori pencarian (*search history*), serta penyesuaian hierarki kategori perpustakaan.
*   **macOS (`Search+macOS.swift`)**: Penyesuaian sinkronisasi pemuatan data ke dalam manajer pustaka macOS.
