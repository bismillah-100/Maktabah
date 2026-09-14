# Persistence & Database

Pengelolaan data Al-Qur'an dan Tafsir berpusat pada `QuranDataManager`.

## `QuranDataManager`

Sebuah *singleton* yang mengelola koneksi basis data khusus (`special.sqlite`) dan mengoordinasikan pembacaan teks ayat Al-Qur'an serta kitab-kitab tafsir.

### Tanggung Jawab Utama

- **Memuat Surah & Ayat**: Mengambil data dari tabel `Qr` dan `Sora` di basis data `special.sqlite`.
- **Memuat Kitab Tafsir**: Memfilter daftar kitab di `LibraryDataManager` yang memiliki kategori Tafsir (ID 127 atau 70) dan memiliki nama tafsir (`tafseerNam`).
- **Membaca Konten**: Menggunakan `BookConnection` untuk menghubungkan arsip SQLite dan mengambil konten dari kitab tafsir pada surah dan ayat spesifik melalui `loadTafseer(for:in:)`.
- **Navigasi Halaman**: Menyediakan fungsi `nextPage()` dan `prevPage()` untuk membaca halaman tafsir berikutnya atau sebelumnya.
- **Pencarian**: Mendukung pencarian nama surah (`searchSurah`) dan pencarian kitab tafsir (`searchTafseerBooks`).

### Skema Tabel di `special.sqlite`

- **`Qr`**: Menyimpan teks ayat Al-Qur'an (`nass`), nomor surah (`sora`), nomor ayat (`aya`), dan nomor halaman mushaf (`Page`).
- **`Sora`**: Menyimpan metadata surah, termasuk nama surah dalam bahasa Arab (`sora`).
