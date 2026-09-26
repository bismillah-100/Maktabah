# macOS Implementation (AppKit)

Fitur Quran pada macOS menggunakan arsitektur AppKit dengan struktur `NSSplitViewController` yang terdiri dari tiga panel (*three-pane layout*).

## QuranSplitVC (Class)

Bertindak sebagai kontainer utama yang menyatukan panel *sidebar*, panel teks Al-Qur'an, dan panel kitab tafsir:

- Menangani aksi pemilihan buku dari `QuranTafseerVC` melalui *closure* terisolasi `@MainActor` (`Task { ... }`), mewarisi konteks UI secara langsung saat mengoordinasikan pemuatan data tafsir dan menyajikan pesan peringatan (*alert dialog*) tanpa *hop thread* manual.
- Menghubungkan navigasi dari `QuranNashVC` kembali ke *sidebar* (sinkronisasi UI saat halaman berpindah).

## QuranSidebarVC (Class)

Menampilkan hierarki Surah dan Ayat menggunakan `NSOutlineView`.

- **Fitur**: Pencarian nama surah dan pemetaan posisi ayat dengan kompleksitas $O(1)$ untuk pengguliran instan.
- **Delegasi**: Menggunakan `QuranDelegate` untuk mengirim data ayat yang dipilih ke `QuranNashVC`.

## QuranTafseerVC (Class)

Menampilkan daftar kitab tafsir yang tersedia dalam `NSTableView`.

- Mengambil daftar kitab dari `QuranDataManager.tafseerBooks` yang telah difilter berdasarkan kategori tafsir.

## QuranNashVC (Class)

Panel utama yang menyajikan teks ayat mushaf beserta penjelasan tafsirnya:

- Menampilkan teks Arab dengan format tipografi yang dapat disesuaikan.
- Mendukung tombol navigasi halaman berikutnya dan sebelumnya (*paging*).
