# macOS (AppKit)

Fitur Quran menggunakan AppKit dengan struktur `NSSplitView` yang terdiri dari beberapa *pane*.

## `QuranSplitVC`

Bertindak sebagai *container* utama yang menyatukan tiga komponen *sidebar* dan *content* menggunakan custom `NSSplitView`. 

Alur kerja:

- Menangani aksi pemilihan buku dari `QuranTafseerVC` dan menginisiasi pengunduhan/penyiapan arsip via `BookIntegrateModalCenter`.
- Menghubungkan navigasi dari `QuranNashVC` kembali ke *sidebar* (sinkronisasi UI saat halaman berpindah).

## `QuranSidebarVC`

Menampilkan hierarki Surah dan Ayat menggunakan `NSOutlineView`.

- **Fitur**: Pencarian nama surah, dan pemetaan posisi ayat (*lookup* dengan kerumitan O(1)) untuk _scrolling_ instan.
- **Delegasi**: Menggunakan `QuranDelegate` untuk mengirim data ayat yang dipilih ke `QuranNashVC`.

## `QuranTafseerVC`

Menampilkan daftar buku tafsir dalam `NSTableView`.

- Mengambil daftar buku dari `QuranDataManager.tafseerBooks` yang telah difilter.
- Memiliki fitur pencarian nama kitab tafsir secara *real-time*.

## `QuranNashVC`

Menampilkan teks ayat dan tafsir menggunakan custom `IbarotTextView`.

- Mendengar interaksi lewat implementasi `QuranDelegate`.
- Menangani fitur pencarian di dalam teks tafsir (*Search Current Book*) melalui `OptionSearchVC` yang muncul di `NSPopover`.
- Mengontrol navigasi halaman selanjutnya dan sebelumnya.

## `QuranWindow`

Komponen jendela utama (Window Controller) khusus untuk fitur Quran.
