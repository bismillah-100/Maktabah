# Struktur Data Kitab

Dokumen ini menjelaskan arsitektur basis data serta pemetaan model (*model mapping*) untuk modul kitab pada aplikasi Maktabah.

Lihat dokumen [Optimasi Penyimpanan](Optimasi%20Disk.md) untuk rincian kompresi ZSTD dan desain FTS hemat ruang.

## Ruang Lingkup

- Basis data utama pada `Source/Core/Database/`
- Pemetaan model data pada `Source/Features/`
- Transformasi teks: `shorts`, pemetaan `tabaqa`, kurung ayat `{}`, dan ZSTD
- Alur pembaruan buku dan pembangunan ulang (*rebuild*) indeks FTS

## Peta Basis Data

`DatabaseManager` membuka dua berkas basis data inti:

- `Files/main.sqlite` (`DatabaseManager.db`)
- `Files/special.sqlite` (`DatabaseManager.dbSpecial`)

Selain itu, aplikasi menggunakan berkas basis data arsip per nomor:

- `N.sqlite` (misalnya `1.sqlite`, `2.sqlite`) berisi konten kitab (`b{bkid}`) dan daftar isi / TOC (`t{bkid}`).
- `N_fts.sqlite` berisi indeks FTS5 per tabel kitab (`b{bkid}_fts`).

Basis data pengguna:

- `SearchResults.sqlite` (hasil pencarian tersimpan / *bookmarks*)
- `Annotations.sqlite` (sorotan teks, garis bawah, dan catatan)

## Skema Utama

### 1) `main.sqlite`

#### Tabel `0bok`

Kolom yang digunakan aplikasi (lihat `DatabaseManager`):

- `bkid` $\rightarrow$ ID buku
- `cat` $\rightarrow$ ID kategori
- `bk` $\rightarrow$ Judul buku
- `Archive` $\rightarrow$ ID berkas arsip (`N.sqlite`)
- `betaka` $\rightarrow$ Metadata / bithoqoh kitab
- `authno` $\rightarrow$ Relasi penulis ke tabel `Auth`
- `inf` $\rightarrow$ Informasi buku
- `TafseerNam` $\rightarrow$ Nama tafsir (opsional)
- `bVer` / `bver` $\rightarrow$ Versi buku (digunakan oleh *update manager*)

#### Tabel `0cat`

- `id` $\rightarrow$ ID kategori
- `name` $\rightarrow$ Nama kategori
- `Lvl` $\rightarrow$ Tingkat (*level*) kategori dalam hierarki
- `catord` $\rightarrow$ Urutan tampilan kategori

### 2) `special.sqlite`

#### Tabel `Auth`

Digunakan untuk data penulis / pengarang:

- `authid`, `auth`, `inf`, `Lng`, `oVer` (dan kolom lain seperti `HigriD` saat pembaruan data penulis).

#### Tabel `shorts`

Digunakan untuk ekspansi singkatan teks kitab:

- `Bk` $\rightarrow$ ID buku
- `Ramz` $\rightarrow$ Token singkatan
- `Nass` $\rightarrow$ Teks pengganti

#### Tabel `rowa`

Digunakan oleh modul biografi perawi hadis (*Narrator*):

- `id`, `name`, `AQUAL`, `ROTBA`, `R_ZAHBI`, `sheok`, `telmez`, `IsoName`, `TABAQA`, `WHO`, `birth`, `death`

#### Tabel `tarjamah`

- `men_b` dan `men_b_fts`
- `men_u` dan `men_u_fts`

#### Tabel Quran

- `Qr` (teks ayat)
- `Sora` (nama surah)

### 3) `N.sqlite` (Arsip Kitab)

Struktur tabel per buku:

- `b{bkid}`: Konten utama (`id`, `nass`, `page`, `part`, serta opsional `sora`, `aya`).
- `t{bkid}`: Daftar isi / TOC (`id`, `tit`, `lvl`, `sub`).

Catatan:

- Pada format terbaru, kolom `nass` disimpan sebagai `BLOB` terkompresi ZSTD.
- Data versi lama mungkin masih bertipe `TEXT`; alur pembacaan telah menyediakan mekanisme *fallback*.

### 4) `N_fts.sqlite`

Setiap buku memiliki tabel virtual (*virtual table*):

- `b{bkid}_fts` dengan kolom `nass_clean` (`fts5`, `tokenize='unicode61'`).
- `rowid` ditetapkan sama dengan `id` baris asli agar operasi *join* ke `b{bkid}` konsisten.

## Pemetaan Basis Data ke Model

### Perpustakaan (*Library*)

- `0cat` $\rightarrow$ `CategoryData`
- `0bok` $\rightarrow$ `BooksData`
- `Auth` $\rightarrow$ `Muallif`

`LibraryDataManager` membangun struktur hierarki kategori (`CategoryData.children`) dan *cache* `booksById`.

### Konten Kitab

