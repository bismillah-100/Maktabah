# Optimasi Penyimpanan

Catatan ini memaparkan alasan pemisahan strategi optimasi penyimpanan buku menjadi dua bagian:

1. Kolom `nass` dikompresi menggunakan Zstandard (ZSTD level 10).
2. Indeks FTS dipisahkan ke berkas tersendiri dengan konfigurasi `content=''`.

Tujuannya adalah menjaga ukuran data tetap ringkas tanpa mengubah perilaku fitur pembacaan maupun pencarian.

## Tujuan

Ukuran data kitab sangat besar. Jika seluruh konten disimpan dalam bentuk teks mentah tanpa kompresi, total ukuran basis data dapat melampaui 20 GB.

Oleh karena itu, proyek ini menerapkan pemisahan berkas:

- Berkas konten utama: `N.sqlite`
- Berkas indeks pencarian: `N_fts.sqlite`

## Struktur Berkas

Untuk setiap arsip (*archive*):

- `N.sqlite` menyimpan tabel utama `b{bkid}` (konten) dan `t{bkid}` (TOC / daftar isi).
- `N_fts.sqlite` menyimpan `b{bkid}_fts` untuk *full-text search* (FTS5).

Dengan pendekatan ini, berkas konten dan indeks terpisah secara tegas.

## Kompresi `nass` (ZSTD)

### Data yang Disimpan

Kolom `nass` pada tabel `b{bkid}`:

- Data lama mungkin masih bertipe `TEXT`.
- Data hasil pembaruan dikonversi menjadi `BLOB` terkompresi ZSTD.

### Waktu Pelaksanaan Kompresi

Saat pembaruan buku (`BookUpdateManager.convertBookDatabase`):

1. Membuat tabel sementara `b{bkid}_zstd`.
2. Menyalin seluruh kolom data.
3. Mengompresi kolom `nass` menggunakan `ReusableFunc.compressData`.
4. Mengganti tabel lama dengan tabel baru yang telah terkompresi.

Setelah tahap ini selesai, tabel buku langsung tersimpan dalam format terkompresi yang hemat ruang.

### Waktu Pelaksanaan Dekompresi

Saat membaca baris konten (`BookConnection.getContent`, `getFirstContent`, `getContentByPage`, dan *path* sejenis):

1. Kolom `nass` dibaca sebagai `Blob`.
2. Dikonversi ke tipe `Data`.
3. Didekompresi melalui `ReusableFunc.decompressData`.
4. Diteruskan ke *pipeline* pemrosesan teks berikutnya (misalnya pemetaan singkatan `shorts`).

### Dampak Performa & Penyimpanan

- Ukuran berkas arsip menyusut secara signifikan.
- Terdapat beban komputasi CPU tambahan saat proses dekompresi data.
- Beban pembacaan berulang diringankan oleh mekanisme *cache* (`BookPageCache`).

## FTS Hemat Ruang (`content=''`)

### Bentuk Tabel FTS

Untuk setiap buku, sistem membuat:

- `b{bkid}_fts`
- Skema: `fts5(nass_clean, content='', tokenize='unicode61')`

Konfigurasi `content=''` sengaja digunakan agar tabel FTS tidak menduplikasi isi teks kitab.

### Alur Pengisian Indeks

Saat pembaruan arsip (`BookUpdateManager.replaceArchiveDatabase`):

1. Memperbarui tabel utama (`b{bkid}` dan `t{bkid}`) terlebih dahulu.
2. Membuat ulang (*drop/create*) tabel `b{bkid}_fts` pada `N_fts.sqlite`.
3. Memasukkan data ke tabel FTS dengan ketentuan:
    - `rowid = id` dari tabel utama.
    - `nass_clean = normalize_arabic(nass)`.

Normalisasi teks Arab diterapkan agar pencocokan kueri (*query matching*) lebih konsisten dan akurat.

### Mekanisme Eksekusi saat Pencarian

Proses pencarian tidak hanya mengandalkan FTS, melainkan melalui alur berikut:

1. Menjalankan kueri `MATCH` pada tabel `b{bkid}_fts`.
2. Melakukan operasi *join* ke tabel `b{bkid}` menggunakan kondisi `rowid = id`.
3. Mengambil kolom `nass`, `page`, dan `part`, kemudian melakukan dekompresi jika `nass` berupa `BLOB`.

Dengan demikian, tabel FTS murni berfungsi sebagai indeks pencarian dan bukan sebagai penyimpan konten utama.

## Ketentuan yang Wajib Dijaga

- Nilai `rowid` pada tabel FTS harus selalu identik dengan `id` pada tabel `b{bkid}`.
- Data pembaruan baru wajib menyimpan kolom `nass` sebagai `BLOB` terkompresi ZSTD.
- Proses *rebuild* FTS wajib dijalankan setelah mengganti tabel buku.

Apabila salah satu ketentuan ini terlewatkan, hasil pencarian tidak akan sinkron dengan konten buku.

## Ringkasan

- ZSTD mengurangi ukuran penyimpanan konten utama.
- FTS `content=''` meminimalkan ukuran indeks pencarian.
- Keduanya diterapkan bersamaan agar penggunaan ruang penyimpanan tetap efisien untuk koleksi kitab berskala besar.
