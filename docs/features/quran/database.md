# Persistence & Database

Pengelolaan data Al-Quran dan Tafsir berpusat pada `QuranDataManager`.

## `QuranDataManager`

Sebuah _singleton_ yang mengelola koneksi database khusus (`special.sqlite`) dan mengoordinasikan pembacaan data Al-Quran serta buku-buku tafsir.

### Tanggung Jawab Utama

- **Memuat Surah & Ayat**: Mengambil data dari tabel `Qr` dan `Sora` di database khusus.
- **Memuat Tafsir**: Memfilter daftar buku di `LibraryDataManager` yang memiliki kategori Tafsir (ID 127 atau 70) dan memiliki nama tafsir (`tafseerNam`).
- **Membaca Konten**: Menggunakan `BookConnection` untuk menghubungkan arsip SQLite dan mengambil konten dari buku tafsir pada surah dan ayat yang spesifik menggunakan `loadTafseer(for:in:)`.
- **Navigasi Halaman**: Menyediakan fungsi `nextPage()` dan `prevPage()` untuk membaca halaman tafsir selanjutnya atau sebelumnya.
- **Pencarian**: Memungkinkan pencarian pada nama Surah (`searchSurah`) dan pencarian buku tafsir (`searchTafseerBooks`).

### Tabel Terkait di `special.sqlite`

- **`Qr`**: Menyimpan teks ayat Al-Quran (`nass`), nomor surah (`sora`), nomor ayat (`aya`), dan nomor halaman (`Page`).
- **`Sora`**: Menyimpan metadata surah, termasuk nama surah (`sora`).