- `b{bkid}` $\rightarrow$ `BookContent`
- `t{bkid}` $\rightarrow$ `TOC` $\rightarrow$ `TOCNode`

`BookConnection` membaca kolom `nass`, melakukan dekompresi ZSTD, kemudian mengembalikan objek `BookContent`.

#### Daftar Isi Kitab (`BookConnection.buildTOCTree`)

Karakteristik data bawaan Shamela:

- Struktur tabel `t{bkid}` tidak selalu konsisten di setiap kitab.
- Nilai `lvl` / `sub` terkadang tidak tersusun secara ideal.
- Relasi induk-turunan (*parent-child*) tidak disimpan sebagai *foreign key* eksplisit.

Strategi yang digunakan adalah pendekatan heuristik bertahap:

1. Mengambil data mentah TOC dari `t{bkid}` dengan kueri:
    - `SELECT id, tit, COALESCE(lvl, 0), COALESCE(sub, 0) ORDER BY id`
2. Menginstansiasi seluruh objek `TOCNode` pada *pass* pertama, kemudian mengelompokkannya ke dalam `levelStacks[level]`.
3. Menentukan *root node* awal dari level 1 (`level == 1 && sub == 0`).
4. Untuk setiap node dengan `level > 1`, sistem mencari *parent node* kandidat dari level terdekat di atasnya:
    - Memeriksa level dari `currentLevel - 1` turun hingga `1`.
    - Memilih *parent* terakhir dengan ketentuan `parent.id <= node.id`.
5. Jika *parent node* tidak ditemukan, node tersebut dipromosikan menjadi *root node* (*fallback* agar konten tidak hilang dari antarmuka pengguna).

Catatan teknis:

- Mengandalkan asumsi bahwa urutan `id` merepresentasikan alur linier dokumen.
- Promosi ke *root node* merupakan kompromi untuk memastikan seluruh bab tetap dapat diakses.
- Hasil struktur hierarki di-*cache* per buku via `tocTreeCache` guna menghindari kalkulasi berulang.
- Pembatalan tugas dipantau secara berkala melalui `Task.isCancelled`.

### Rawi / Tarjamah

- `rowa` $\rightarrow$ `Rowi`
- `men_b` / `men_u` $\rightarrow$ `TarjamahMen`
- Konten dari `b{bkid}` $\rightarrow$ `TarjamahResult`

Model `Rowi` melakukan normalisasi data pada blok `didSet` (seperti `aqual`, `rotba`, `sheok`, `telmez`, `who`).

#### Pengelompokan Perawi Berdasarkan Tabaqa (`RowiDataManager.loadData().groupByTabaqa()`)

Karakteristik data bawaan Shamela:

- Tabel `rowa` tidak memiliki kolom hierarki bertingkat seperti `lvl`.
- Klasifikasi generasi perawi tersimpan pada kolom teks `TABAQA` dengan format gabungan huruf, angka, dan teks.

Oleh karena itu, struktur perawi yang dibentuk berupa hierarki dua tingkat:

- **Tingkat 1**: `TabaqaGroup` (kode `F`..`P` beserta *fallback*).
- **Tingkat 2**: Daftar entitas `Rowi` di dalam grup terkait.

Alur pemrosesan:

1. `loadData()` memuat kolom dasar (`id`, `TABAQA`, `IsoName`) untuk seluruh perawi.
2. Setiap perawi dipetakan ke kode normal melalui `Rowi.getNormalizedTabaqaCode()`.
3. `groupByTabaqa()` membentuk kamus data `[kode: [Rowi]]`.
4. Grup disusun berdasarkan urutan kode domain `orderedCodes = [F...P]`.
5. Kode di luar rentang dimasukkan ke grup *fallback* (`Unknown` atau kode mentah).
6. Setiap grup menerapkan pemuatan bertahap (*pagination* via `initialLoad` dan `loadMore`) untuk menjaga efisiensi rendering antarmuka pengguna.

## Alur Transformasi Teks

### 1) Dekompresi `nass` (ZSTD)

Alur Pembacaan Utama (*Main Read Path*) (`BookConnection.getContent`, `getFirstContent`, `getContentByPage`, dll.):

1. Menjalankan kueri kolom `nass` sebagai `Blob`.
2. Mengonversi `Data(blob.bytes)` $\rightarrow$ `ReusableFunc.decompressData`.
3. Teks hasil dekompresi disimpan ke dalam `BookContent.nash`.

Pada alur pencarian atau tarjamah, jika `nass` terbaca langsung sebagai `String`, sistem langsung menggunakan teks tersebut sebagai *fallback*.

### 2) Pemetaan Singkatan `shorts`

`DatabaseManager.loadShortsForBook(_:)` memuat peta `Ramz -> Nass` dari `special.sqlite`.
`BookConnection.applyShortsMapping` mengganti token singkatan secara berurutan mulai dari kunci (*key*) terpanjang.

Implikasi arsitektur:

