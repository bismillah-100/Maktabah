# Book Structure

Dokumen ini adalah artikel arsitektur database dan mapping model untuk modul buku.

Lihat: `Documentation/Optimasi-Penyimpanan.md` untuk detail kompresi ZSTD dan desain FTS hemat ruang.

## Ruang Lingkup

- Database utama di `Managers/Database`
- Mapping data di `Source/Models`
- Transformasi teks: `shorts`, mapping `tabaqa`, kurung `{}`, dan ZSTD
- Alur update buku + rebuild FTS

## Peta Database

`DatabaseManager` membuka dua database inti:

- `Files/main.sqlite` (`DatabaseManager.db`)
- `Files/special.sqlite` (`DatabaseManager.dbSpecial`)

Selain itu aplikasi memakai database archive per nomor:

- `N.sqlite` (contoh `1.sqlite`, `2.sqlite`) berisi konten kitab (`b{bkid}`) + TOC (`t{bkid}`)
- `N_fts.sqlite` berisi indeks FTS5 per tabel kitab (`b{bkid}_fts`)

Fitur Database Pengguna:

- `SearchResults.sqlite` (hasil pencarian tersimpan)
- `Annotations.sqlite` (highlight/underline + catatan)

## Skema Utama

### 1) `main.sqlite`

#### Tabel `0bok`

Kolom yang dipakai aplikasi (lihat `DatabaseManager`):

- `bkid` -> ID buku
- `cat` -> kategori
- `bk` -> judul buku
- `Archive` -> id file archive (`N.sqlite`)
- `betaka` -> metadata/bithoqoh
- `authno` -> relasi penulis ke `Auth`
- `inf` -> info buku
- `TafseerNam` -> nama tafsir (opsional)
- `bVer`/`bver` -> versi buku (dipakai update manager)

#### Tabel `0cat`

- `id` -> ID kategori
- `name` -> nama kategori
- `Lvl` -> level kategori
- `catord` -> urutan tampilan

### 2) `special.sqlite`

#### Tabel `Auth`

Dipakai untuk data penulis:

- `authid`, `auth`, `inf`, `Lng`, `oVer` (dan kolom lain seperti `HigriD` saat update author)

#### Tabel `shorts`

Dipakai untuk ekspansi singkatan teks kitab:

- `Bk` -> ID buku
- `Ramz` -> token singkatan
- `Nass` -> teks pengganti

#### Tabel `rowa`

Dipakai modul perawi:

- `id`, `name`, `AQUAL`, `ROTBA`, `R_ZAHBI`, `sheok`, `telmez`, `IsoName`, `TABAQA`, `WHO`, `birth`, `death`

#### Tabel tarjamah

- `men_b` + `men_b_fts`
- `men_u` + `men_u_fts`

#### Tabel Quran

- `Qr` (ayat)
- `Sora` (nama surat)

### 3) `N.sqlite` (archive kitab)

Per buku:

- `b{bkid}`: konten utama (`id`, `nass`, `page`, `part`, opsional `sora`, `aya`)
- `t{bkid}`: daftar isi/TOC (`id`, `tit`, `lvl`, `sub`)

Catatan:

- Pada state terbaru, `nass` disimpan sebagai `BLOB` terkompres ZSTD.
- Beberapa data lama bisa masih `TEXT`; pembacaan di beberapa path sudah menangani fallback.

### 4) `N_fts.sqlite`

Per buku ada virtual table:

- `b{bkid}_fts` dengan kolom `nass_clean` (`fts5`, `tokenize='unicode61'`)
- `rowid` diset ke `id` baris asli agar join ke `b{bkid}` stabil

## Mapping Database ke Model

### Library

- `0cat` -> `CategoryData`
- `0bok` -> `BooksData`
- `Auth` -> `Muallif`

`LibraryDataManager` membangun hierarki kategori (`CategoryData.children`) dan cache `booksById`.

### Konten Buku

- `b{bkid}` -> `BookContent`
- `t{bkid}` -> `TOC` -> `TOCNode`

`BookConnection` membaca `nass`, melakukan decompress, lalu menghasilkan `BookContent`.

#### Daftar Isi Kitab (`BookConnection.buildTOCTree`)

