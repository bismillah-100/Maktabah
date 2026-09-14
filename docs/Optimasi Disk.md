# Optimasi Penyimpanan

Catatan ini menjelaskan kenapa penyimpanan buku dipecah menjadi dua optimasi:

1. `nass` dikompres pakai ZSTD (level 10).
2. indeks FTS dipisah ke file terpisah dan dibuat `content=''`.

Tujuannya sederhana: ukuran data tetap masuk akal, tapi alur baca dan search tidak berubah dari sisi fitur.

## Tujuan

Data kitab besar. Kalau semua disimpan mentah sebagai teks, ukuran total cepat naik (secara praktis bisa lewat 20 GB).

Karena itu, di proyek ini dipakai pola:

- file konten utama: `N.sqlite`
- file indeks pencarian: `N_fts.sqlite`

## Struktur singkat

Untuk satu archive:

- `N.sqlite` menyimpan tabel utama `b{bkid}` (konten) dan `t{bkid}` (TOC).
- `N_fts.sqlite` menyimpan `b{bkid}_fts` untuk full-text search.

Dengan pola ini, konten dan indeks dipisah jelas.

## Kompresi `nass` (ZSTD)

### Apa yang disimpan

Kolom `nass` di tabel `b{bkid}`.

- data lama bisa masih `TEXT`
- data hasil update dikonversi menjadi `BLOB` terkompres

### Kapan kompresi jalan

Saat update buku (`BookUpdateManager.convertBookDatabase`):

1. membuat tabel sementara `b{bkid}_zstd`
2. menyalin semua kolom
3. khusus `nass`, kolom dikompres dengan `ReusableFunc.compressData`
4. timpa tabel lama dengan tabel baru

Setelah tahap ini, tabel buku langsung dalam format hemat ruang.

### Kapan dekompresi jalan

Saat baca row konten (`BookConnection.getContent`, `getFirstContent`, `getContentByPage`, dan path sejenis):

1. `nass` dibaca sebagai `Blob`
2. diubah ke `Data`
3. didekompres via `ReusableFunc.decompressData`
4. baru masuk pipeline teks lain (mis. mapping `shorts`)

### Dampaknya

- ukuran file archive turun cukup besar
- ada biaya CPU saat read
- beban baca berulang ditolong cache (`BookPageCache`)

## FTS hemat ruang (`content=''`)

### Bentuk tabel FTS

Untuk setiap buku dibuat:

- `b{bkid}_fts`
- skema: `fts5(nass_clean, content='', tokenize='unicode61')`

`content=''` sengaja dipakai supaya FTS tidak menyimpan salinan isi kitab lagi.

### Cara isi indeks

Saat update archive (`BookUpdateManager.replaceArchiveDatabase`):

1. replace dulu tabel utama (`b{bkid}` dan `t{bkid}`)
2. drop/create ulang `b{bkid}_fts` di `N_fts.sqlite`
3. insert data FTS dengan:
    - `rowid = id` dari tabel utama
    - `nass_clean = normalize_arabic(nass)`

Normalisasi Arab dipakai supaya matching query lebih stabil.

### Cara dipakai saat search

Pencarian tidak berhenti di FTS saja. Alurnya:

1. `MATCH` di `b{bkid}_fts`
2. join ke `b{bkid}` pakai `rowid = id`
3. ambil `nass/page/part`, lalu dekompres kalau `nass` adalah `BLOB`

Jadi FTS hanya jadi indeks, bukan sumber konten utama.

## Hal yang wajib dijaga

- `rowid` di FTS harus selalu sama dengan `id` di tabel `b{bkid}`.
- hasil update baru harus menyimpan `nass` sebagai `BLOB` terkompres.
- rebuild FTS wajib dilakukan setelah replace tabel buku.

Kalau salah satu poin ini meleset, hasil search bisa tidak sinkron dengan konten.

## Ringkasan

- ZSTD mengurangi ukuran konten utama.
- FTS `content=''` mengurangi ukuran indeks.
- Keduanya dipakai bersamaan supaya storage tetap terkontrol untuk koleksi kitab besar.