- Ekspansi singkatan dieksekusi pada setiap pembacaan konten buku.
- Terdapat `shortsCache` per buku untuk meminimalkan kueri basis data berulang.

### 3) Kurung Teks Ayat `{}` dan Rendering Tipografi

Fungsi `StringExt.cleanedText()` dan `cleanedTextWithRanges()`:

- Mengonversi *literal* `\\n` menjadi karakter baris baru (*newline*).
- Menghapus karakter pemisah khusus (`¬`, `§`).
- Mengubah tanda kurung `{` dan `}` menjadi kurung ayat Arab (`﴿` / `﴾`) sesuai *font* aktif.
- Pada varian `cleanedTextWithRanges()`, rentang teks di dalam kurung dicatat untuk kebutuhan penyorotan warna (*syntax highlighting*) pada UI.

### 4) Pemetaan `tabaqa` dan Simbol Perawi

`RowiModel` dan `StringExt` menangani:

- Ekspansi kode kitab hadis (`mappingRowiKutub`).
- Ekspansi singkatan tunggal (`C`, `E`, `W`, `#`, dll.).
- Konversi kode tabaqa (`F`..`P`) ke label bahasa Arab.
- Normalisasi pengelompokan perawi via `getNormalizedTabaqaCode()`.

## Mekanisme Pencarian & FTS

### Pencarian Kitab Umum

`SearchEngine`:

1. Menyusun kueri FTS (mode `phrase`, `contains`, `or`, atau `near`).
2. Menghitung `COUNT(*)` dari tabel `b{bkid}_fts`.
3. Mengambil data dalam *batch* menggunakan operasi *join*:
    - Tabel FTS (`b{bkid}_fts`)
    - Tabel konten utama (`b{bkid}`)
4. Melakukan dekompresi ZSTD pada kolom `nass` hasil *join* jika berupa `BLOB`.

### Pencarian Tarjamah Perawi

`TarjamahGlobalManager`:

- Mengakses `men_b` melalui indeks `men_b_fts`.
- Mengakses `men_u` melalui indeks `men_u_fts`.
- Mengambil konten referensi dari `b{bkid}` berdasarkan `id`.

## Pembaruan Buku dan Pembangunan Ulang Indeks

`BookUpdateManager` menjalankan alur *pipeline* berikut:

1. Mengunduh metadata dan berkas buku baru.
2. Membaca tabel `main_update` untuk mendapatkan metadata (`bkid`, `archive`, `bVer`, `link`, dll.).
3. Mengonversi tabel `b{bkid}`:
    - Menyalin ke tabel sementara.
    - Mengompresi kolom `nass` menggunakan ZSTD (`TEXT` $\rightarrow$ `BLOB`).
    - Mengubah nama tabel kembali ke `b{bkid}`.
4. Mengganti tabel target pada arsip:
    - `b{bkid}`
    - `t{bkid}`
5. Membangun ulang indeks FTS pada `N_fts.sqlite`:
    - Menghapus dan membuat ulang (*drop/create*) `b{bkid}_fts`.
    - Memasukkan data dengan `rowid = id` dan `nass_clean = normalize_arabic(nass)`.
6. Memperbarui metadata `0bok` serta nomor versi (`bVer`).

## Basis Data Pengguna

### `Annotations.sqlite`

Tabel `annotations`:

- `id`: Pengenal unik anotasi (UUID).
- `bkId`: ID buku dari `main.sqlite`.
- `contentId`: ID konten buku dari berkas `N.sqlite`.
- `startIndex`, `length`: Indeks awal dan panjang rentang teks anotasi.
- `startIndexDiac`, `lengthDiac`: Indeks awal dan panjang rentang teks pada mode berharakat.
- `color`: Kode warna sorotan (*hex*).
- `type`: Tipe anotasi (*highlight* / *underline*).
- `note`: Teks catatan pengguna.
- `createdAt`: Waktu pembuatan anotasi (UNIX *timestamp*).
- `context`: Cuplikan teks kitab yang dianotasi.
- `part`: Nomor jilid/bagian.
- `page`: Nomor halaman.

Data ini dipetakan ke model `Annotation`.

### `SearchResults.sqlite`

- `folders`: Menyimpan struktur hierarki folder untuk hasil pencarian yang disimpan (*bookmarks*).
- `results`: Menyimpan entitas hasil pencarian (`query`, `archive`, `bkId`, daftar `contentId`).

Data ini dipetakan ke model `SavedResultsItem` dan node tampilan hasil pencarian.

## Catatan Implementasi Penting

- Pembacaan konten melakukan dekompresi ZSTD pada setiap pengambilan baris dan menyimpannya ke `BookPageCache` untuk meminimalkan beban CPU berulang.
- Ekspansi singkatan `shorts` dilakukan setelah tahap dekompresi.
- Fitur markah buku (*bookmarks*) diintegrasikan dengan modul penyimpanan hasil pencarian guna menjaga konsistensi arsitektur dan kemudahan pemeliharaan kode.

## Berkas Referensi Terkait

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