Masalah data asal Shamela:

- Struktur `t{bkid}` tidak selalu konsisten antar kitab.
- Nilai `lvl`/`sub` bisa tidak ideal.
- Hubungan parent-child tidak tersimpan sebagai foreign key eksplisit.

Strategi yang dipakai saat ini adalah heuristik bertahap:

1. Ambil flat TOC dari `t{bkid}` dengan query:
    - `SELECT id, tit, COALESCE(lvl, 0), COALESCE(sub, 0) ORDER BY id`
2. Buat semua `TOCNode` dulu (pass 1), lalu kelompokkan ke `levelStacks[level]`.
3. Tentukan root awal dari level 1:
    - `level == 1 && sub == 0`
4. Untuk setiap node level > 1, cari parent kandidat dari level terdekat ke atas:
    - cek level `currentLevel - 1` turun sampai `1`
    - pilih parent terakhir dengan `parent.id <= node.id`
5. Jika parent tidak ketemu, node dipromosikan jadi root (fallback agar tidak hilang dari UI).

Catatan penting:

- Mengandalkan asumsi urutan `id` kurang-lebih mengikuti alur dokumen.
- Karena sumber data tidak selalu rapi, fallback “promote to root” adalah kompromi supaya konten tetap tampil.
- Hasil tree di-cache per buku via `tocTreeCache` untuk mengurangi rebuild.
- `Task.isCancelled` dicek berkala agar proses bisa dibatalkan.

### Rawi/Tarjamah

- `rowa` -> `Rowi`
- `men_b`/`men_u` -> `TarjamahMen`
- konten dari `b{bkid}` -> `TarjamahResult`

Model `Rowi` memiliki normalisasi di `didSet` (mis. `aqual`, `rotba`, `sheok`, `telmez`, `who`).

#### Pengelompokan Rowi sesuai Tabaqa (`RowiDataManager.loadData().groupByTabaqa()`)

Masalah data asal Shamela:

- Tabel `rowa` tidak punya kolom hirarki seperti `lvl` (berbeda dengan `0cat`).
- Klasifikasi ada di kolom teks `TABAQA`, formatnya bisa campuran huruf/angka/teks.

Karena itu, struktur Rowi yang dibangun bukan tree multi-level murni, melainkan:

- level 1: `TabaqaGroup` (kode F..P + fallback)
- level 2: daftar `Rowi` di dalam grup

Alur saat ini:

1. `loadData()` memuat data ringan dulu (`id`, `TABAQA`, `IsoName`) untuk semua rowi.
2. Tiap rowi dipetakan ke kode normal melalui `Rowi.getNormalizedTabaqaCode()`.
3. `groupByTabaqa()` membentuk dictionary `[kode: [Rowi]]`.
4. Grup disusun pakai urutan domain tetap `orderedCodes = [F...P]`.
5. Kode sisa masuk fallback group (`Unknown` atau kode mentah).
6. Tiap grup memakai pagination (`initialLoad`/`loadMore`) agar UI tidak render semua item sekaligus.

Konsekuensi desain:

- Tidak ada parent-child berbasis relasi DB, hanya grouping semantik berdasarkan normalisasi `TABAQA`.
- Akurasi grouping sangat bergantung pada aturan parser `getNormalizedTabaqaCode()` dan mapping `TabaqaGroup`.
- Pendekatan ini dipilih karena kompatibel dengan dataset lama yang tidak menyediakan struktur hierarki eksplisit.

## Alur Transformasi Teks

### 1) Decompress `nass` (ZSTD)

Path baca utama (`BookConnection.getContent`, `getFirstContent`, `getContentByPage`, dll):

1. Query kolom `nass` sebagai `Blob`
2. `Data(blob.bytes)` -> `ReusableFunc.decompressData`
3. Hasil plain text dipakai sebagai `BookContent.nash`

Di path search/tarjamah, jika `nass` terbaca sebagai `String`, kode fallback langsung memakai teks tersebut.

### 2) `shorts` mapping

`DatabaseManager.loadShortsForBook(_:)` memuat map `Ramz -> Nass` dari `special.sqlite`.
`BookConnection.applyShortsMapping` mengganti token dengan urutan key terpanjang dulu.

