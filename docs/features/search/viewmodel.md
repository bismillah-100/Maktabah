# State Management

Manajemen *state* di modul Search ditangani oleh `SearchViewModel`, yang diakselerasi dengan makro `@Observable` (Swift 5.9) untuk integrasi reaktif dengan antarmuka SwiftUI maupun *binding* data ke UIKit dan AppKit (melalui `Combine` atau `Observation`).

## Komponen `SearchViewModel`

ViewModel ini mengkoordinasikan antrean *multithread* dari `SearchEngine` dan mengemasnya untuk dikonsumsi lapis presentasi (UI).

### State Utama

*   `query`: Teks atau kata kunci yang dicari.
*   `searchMode`: Mode pencarian (Frasa, Mengandung, OR, Jarak/Near).
*   `nearDistance`: Jarak maksimal kata untuk mode *Near*.
*   `results`: Kumpulan data `SearchResultItem` yang disiarkan ke antarmuka.
*   `isSearching` & `isPaused`: Indikator status siklus hidup (*lifecycle*) pencarian yang sedang aktif.
*   **Indikator Progress:** Properti `totalTables`, `completedTables`, `totalRowsInTable`, dan `completedRowsInTable` digunakan khusus untuk memandu presentasi bilah kemajuan (*progress bar*).

### Sub-Komponen (Ekstensi)

Untuk memitigasi kompleksitas tipe (*Separation of Concerns*), fungsi di dalam `SearchViewModel` didistribusikan ke dalam beberapa berkas ekstensi.

#### 1. Execution (`Search+Execution.swift`)

Menangani siklus pencarian seperti eksekusi awal (`startSearch`), eksekusi jeda/lanjut, dan penghentian paksa (`stopSearch`). Eksekusi dialihkan ke dalam *background thread* melalui `Task.detached` dengan `Mutex` *lock* pada referensi `Task` untuk memitigasi isu akses konkuren.
Di AppKit (macOS), ekstensi ini memanfaatkan serangkaian pemancar nilai (*Combine Publishers*) seperti `searchDidInitialize` atau `searchProgressDidUpdate`.

#### 2. Library (`Search+Library.swift`)

Bertindak sebagai adapter dan delegator menuju `LibraryDataManager`. Modul ini membantu melacak tabel SQLite (*resolve*) terhadap pustaka kitab terkait.

#### 3. Observers (`Search+Observers.swift`)

Berperan memantau siaran internal (*NotificationCenter*). Jika pengguna mengubah direktori penyimpanan library (basis data SQLite) melalui Pengaturan, modul ini mereset dan memuat ulang instrumen secara mandiri.

#### 4. Restoration (`Search+Restoration.swift`)

Membaca dan menyimpan cadangan sesi pencarian (`ReaderState`). Mekanisme ini memulihkan hasil pencarian terakhir ketika pengguna membuka kembali kotak dialog tanpa harus menghabiskan komputasi ulang.

#### 5. Saved Results (`Search+SavedResults.swift`)

Menyediakan utilitas penyelesaian teks sorotan (cuplikan rentang kata kunci `NSAttributedString`). Ketika riwayat "Saved Results/Bookmark" diakses, modul memanfaatkan `ResultBuffer` (*batching*) untuk memuat fragmen secara efisien.

#### 6. Ekstensi Berdasarkan Platform

Memuat abstraksi terisolasi bagi masing-masing OS:

*   **iOS (`Search+iOS.swift`)**: Penerapan metode *debounce filter* (melalui `Combine`), pelacakan riwayat (*search history*), serta modifikasi tata hierarki data kategori perpusakaan UI.
*   **macOS (`Search+macOS.swift`)**: Persiapan sinkronisasi muat perpusakaan khusus ke dalam manajer *library* macOS.
