# Optimasi Penyimpanan

Catatan ini memaparkan strategi arsitektur dan optimasi penyimpanan data kitab pada aplikasi Maktabah:

1. **Kompresi Konten Zstandard (ZSTD Level 10)** pada kolom `nass`.
2. **Indeks Pencarian Terpadu (Unified FTS5)** dengan konfigurasi `content=''` dan **Bitwise Packed RowID**.
3. **Penyangga Aliran & Resolusi Malas** (`SearchResultBuffer` dan `SearchHitResolver`) untuk meminimalkan beban memori kerja (RAM).

Tujuannya adalah menjaga ukuran data tetap ringkas tanpa mengorbankan performa pembacaan maupun pencarian skala besar melintasi jutaan halaman.

---

## 1. Tujuan & Tantangan Skala

Ukuran koleksi kitab Maktabah Syamilah sangat masif (mencapai lebih dari 7.000 kitab). Jika seluruh konten disimpan dalam bentuk teks mentah tanpa kompresi, total ukuran basis data dapat melampaui 20 GB.

Oleh karena itu, proyek ini menerapkan pemisahan berkas basis data per arsip:

- **Berkas Konten Utama (`N.sqlite`)**: Menyimpan tabel data `b{bkid}` (konten) dan `t{bkid}` (daftar isi/TOC).
- **Berkas Indeks Pencarian (`N_fts.sqlite`)**: Menyimpan indeks pencarian terpadu `archive_fts` dan pemetaan metadata `archive_index` (atau tabel warisan `b{bkid}_fts` untuk arsip lama).

---

## 2. Kompresi Konten `nass` (Zstandard)

### Data yang Disimpan

Kolom `nass` pada tabel kitab `b{bkid}`:
- Data hasil pembaruan dikonversi menjadi `BLOB` terkompresi ZSTD (Level 10).
- Data versi lama yang masih bertipe `TEXT` tetap didukung melalui alur pembacaan adaptif (*backward compatibility*).

### Waktu Pelaksanaan Kompresi

Saat proses impor atau integrasi kitab (`BookUpdateManager` / `BookArchiveIntegrator`):
1. Membuat tabel sementara `b{bkid}_zstd`.
2. Menyalin kolom metadata (`id`, `page`, `part`).
3. Mengompresi teks kolom `nass` menjadi BLOB menggunakan pustaka C Zstandard tingkat rendah (`ZstdDecompressor.compressData`).
4. Mengganti tabel lama dengan tabel baru yang telah terkompresi.

### Waktu Pelaksanaan Dekompresi

Saat membaca baris konten (`BookConnection.getContent` atau saat sel pencarian terlihat di layar):
1. Kolom `nass` dibaca sebagai `BLOB`.
2. Didekompresi melalui `ZstdDecompressor` menggunakan *context pool* (`ZSTDContextPool`) untuk menghindari *overhead* alokasi memori berulang.
3. Hasil pembacaan disimpan sementara di *cache* halaman (`BookPageCache`) untuk mempercepat navigasi berikutnya.

---

## 3. Arsitektur Unified FTS5 & Bitwise Packed RowID

Pada generasi awal Maktabah, setiap buku memiliki tabel virtual FTS5 individual (`b{bkid}_fts`). Meskipun menggunakan `content=''`, memiliki 300+ tabel virtual di setiap berkas arsip menimbulkan pemborosan metadata B-Tree SQLite yang signifikan serta fragmentasi I/O.

### Mengapa Beralih ke Unified FTS?

Dalam skema **Unified FTS5**, seluruh kitab di dalam satu arsip disatukan ke dalam satu tabel virtual `archive_fts` dan satu tabel indeks reguler `archive_index`:

1. **Penghematan Metadata B-Tree**: Mengeliminasi ribuan tabel virtual internal (`%_data`, `%_idx`, `%_config`) SQLite FTS5, menghemat ratusan megabyte ruang *disk*.
2. **Page Cache Locality**: Indeks FTS terkonsentrasi pada segmen pohon terpadu, memaksimalkan efisiensi *cache* memori OS.

### Inovasi Bitwise Packed RowID

Untuk membedakan halaman antar-buku di dalam satu tabel FTS tanpa mengotori kamus kata FTS5, Maktabah menerapkan pengemasan bitwise 64-bit pada `rowid`:

$$\text{packedRowId} = (\text{bookId} \ll 32) \mid (\text{rowId} \ \& \ \text{0xFFFFFFFF})$$

- **Zero Posting List Overhead:**
  Tidak ada token buatan seperti `bk_123` yang disuntikkan ke dalam teks Arab. Ukuran berkas FTS5 dan kamus kata FST sama sekali tidak membengkak.
- **Binary Seek & Early Cutoff Alami:**
  Di SQLite FTS5, seluruh *posting list* disimpan terurut menaik (*ascending*) berdasarkan `rowid`. Ketika kueri memfilter rentang buku tertentu:
  $$\text{f.rowid BETWEEN } (\text{bookId} \ll 32) \text{ AND } ((\text{bookId} \ll 32) \mid \text{0xFFFFFFFF})$$
  mesin FTS5 (`xFilter`) langsung melakukan *binary search* ke posisi `minRowId`, membaca hanya kecocokan di dalam rentang tersebut, dan **seketika berhenti (*early break*)** begitu membaca `rowid > maxRowId`. Seluruh data ribuan buku lain dilewati tanpa sentuhan I/O.

---

## 4. Efisiensi Transaksi Migrasi (1 Commit vs 300 Commit)

Setiap perintah `COMMIT` pada SQLite FTS5 memicu proses penggabungan segmen indeks (*segment merge*) pada B-Tree.

- **Kelemahan Skema Lama:** Melakukan transaksi per-buku (300+ kali `COMMIT`) menyebabkan *I/O thrashing* parah karena mesin FTS5 dipaksa menulis ulang struktur indeks ratusan kali.
- **Optimasi Migrasi Modern:** Skrip migrasi terkompilasi (`Scripts/migrate_unified_fts.swift`) membungkus seluruh buku di satu arsip dalam **1 Transaksi Tunggal (`BEGIN TRANSACTION` ... `COMMIT`)**:
  - Seluruh segmen FTS5 ditampung di dalam *RAM cache* (1 GB via `PRAGMA cache_size = -1048576` dan `PRAGMA mmap_size = 1GB`).
  - Proses *segment merge* hanya terjadi 1 kali di akhir transaksi.
  - Mempercepat proses migrasi hingga **3x s.d. 5x** dan menjamin sifat atomik 100% (*zero corrupted state* jika terjadi kegagalan).

---

## 5. Ringkasan Penghematan Ruang & Memori

| Komponen | Strategi Optimasi | Dampak Penghematan |
| :--- | :--- | :--- |
| **Konten Kitab (`b{id}`)** | Kompresi ZSTD Level 10 | Mengurangi ukuran berkas konten hingga ~65% |
| **Indeks Pencarian** | FTS5 `content=''` | Tidak ada duplikasi teks mentah di tabel pencarian |
| **Arsitektur FTS** | Unified FTS (`archive_fts`) | Mengurangi ribuan tabel virtual & metadata B-Tree |
| **Posting List FTS** | Bitwise `packedRowId` | Nol overhead ukuran kamus kata (*Zero index bloat*) |
| **Memori Tampilan (UI)** | `SearchHitResolver` (Lazy Snippet) | Penghematan RAM signifikan saat menemukan ratusan ribu hasil |