Implikasi:

- Ekspansi singkatan dilakukan setiap fetch konten buku
- Ada cache `shortsCache` per buku untuk mengurangi query ulang

### 3) Kurung `{}` dan rendering teks

`StringExt.cleanedText()`/`cleanedTextWithRanges()`:

- Mengganti literal `\\n` menjadi newline
- Menghapus karakter tertentu (`¬`, `§`)
- Mengubah `{` dan `}` menjadi bentuk kurung Arab (`﴿` / `﴾`) sesuai font aktif
- Pada varian `cleanedTextWithRanges()`, range isi di dalam kurung dicatat untuk pewarnaan UI

### 4) Mapping `tabaqa` / simbol rawi

`RowiModel` + `StringExt` melakukan:

- Ekspansi kode kutub (`mappingRowiKutub`)
- Ekspansi singkatan tunggal (`C`, `E`, `W`, `#`, dll)
- Konversi kode tabaqa (`F`..`P`) ke label Arab
- Normalisasi grouping perawi via `getNormalizedTabaqaCode()`

## Mekanisme Search + FTS

### Search kitab umum

`SearchEngine`:

1. Menyusun FTS query (`phrase` atau `contains`)
2. Menghitung `COUNT(*)` dari `b{bkid}_fts`
3. Mengambil data batch dengan join:
    - FTS table (`b{bkid}_fts`)
    - Tabel konten asli (`b{bkid}`)
4. `nass` hasil join didecompress jika berupa `BLOB`

### Search tarjamah

`TarjamahGlobalManager`:

- `men_b` via `men_b_fts`
- `men_u` via `men_u_fts`
- Konten referensi diambil dari `b{bkid}` sesuai `id`

## Update Buku dan Rebuild Struktur

`BookUpdateManager` melakukan pipeline:

1. Download metadata dan file buku baru
2. Baca `main_update` untuk dapat metadata (`bkid`, `archive`, `bVer`, `link`, dst)
3. Konversi tabel `b{bkid}`:
    - Salin ke temp table
    - Kolom `nass` dikompres ZSTD (`TEXT` -> `BLOB`)
    - Rename kembali ke `b{bkid}`
4. Replace tabel target archive:
    - `b{bkid}`
    - `t{bkid}`
5. Rebuild FTS di `N_fts.sqlite`:
    - Drop/create `b{bkid}_fts`
    - Insert `rowid=id`, `nass_clean=normalize_arabic(nass)`
6. Update/inject metadata `0bok` + update versi (`bVer`)

## Database Pengguna

### `Annotations.sqlite`

Tabel `annotations`:

- `id` id unik anotasi
- `bkId` id buku dari main.sqlite
- `contentId` id konen buku dari N.sqlite
- `startIndex`, `length` startIndex dan panjang anotasi
- `startIndexDiac`, `lengthDiac` startIndex dan panjang anotasi dengan harakat
- `color` warna
- `type` tipe: highligh/underline
- `note` catatan
- `createdAt` tanggal dibuat
- `context` konteks (konten kitab yang diberi tanda)
- `part` bagian
- `page` halaman

Dipetakan ke `Annotation`.

### `SearchResults.sqlite`

- `folders` untuk struktur folder hasil tersimpan
- `results` untuk item hasil (query, archive, bkId, daftar contentId)

Dipetakan ke `SavedResultsItem` / node view model hasil.

## Catatan Implementasi Penting

- Pembacaan konten melakukan decompress per row fetch dan dicache di (`BookPageCache`)  untuk mengurangi dekompresi berulang.
- Ekspansi `shorts` dilakukan setelah decompress; jadi biaya string processing tetap ada di path baca.
- Tidak ada fitur bookmark karena sudah bisa tercakup dalam fitur anotasi untuk kestabilan dan kemudahan pengembangan.

## File Referensi

- `DatabaseManager.swift`
- `BookConnection.swift`
- `BookUpdateManager.swift`
- `AnnotationManager.swift`
- `ResultsHandler.swift`
- `SearchEngine.swift`
- `StringExt.swift`
- `RowiDataManager.swift`
- `TarjamahDataManager.swift`
- `RowiModel.swift`
- `Annotations.swift`
- `Rowi.swift`
